#!/usr/bin/env python3
"""tg_dashboard.py against a local fake Bot API: cadence, 429 back-off,
HTML escaping, progress rendering and the final failure frame."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
calls: list[dict] = []
rate_limited = {"remaining": 1}


class FakeTelegram(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        form = dict(urllib.parse.parse_qsl(self.rfile.read(length).decode()))
        form["_t"] = time.time()
        form["_method"] = self.path.rsplit("/", 1)[-1]
        calls.append(form)
        if rate_limited["remaining"] > 0:
            rate_limited["remaining"] -= 1
            body = {"ok": False, "error_code": 429, "description": "Too Many Requests: retry after 1",
                    "parameters": {"retry_after": 1}}
            self.send_response(429)
        else:
            body = {"ok": True, "result": {"message_id": 7}}
            self.send_response(200)
        payload = json.dumps(body).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


server = ThreadingHTTPServer(("127.0.0.1", 0), FakeTelegram)
threading.Thread(target=server.serve_forever, daemon=True).start()

with tempfile.TemporaryDirectory() as tmp:
    state = Path(tmp) / "state.json"
    log = Path(tmp) / "build.log"
    log.write_text("  CC      kernel/fork.o\n  CC      fs/<evil>&.o\n", encoding="utf-8")
    write = [sys.executable, str(ROOT / "scripts/progress_state.py"), str(state)]
    subprocess.run(write + ["pct=44", "state=pending", "phase=compile", "detail=objects 100/1000",
                            "compile_done=100", "compile_total=1000", "toolchain=aosp clang-r416183b"], check=True)
    env = dict(os.environ, TG_BOT_TOKEN="t", TG_CHAT_ID="-1001", TG_MESSAGE_ID="7",
               TG_API_BASE=f"http://127.0.0.1:{server.server_port}", TG_UI_INTERVAL="1",
               BUILD_PROFILE="lavender-4.19", DEVICE="lavender", VARIANT_LABEL="KernelSU-Next",
               RUN_URL="https://example.invalid/run?a=1&b=2", KERNEL_BRANCH="main")
    proc = subprocess.Popen([sys.executable, str(ROOT / "scripts/tg_dashboard.py"), str(state), str(log)], env=env)
    time.sleep(2.5)
    subprocess.run(write + ["compile_done=300", "detail=objects 300/1000", "pct=57"], check=True)
    time.sleep(2.5)
    subprocess.run(write + ["final=true", "state=failure", "phase=compile",
                            "detail=failed after 1m", "error_excerpt=fs/x.c:1:2: error: <script> & boom"], check=True)
    try:
        rc = proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        fail("dashboard did not exit after the final state")

server.shutdown()
if rc != 0:
    fail(f"dashboard exit code {rc}")
edits = [c for c in calls if c["_method"] == "editMessageText"]
if len(edits) < 4:
    fail(f"expected a steady stream of edits, got {len(edits)}")
# 429 handling: the call after the rate-limited one waits at least retry_after.
if edits[1]["_t"] - edits[0]["_t"] < 0.95:
    fail("dashboard did not honour retry_after")
texts = [e["text"] for e in edits]
if len(set(texts)) < 3:
    fail("frames do not change between edits (animation stalls)")
running = texts[2]
for needle in ("Building kernel", "lavender-4.19", "KernelSU-Next", "aosp clang-r416183b", "ETA", "Compile",
               "fs/&lt;evil&gt;&amp;.o", 'href="https://example.invalid/run?a=1&amp;b=2"'):
    if needle not in running:
        fail(f"running frame lacks {needle!r}:\n{running}")
if "<evil>" in running:
    fail("log tail is not HTML-escaped")
final = texts[-1]
for needle in ("Build gagal", "<blockquote expandable>", "&lt;script&gt; &amp; boom", "❌Compile"):
    if needle not in final:
        fail(f"final frame lacks {needle!r}:\n{final}")
if any(len(t) > 4096 for t in texts):
    fail("message exceeds Telegram's 4096 character limit")
print(f"PASS telegram dashboard: {len(edits)} edits, 429 honoured, escaped, final failure frame")
