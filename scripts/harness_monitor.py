#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = os.environ.get("HARNESS_BASE", "https://app.harness.io")
ACCOUNT = os.environ["HARNESS_ACCOUNT"]
ORG = os.environ.get("HARNESS_ORG", "default")
PROJECT = os.environ.get("HARNESS_PROJECT", "ci_build")
PIPELINE = os.environ.get("HARNESS_PIPELINE", "Universal_Kernel_Build")
PLAN = os.environ["HARNESS_PLAN_EXECUTION_ID"]
POLL = max(5, int(os.environ.get("HARNESS_POLL_SECONDS", "5")))
TG_TOKEN = os.environ.get("TG_BOT_TOKEN", "")
TG_CHAT = os.environ.get("TG_CHAT_ID", "")
TG_TOPIC = os.environ.get("TG_TOPIC_ID", "")
DEVICE = os.environ.get("DEVICE", "unknown")
BRANCH = os.environ.get("KERNEL_BRANCH", "unknown")
OUT = Path(os.environ.get("HARNESS_MONITOR_FILE", "harness-monitor.json"))
RUN_URL = os.environ.get("HARNESS_EXECUTION_URL", "")
GITHUB_API = os.environ.get("GITHUB_API", "https://api.github.com")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GH_REPOSITORY = os.environ.get("GH_REPOSITORY", "")
MAX_SECONDS = max(60, int(os.environ.get("HARNESS_MAX_SECONDS", "8100")))
TG_EDIT_MIN_SECONDS = max(3.0, float(os.environ.get("TG_EDIT_MIN_SECONDS", str(POLL))))
TG_MAX_RETRIES = max(1, int(os.environ.get("TG_MAX_RETRIES", "3")))
RELEASE_TAG = f"harness-{PLAN}"

TERMINAL = {"SUCCEEDED","SUCCESS","FAILED","FAILURE","ERROR","ERRORED","ABORTED","EXPIRED","REJECTED","STOPPED","CANCELED"}
ACTIVE = {"RUNNING","IN_PROGRESS","QUEUED","NOT_STARTED","PAUSED","WAITING"}
RUNNING_STATES = {"RUNNING", "IN_PROGRESS"}

DONE_STATES = TERMINAL | {"SKIPPED", "IGNORED", "NOT_RUN"}

SPINNER_FRAMES = (
    "⠋", "⠙", "⠹", "⠸", "⠼",
    "⠴", "⠦", "⠧", "⠇", "⠏",
)

BAR_WIDTH = 16

TREE_MAX_STAGES = max(
    1,
    int(os.environ.get("TG_MAX_STAGES", "12")),
)

TREE_MAX_STEPS = max(
    1,
    int(os.environ.get("TG_MAX_STEPS", "12")),
)

TREE_MAX_CHARS = max(
    800,
    int(os.environ.get("TG_TREE_MAX_CHARS", "2600")),
)

GENERIC_NAMES = {
    "",
    "data",
    "stages",
    "stage",
    "steps",
    "step",
    "nodes",
    "node",
    "execution",
    "executiondata",
    "pipelineexecution",
    "pipelineexecutionsummary",
    "planexecution",
    "planexecutiondata",
    "children",
    "child",
    "items",
    "item",
}


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



def clean_name(value: object) -> str:
    name = str(value or "").strip()

    if not name:
        return ""

    if name.casefold() in GENERIC_NAMES:
        return ""

    return name


def classify_node(
    obj: dict,
    key_hint: str = "",
) -> tuple[str, str]:
    raw_type = str(
        obj.get("nodeType")
        or obj.get("type")
        or obj.get("stepType")
        or ""
    )

    typ = raw_type.upper()
    hint = key_hint.upper()

    if "STAGE" in typ or "STAGE" in hint:
        return "stage", raw_type

    if (
        "STEP" in typ
        or "SHELL" in typ
        or "RUN" in typ
        or "STEP" in hint
    ):
        return "step", raw_type

    return "node", raw_type


def node_name(obj: dict) -> str:
    for key in (
        "name",
        "nodeName",
        "displayName",
        "stageName",
        "stepName",
        "identifier",
    ):
        name = clean_name(obj.get(key))

        if name:
            return name

    return ""


