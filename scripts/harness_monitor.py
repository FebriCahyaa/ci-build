#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE = os.environ.get("HARNESS_BASE", "https://app.harness.io")
ACCOUNT = os.environ["HARNESS_ACCOUNT"]
ORG = os.environ.get("HARNESS_ORG", "default")
PROJECT = os.environ.get("HARNESS_PROJECT", "ci_build")
PIPELINE = os.environ.get("HARNESS_PIPELINE", "Universal_Kernel_Build")
PLAN = os.environ["HARNESS_PLAN_EXECUTION_ID"]
POLL = max(5, int(os.environ.get("HARNESS_POLL_SECONDS", "10")))
TG_TOKEN = os.environ.get("TG_BOT_TOKEN", "")
TG_CHAT = os.environ.get("TG_CHAT_ID", "")
TG_TOPIC = os.environ.get("TG_TOPIC_ID", "")
DEVICE = os.environ.get("DEVICE", "unknown")
BRANCH = os.environ.get("KERNEL_BRANCH", "unknown")
OUT = Path(os.environ.get("HARNESS_MONITOR_FILE", "harness-monitor.json"))
RUN_URL = os.environ.get("HARNESS_EXECUTION_URL", "")

TERMINAL = {"SUCCEEDED","SUCCESS","FAILED","FAILURE","ERROR","ERRORED","ABORTED","EXPIRED","REJECTED","STOPPED","CANCELED"}
ACTIVE = {"RUNNING","IN_PROGRESS","QUEUED","NOT_STARTED","PAUSED","WAITING"}


def norm(v: object) -> str:
    return str(v or "").strip().upper().replace("-", "_").replace(" ", "_")