def node_status(obj: dict) -> str:
    for key in (
        "status",
        "nodeStatus",
        "stepStatus",
        "stageStatus",
        "state",
        "executionStatus",
        "nodeExecutionStatus",
        "executionState",
    ):
        value = obj.get(key)

        if isinstance(value, str) and value.strip():
            return value

    return ""


def nodes_of(
    obj: object,
    stage: str = "",
    depth: int = 0,
    key_hint: str = "",
) -> list[tuple[int, str, str, str, str]]:
    """
    Extract real Harness execution nodes.

    Collection names such as "stages" and "steps" are never emitted
    as fake execution nodes.
    """
    out: list[tuple[int, str, str, str, str]] = []

    if isinstance(obj, dict):
        name = node_name(obj)
        state = node_status(obj)

        current_stage = stage
        kind = "node"

        if name and state:
            kind, _ = classify_node(obj, key_hint)

            if kind == "stage":
                current_stage = name

            out.append(
                (
                    depth,
                    current_stage,
                    name,
                    state,
                    kind,
                )
            )

        for key, value in obj.items():
            if key in {
                "name",
                "nodeName",
                "displayName",
                "stageName",
                "stepName",
                "status",
                "nodeStatus",
                "stepStatus",
                "stageStatus",
                "state",
                "executionStatus",
                "nodeType",
                "type",
                "stepType",
            }:
                continue

            out.extend(
                nodes_of(
                    value,
                    current_stage,
                    depth + 1,
                    str(key),
                )
            )

    elif isinstance(obj, list):
        for value in obj:
            out.extend(
                nodes_of(
                    value,
                    stage,
                    depth,
                    key_hint,
                )
            )

    return out


def dedupe_nodes(
    nodes: list[tuple[int, str, str, str, str]],
) -> list[tuple[int, str, str, str, str]]:
    priority = {
        "FAILED": 100,
        "FAILURE": 100,
        "ERROR": 100,
        "ERRORED": 100,
        "ABORTED": 95,
        "CANCELED": 95,
        "SUCCEEDED": 80,
        "SUCCESS": 80,
        "SKIPPED": 75,
        "IGNORED": 75,
        "NOT_RUN": 75,
        "RUNNING": 70,
        "IN_PROGRESS": 70,
        "PAUSED": 65,
        "WAITING": 60,
        "QUEUED": 50,
        "NOT_STARTED": 40,
    }

    selected = {}

    for item in nodes:
        depth, stage, name, state, kind = item
        key = (stage, name, kind)

        current = selected.get(key)

        if current is None:
            selected[key] = item
            continue

        current_score = (
            current[0] * 10
            + priority.get(norm(current[3]), 0)
        )

        new_score = (
            depth * 10
            + priority.get(norm(state), 0)
        )

        if new_score >= current_score:
            selected[key] = item

    return list(selected.values())


def infer_active_children(
    raw_nodes: list[tuple[int, str, str, str, str]],
) -> list[tuple[int, str, str, str, str]]:
    """Repair sparse Harness graph data for the current active step.

    Harness can briefly return the stage as RUNNING while its child step is
    either reported without a parent stage or has NOT_STARTED/blank state.
    For this pipeline shape there is one active stage and one non-terminal
    child, so associating that child with the active stage is deterministic
    enough to avoid the misleading "Active: 0" display.
    """
    active_stages = [
        name
        for _depth, name, _node, state, kind in raw_nodes
        if kind == "stage" and norm(state) in RUNNING_STATES and name
    ]

    if not active_stages:
        return raw_nodes

    updated = list(raw_nodes)

    # When Harness returns the child as a top-level/Pipeline node, attach it
    # to the sole active stage. Only do this when there is exactly one active
    # stage and exactly one non-terminal non-stage node to avoid guessing in
    # multi-stage pipelines.
    if len(active_stages) == 1:
        target_stage = active_stages[0]
        candidates = [
            index
            for index, (_depth, stage, _name, state, kind) in enumerate(updated)
            if kind != "stage"
            and (not stage or stage.casefold() == "pipeline")
            and norm(state) not in DONE_STATES
        ]
        if len(candidates) == 1:
            index = candidates[0]
            depth, _old_stage, name, state, kind = updated[index]
            updated[index] = (depth, target_stage, name, state, kind)

    by_stage: dict[str, list[int]] = {}
    for index, (_depth, stage, _name, state, kind) in enumerate(updated):
        if kind == "stage" or stage not in active_stages:
            continue
        if norm(state) in DONE_STATES or norm(state) in RUNNING_STATES:
            continue
        by_stage.setdefault(stage, []).append(index)

    for stage, indexes in by_stage.items():
        if len(indexes) != 1:
            continue
        index = indexes[0]
        depth, stage_name, name, _state, kind = updated[index]
        updated[index] = (depth, stage_name, name, "RUNNING", kind)

    return updated


def aggregate_status(states: list[str]) -> str:
    normalized = [
        norm(state)
        for state in states
        if state
    ]

    if any(
        state in {
            "FAILED",
            "FAILURE",
            "ERROR",
            "ERRORED",
            "ABORTED",
            "CANCELED",
        }
        for state in normalized
    ):
        return "FAILED"

    if any(
        state in ACTIVE
        for state in normalized
    ):
        return "RUNNING"

    if normalized and all(
        state in DONE_STATES
        for state in normalized
    ):
        return "SUCCEEDED"

    if any(
        state in {
            "WAITING",
            "QUEUED",
            "NOT_STARTED",
            "PAUSED",
        }
        for state in normalized
    ):
        return "WAITING"

    return normalized[0] if normalized else "UNKNOWN"


def tree_from_raw(
    raw: list[tuple[int, str, str, str, str]],
) -> list[tuple[str, str, list[tuple[str, str]]]]:
    groups = {}
    stage_order = []

    for depth, stage, name, state, kind in raw:
        stage_name = clean_name(stage) or "Pipeline"

        if stage_name not in groups:
            groups[stage_name] = []
            stage_order.append(stage_name)

        groups[stage_name].append((name, state, kind, depth))

    tree = []

    for stage_name in stage_order:
        entries = groups[stage_name]

        explicit_stage_states = [
            state
            for name, state, kind, _depth in entries
            if kind == "stage" and name == stage_name
        ]

        children_entries = [
            (name, state, kind, depth)
            for name, state, kind, depth in entries
            if not (kind == "stage" and name == stage_name)
        ]

        stage_state = (
            explicit_stage_states[0]
            if explicit_stage_states
            else aggregate_status(
                [
                    state
                    for _name, state, _kind, _depth in children_entries
                ]
            )
        )

        children = []
        seen = set()

        for name, state, _kind, depth in sorted(
            children_entries,
            key=lambda item: (item[3], item[0]),
        ):
            key = name.casefold()
            if key in seen:
                continue
            seen.add(key)
            children.append((name, state))
            if len(children) >= TREE_MAX_STEPS:
                break

        tree.append((stage_name, stage_state, children))
        if len(tree) >= TREE_MAX_STAGES:
            break

    return tree


def pipeline_tree(
    graph: object,
) -> tuple[
    list[tuple[str, str, list[tuple[str, str]]]],
    list[tuple[int, str, str, str, str]],
]:
    raw = dedupe_nodes(nodes_of(graph))
    return tree_from_raw(raw), raw


def current_node(
    raw_nodes: list[tuple[int, str, str, str, str]],
) -> tuple[str, str]:
    active_steps = [
        item
        for item in raw_nodes
        if item[4] == "step"
        and norm(item[3]) in RUNNING_STATES
    ]

    if active_steps:
        active_steps.sort(
            key=lambda item: (
                item[0],
                item[1],
                item[2],
            ),
            reverse=True,
        )

        _depth, stage, name, _state, _kind = active_steps[0]

        return stage, name

    active_nodes = [
        item
        for item in raw_nodes
        if norm(item[3]) in RUNNING_STATES
    ]

    if active_nodes:
        active_nodes.sort(
            key=lambda item: (
                item[0],
                item[1],
                item[2],
            ),
            reverse=True,
        )

        _depth, stage, name, _state, kind = active_nodes[0]

        if kind == "stage":
            return name, ""

        return stage, name

    return "", ""