def api_get(path: str) -> object:
    req = urllib.request.Request(
        f"{BASE}{path}",
        headers={"x-api-key": os.environ["HARNESS_API_KEY"], "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def status_of(obj: object) -> str:
    if isinstance(obj, dict):
        # Harness API envelope has its own "status" field.
        # The actual pipeline state is inside data.planExecution.
        data = obj.get("data")

        if isinstance(data, dict):
            plan_execution = data.get("planExecution")

            if isinstance(plan_execution, dict):
                for key in (
                    "status",
                    "pipelineStatus",
                    "executionStatus",
                    "state",
                ):
                    val = plan_execution.get(key)
                    if isinstance(val, str) and val.strip():
                        return val

            for key in ("pipelineExecutionSummary", "executionData"):
                nested = data.get(key)
                if isinstance(nested, (dict, list)):
                    found = status_of(nested)
                    if found:
                        return found

        # Only use these as fallback.
        for key in (
            "pipelineStatus",
            "executionStatus",
            "state",
        ):
            val = obj.get(key)
            if isinstance(val, str) and val.strip():
                return val

        return ""

    if isinstance(obj, list):
        for item in obj:
            found = status_of(item)
            if found:
                return found

    return ""


def nodes_of(obj: object, stage: str = "", depth: int = 0) -> list[tuple[int,str,str,str]]:
    out: list[tuple[int,str,str,str]] = []
    if isinstance(obj, dict):
        name = obj.get("name") or obj.get("nodeName") or obj.get("displayName")
        st = obj.get("status") or obj.get("nodeStatus") or obj.get("state")
        typ = str(obj.get("nodeType") or obj.get("type") or "")
        next_stage = str(name) if name and "STAGE" in typ.upper() else stage
        if name and isinstance(st, str):
            out.append((depth, next_stage, str(name), st))
        for value in obj.values():
            out.extend(nodes_of(value, next_stage, depth + 1))
    elif isinstance(obj, list):
        for value in obj:
            out.extend(nodes_of(value, stage, depth))
    return out


def error_of(obj: object) -> str:
    keys = ("errorMessage", "errorDetails", "failureInfo", "failureDetails", "errorSummary", "exception")
    if isinstance(obj, dict):
        for key in keys:
            val = obj.get(key)
            if isinstance(val, str) and val.strip():
                return val.strip()
            if isinstance(val, (dict, list)):
                found = error_of(val)
                if found:
                    return found
        for value in obj.values():
            found = error_of(value)
            if found:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = error_of(value)
            if found:
                return found
    return ""


def tg(method: str, data: dict[str,str]) -> object | None:
    if not TG_TOKEN or not TG_CHAT:
        return None
    body = dict(data)
    body["chat_id"] = TG_CHAT
    if TG_TOPIC:
        body["message_thread_id"] = TG_TOPIC
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TG_TOKEN}/{method}",
        data=urllib.parse.urlencode(body).encode(),
        headers={"Content-Type":"application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.load(resp)
    except Exception:
        return None


def send(text: str) -> str:
    result = tg("sendMessage", {"text":text,"parse_mode":"HTML","disable_web_page_preview":"true"})
    try:
        return str(result["result"]["message_id"])
    except Exception:
        return ""


def edit(message_id: str, text: str) -> None:
    if message_id:
        tg("editMessageText", {"message_id":message_id,"text":text,"parse_mode":"HTML","disable_web_page_preview":"true"})


def duration(sec: int) -> str:
    return f"{sec // 60}m {sec % 60}s"


def render(status: str, stage: str, step: str, elapsed: int, err: str = "") -> str:
    st = norm(status)
    icon = "✅" if st in {"SUCCESS","SUCCEEDED"} else ("❌" if st in TERMINAL else "🟡")
    msg = (
        f"{icon} <b>Universal Kernel Build</b>\n"
        f"📱 <code>{html.escape(DEVICE)}</code>\n"
        f"🌿 Branch: <code>{html.escape(BRANCH)}</code>\n"
        f"🧩 Status: <code>{html.escape(status or 'UNKNOWN')}</code>\n"
        f"📍 Stage: <code>{html.escape(stage or '-')}</code>\n"
        f"🔧 Step: <code>{html.escape(step or '-')}</code>\n"
        f"⏱ <code>{duration(elapsed)}</code>\n"
        f"🆔 <code>{html.escape(PLAN)}</code>"
    )
    if RUN_URL:
        msg += f'\n🔗 <a href="{html.escape(RUN_URL, quote=True)}">Harness execution</a>'
    if err:
        msg += f"\n\n<b>Error:</b> <code>{html.escape(err[:800])}</code>"
    return msg


def main() -> int:
    started = time.time()
    message_id = send(
        f"🚀 <b>Universal Kernel Build</b>\n"
        f"📱 <code>{html.escape(DEVICE)}</code>\n"
        f"🌿 <code>{html.escape(BRANCH)}</code>\n"
        f"🆔 <code>{html.escape(PLAN)}</code>\n"
        f"🟡 Starting…"
    )
    last_signature = ""
    last_text = ""
    final = {}
    api_failures = 0

    while True:
        try:
            q = (
                f"?accountIdentifier={urllib.parse.quote(ACCOUNT)}"
                f"&orgIdentifier={urllib.parse.quote(ORG)}"
                f"&projectIdentifier={urllib.parse.quote(PROJECT)}"
            )
            details = api_get(f"/pipeline/api/pipelines/execution/v2/{urllib.parse.quote(PLAN, safe='')}{q}")
            graph = api_get(f"/pipeline/api/pipelines/execution/getExecutionGraph/{urllib.parse.quote(PLAN, safe='')}{q}")
            api_failures = 0
        except Exception as exc:
            api_failures += 1
            details, graph = {}, {}
            final["monitor_error"] = str(exc)

        status = status_of(details)
        active = [n for n in nodes_of(graph) if norm(n[3]) in ACTIVE]
        active.sort(key=lambda n: (n[0], n[1], n[2]), reverse=True)
        stage = active[0][1] if active else ""
        step = active[0][2] if active else ""
        if active and not status:
            status = active[0][3]
        err = error_of(details) or error_of(graph)
        elapsed = int(time.time() - started)
        signature = f"{norm(status)}|{stage}|{step}|{err[:300]}"
        if signature != last_signature:
            text = render(status or "RUNNING", stage, step, elapsed, err)
            if text != last_text:
                if message_id:
                    edit(message_id, text)
                else:
                    message_id = send(text)
                last_text = text
            last_signature = signature

        state = norm(status)
        if state in TERMINAL:
            final = {
                "plan_execution_id": PLAN,
                "status": state,
                "stage": stage,
                "step": step,
                "error": err,
                "elapsed_seconds": elapsed,
                "execution_url": RUN_URL,
            }
            break
        if api_failures >= 12:
            final = {
                "plan_execution_id": PLAN,
                "status": "MONITOR_ERROR",
                "stage": stage,
                "step": step,
                "error": str(final.get("monitor_error", "Harness API polling failed")),
                "elapsed_seconds": elapsed,
                "execution_url": RUN_URL,
            }
            break
        time.sleep(POLL)

    OUT.write_text(json.dumps(final, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    final_text = render(str(final.get("status", "UNKNOWN")), str(final.get("stage", "")), str(final.get("step", "")), int(final.get("elapsed_seconds", 0)), str(final.get("error", "")))
    if message_id:
        edit(message_id, final_text)
    else:
        send(final_text)
    print(json.dumps(final, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