def progress_of(
    raw_nodes: list[tuple[int, str, str, str, str]],
) -> tuple[int, int, int]:
    steps = [
        item
        for item in raw_nodes
        if item[4] == "step"
    ]

    if not steps:
        steps = [
            item
            for item in raw_nodes
            if item[4] != "stage"
        ]

    if not steps:
        steps = raw_nodes

    unique = {}

    for _depth, stage, name, state, _kind in steps:
        unique[(stage, name)] = norm(state)

    total = len(unique)

    done = sum(
        1
        for state in unique.values()
        if state in DONE_STATES
    )

    active = sum(
        1
        for state in unique.values()
        if state in RUNNING_STATES
    )

    return done, total, active


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


def _telegram_request(
    method: str,
    data: dict[str, str],
    *,
    include_topic: bool = True,
) -> object | None:
    global TG_LAST_ERROR

    if not TG_TOKEN or not TG_CHAT:
        TG_LAST_ERROR = "Telegram credentials are not configured"
        return None

    body = dict(data)
    body["chat_id"] = TG_CHAT
    if include_topic and TG_TOPIC:
        body["message_thread_id"] = TG_TOPIC

    payload = urllib.parse.urlencode(body).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TG_TOKEN}/{method}",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    last_error = ""

    for attempt in range(1, TG_MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                result = json.load(resp)

            if isinstance(result, dict) and not result.get("ok", True):
                description = str(result.get("description") or "Telegram API returned ok=false")
                TG_LAST_ERROR = description
                last_error = description

                if "message is not modified" in description.lower():
                    return {"ok": True, "result": {}}
            else:
                TG_LAST_ERROR = ""
                return result
        except urllib.error.HTTPError as exc:
            body_text = ""
            try:
                body_text = exc.read().decode("utf-8", "replace")[:1000]
            except Exception:
                pass
            last_error = f"HTTP {exc.code}: {body_text or exc.reason}"
            TG_LAST_ERROR = last_error

            if exc.code == 429:
                retry_after = 1
                try:
                    decoded = json.loads(body_text)
                    retry_after = int(((decoded.get("parameters") or {}).get("retry_after")) or 1)
                except Exception:
                    pass
                if attempt < TG_MAX_RETRIES:
                    time.sleep(min(max(retry_after, 1), 15))
                    continue
        except Exception as exc:
            last_error = f"{type(exc).__name__}: {exc}"
            TG_LAST_ERROR = last_error

        if attempt < TG_MAX_RETRIES:
            time.sleep(min(1.0 * attempt, 4.0))

    if last_error:
        print(f"[telegram] {method} failed: {last_error}", file=os.sys.stderr, flush=True)
    return None


TG_LAST_ERROR = ""


def tg(method: str, data: dict[str, str], *, include_topic: bool = True) -> object | None:
    return _telegram_request(method, data, include_topic=include_topic)


def send(text: str) -> str:
    result = tg(
        "sendMessage",
        {
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": "true",
        },
        include_topic=True,
    )
    try:
        return str(result["result"]["message_id"])
    except Exception:
        return ""


def edit(message_id: str, text: str) -> bool:
    if not message_id:
        return False

    result = tg(
        "editMessageText",
        {
            "message_id": message_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": "true",
        },
        include_topic=False,
    )

    return bool(isinstance(result, dict) and result.get("ok"))


def write_monitor_state(data: dict[str, object]) -> None:
    """Persist the current monitor state on every polling cycle."""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_name(f".{OUT.name}.tmp")
    payload = dict(data)
    payload["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    tmp.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    tmp.replace(OUT)


def github_release_state() -> tuple[str, str]:
    """
    Secondary completion signal.

    Harness creates the GitHub Release from the EXIT trap only after the
    build process terminates.
    """
    if not GH_REPOSITORY:
        return "", ""

    url = (
        f"{GITHUB_API}/repos/{urllib.parse.quote(GH_REPOSITORY, safe='/')}"
        f"/releases/tags/{urllib.parse.quote(RELEASE_TAG, safe='')}"
    )

    headers = {"Accept": "application/vnd.github+json"}
    if GITHUB_TOKEN:
        headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            release = json.load(resp)
    except Exception:
        return "", ""

    assets = {
        str(asset.get("name", "")).strip()
        for asset in release.get("assets", [])
        if isinstance(asset, dict)
    }

    if "build-result.txt" in assets:
        return "SUCCEEDED", ""

    if "failure-summary.txt" in assets:
        return "FAILED", "Harness build failed; see GitHub Release failure-summary.txt."

    return "", ""





def duration(sec: int) -> str:
    return f"{sec // 60}m {sec % 60}s"


def status_icon(status: str) -> str:
    state = norm(status)

    if state in {"SUCCESS", "SUCCEEDED"}:
        return "✅"

    if state in {
        "FAILED",
        "FAILURE",
        "ERROR",
        "ERRORED",
        "ABORTED",
        "CANCELED",
    }:
        return "❌"

    if state in ACTIVE:
        return "🔄"

    if state in {
        "QUEUED",
        "NOT_STARTED",
        "WAITING",
        "PAUSED",
    }:
        return "⏳"

    if state in {
        "SKIPPED",
        "IGNORED",
        "NOT_RUN",
    }:
        return "⏭️"

    return "•"


def progress_bar(
    status: str,
    done: int,
    total: int,
    frame: int,
) -> tuple[str, str]:
    state = norm(status)

    if total > 0:
        pct = int(round(done * 100 / total))

        if state not in TERMINAL:
            pct = min(pct, 99)

        pct = max(0, min(100, pct))
        filled = int(round(BAR_WIDTH * pct / 100))
        bar = list("█" * filled + "░" * (BAR_WIDTH - filled))

        # Even when completed/total does not change, animate a live marker
        # through the remaining segment so Telegram visibly updates.
        if state not in TERMINAL:
            start_pos = min(filled, BAR_WIDTH - 1)
            span = max(1, BAR_WIDTH - start_pos)
            pos = start_pos + (frame % span)
            bar[pos] = "●"

        return "".join(bar), f"{pct:3d}%"

    pos = frame % BAR_WIDTH

    return (
        "".join(
            "●" if i == pos else "─"
            for i in range(BAR_WIDTH)
        ),
        "LIVE",
    )


def render_tree(
    tree: list[tuple[str, str, list[tuple[str, str]]]],
) -> str:
    if not tree:
        return (
            "📦 <b>PIPELINE</b>\n"
            "└─ ⏳ Waiting for Harness graph…"
        )

    lines = ["📦 <b>PIPELINE</b>"]

    for stage_index, (stage, stage_state, children) in enumerate(tree):
        stage_prefix = (
            "└─"
            if stage_index == len(tree) - 1
            else "├─"
        )

        lines.append(
            f"{stage_prefix} "
            f"{status_icon(stage_state)} "
            f"<b>{html.escape(stage)}</b>"
        )

        for child_index, (name, state) in enumerate(children):
            child_prefix = (
                "   └─"
                if child_index == len(children) - 1
                else "   ├─"
            )

            lines.append(
                f"{child_prefix} "
                f"{status_icon(state)} "
                f"{html.escape(name)}"
            )

    result = "\n".join(lines)

    if len(result) <= TREE_MAX_CHARS:
        return result

    return (
        result[:TREE_MAX_CHARS - 45]
        + "\n… <i>pipeline tree truncated</i>"
    )


def render(
    status: str,
    stage: str,
    step: str,
    elapsed: int,
    err: str = "",
    done: int = 0,
    total: int = 0,
    active: int = 0,
    frame: int = 0,
    tree_text: str = "",
) -> str:
    state = norm(status)

    icon = status_icon(status)

    spinner = (
        ""
        if state in TERMINAL
        else SPINNER_FRAMES[
            frame % len(SPINNER_FRAMES)
        ]
    )

    bar, pct = progress_bar(
        status,
        done,
        total,
        frame,
    )

    current = html.escape(
        step or stage or "-"
    )

    msg = (
        f"{icon} <b>Universal Kernel Build</b>\n"
        f"📱 <code>{html.escape(DEVICE)}</code>\n"
        f"🌿 Branch: <code>{html.escape(BRANCH)}</code>\n"
        f"🧩 Status: <code>"
        f"{html.escape(status or 'UNKNOWN')}"
        f"</code>\n\n"
        f"{tree_text or '📦 <b>PIPELINE</b>'}\n\n"
        f"🎯 Stage: <code>{html.escape(stage or '-')}</code>\n"
        f"🔨 Step: <code>{html.escape(step or '-')}</code>\n"
        f"📊 Pipeline: <code>{bar}</code> "
        f"<b>{pct}</b> <code>{spinner}</code>\n"
        f"✅ Completed: <code>{done}/{total}</code>\n"
        f"⚡ Active: <code>{active}</code>\n"
        f"💓 Monitor poll: <code>#{frame}</code>\n"
        f"⏱ <code>{duration(elapsed)}</code>\n"
        f"🆔 <code>{html.escape(PLAN)}</code>"
    )

    if RUN_URL:
        msg += (
            f'\n🔗 <a href="{html.escape(RUN_URL, quote=True)}">'
            f"Harness execution</a>"
        )

    if err:
        msg += (
            "\n\n<b>Error:</b> "
            f"<code>{html.escape(err[:800])}</code>"
        )

    return msg



def main() -> int:
    started = time.time()
    frame = 0

    message_id = send(
        f"🚀 <b>Universal Kernel Build</b>\n"
        f"📱 <code>{html.escape(DEVICE)}</code>\n"
        f"🌿 <code>{html.escape(BRANCH)}</code>\n"
        f"🆔 <code>{html.escape(PLAN)}</code>\n"
        f"🟡 Starting…"
    )

    last_signature = ""
    last_text = ""
    last_edit_at = 0.0
    edit_failures = 0

    final: dict[str, object] = {}
    api_failures = 0

    last_done = 0
    last_total = 0
    last_active = 0
    last_tree = ""

    while True:
        frame += 1

        try:
            query = (
                f"?accountIdentifier={urllib.parse.quote(ACCOUNT)}"
                f"&orgIdentifier={urllib.parse.quote(ORG)}"
                f"&projectIdentifier={urllib.parse.quote(PROJECT)}"
            )
            detail_query = query + "&renderFullBottomGraph=true"

            details = api_get(
                "/pipeline/api/pipelines/execution/v2/"
                f"{urllib.parse.quote(PLAN, safe='')}"
                f"{detail_query}"
            )

            graph = api_get(
                "/pipeline/api/pipelines/execution/"
                "getExecutionGraph/"
                f"{urllib.parse.quote(PLAN, safe='')}"
                f"{query}"
            )

            api_failures = 0

        except Exception as exc:
            api_failures += 1
            details = {}
            graph = {}
            final["monitor_error"] = str(exc)

        status = status_of(details)

        tree, raw_nodes = pipeline_tree(graph)

        # Some Harness responses expose execution nodes through details
        # while the graph endpoint is temporarily sparse.
        if not raw_nodes:
            tree, raw_nodes = pipeline_tree(details)

        raw_nodes = infer_active_children(raw_nodes)
        tree = tree_from_raw(raw_nodes)

        stage, step = current_node(raw_nodes)

        if not status:
            active_nodes = [
                node
                for node in raw_nodes
                if norm(node[3]) in RUNNING_STATES
            ]

            if active_nodes:
                active_nodes.sort(
                    key=lambda node: (
                        node[0],
                        node[1],
                        node[2],
                    ),
                    reverse=True,
                )

                status = active_nodes[0][3]

        err = error_of(details) or error_of(graph)
        elapsed = int(time.time() - started)

        done_nodes, total_nodes, active_nodes_count = progress_of(
            raw_nodes
        )

        tree_text = render_tree(tree)

        # Harness creates the GitHub Release only from the EXIT trap after
        # the build process terminates. Keep it as a secondary terminal signal.
        release_status, release_error = github_release_state()

        completion_source = ""

        if release_status:
            status = release_status
            err = err or release_error
            completion_source = "github_release"

        state = norm(status) or "UNKNOWN"

        # Keep the last useful graph visible during transient API failures.
        if not raw_nodes and last_tree:
            tree_text = last_tree
            done_nodes = last_done
            total_nodes = last_total
            active_nodes_count = last_active

        if raw_nodes:
            last_tree = tree_text
            last_done = done_nodes
            last_total = total_nodes
            last_active = active_nodes_count

        message_text = render(
            status or "RUNNING",
            stage,
            step,
            elapsed,
            err,
            done_nodes,
            total_nodes,
            active_nodes_count,
            frame,
            tree_text,
        )

        signature = (
            f"{state}|{stage}|{step}|{err[:300]}|"
            f"{done_nodes}|{total_nodes}|{active_nodes_count}|"
            f"{tree_text}|{frame}"
        )

        now = time.monotonic()
        if (
            message_text != last_text
            and (now - last_edit_at) >= TG_EDIT_MIN_SECONDS
        ):
            if message_id:
                if edit(message_id, message_text):
                    edit_failures = 0
                    last_edit_at = now
                else:
                    edit_failures += 1

                    # Do not let one broken Telegram message freeze the monitor.
                    # After two consecutive edit failures, create a replacement
                    # message and continue editing that one.
                    if edit_failures >= 2:
                        replacement_id = send(message_text)
                        if replacement_id:
                            message_id = replacement_id
                            edit_failures = 0
                            last_edit_at = now
            else:
                message_id = send(message_text)
                if message_id:
                    edit_failures = 0
                    last_edit_at = now

            last_text = message_text
            last_signature = signature

        # Persist a live snapshot, not only the final state.
        write_monitor_state({
            "plan_execution_id": PLAN,
            "status": state,
            "stage": stage,
            "step": step,
            "error": err,
            "elapsed_seconds": elapsed,
            "execution_url": RUN_URL,
            "completion_source": completion_source or "live_poll",
            "terminal": state in TERMINAL,
            "poll": frame,
            "api_failures": api_failures,
            "telegram": {
                "configured": bool(TG_TOKEN and TG_CHAT),
                "message_id": message_id,
                "edit_failures": edit_failures,
                "last_error": TG_LAST_ERROR,
            },
            "progress": {
                "completed": done_nodes,
                "total": total_nodes,
                "active": active_nodes_count,
            },
        })

        print(
            f"[monitor] poll={frame} status={state} "
            f"progress={done_nodes}/{total_nodes} active={active_nodes_count} "
            f"stage={stage or '-'} step={step or '-'} elapsed={elapsed}s",
            flush=True,
        )

        if state in TERMINAL:
            final = {
                "plan_execution_id": PLAN,
                "status": state,
                "stage": stage,
                "step": step,
                "error": err,
                "elapsed_seconds": elapsed,
                "execution_url": RUN_URL,
                "completion_source": (
                    completion_source
                    or "harness_api"
                ),
                "progress": {
                    "completed": done_nodes,
                    "total": total_nodes,
                    "active": active_nodes_count,
                },
            }
            break

        if elapsed >= MAX_SECONDS:
            final = {
                "plan_execution_id": PLAN,
                "status": "MONITOR_TIMEOUT",
                "stage": stage,
                "step": step,
                "error": (
                    f"Monitor exceeded {MAX_SECONDS}s "
                    "without a terminal Harness/release state."
                ),
                "elapsed_seconds": elapsed,
                "execution_url": RUN_URL,
                "completion_source": "monitor_timeout",
                "progress": {
                    "completed": done_nodes,
                    "total": total_nodes,
                    "active": active_nodes_count,
                },
            }
            break

        if api_failures >= 12:
            final = {
                "plan_execution_id": PLAN,
                "status": "MONITOR_ERROR",
                "stage": stage,
                "step": step,
                "error": str(
                    final.get(
                        "monitor_error",
                        "Harness API polling failed",
                    )
                ),
                "elapsed_seconds": elapsed,
                "execution_url": RUN_URL,
                "completion_source": "harness_api_error",
                "progress": {
                    "completed": done_nodes,
                    "total": total_nodes,
                    "active": active_nodes_count,
                },
            }
            break

        time.sleep(POLL)

    write_monitor_state(final)

    final_progress = final.get("progress")
    if not isinstance(final_progress, dict):
        final_progress = {}

    final_text = render(
        str(final.get("status", "UNKNOWN")),
        str(final.get("stage", "")),
        str(final.get("step", "")),
        int(final.get("elapsed_seconds", 0)),
        str(final.get("error", "")),
        int(final_progress.get("completed", last_done)),
        int(final_progress.get("total", last_total)),
        int(final_progress.get("active", last_active)),
        frame,
        last_tree,
    )

    if message_id:
        if not edit(message_id, final_text):
            replacement_id = send(final_text)
            if replacement_id:
                message_id = replacement_id
    else:
        send(final_text)

    print(
        json.dumps(
            final,
            ensure_ascii=False,
        )
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
