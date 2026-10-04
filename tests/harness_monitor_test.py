#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path

ENV = {
    "HARNESS_ACCOUNT": "test-account",
    "HARNESS_API_KEY": "test-key",
    "HARNESS_PLAN_EXECUTION_ID": "test-plan",
    "HARNESS_UNKNOWN_IDLE_GRACE_SECONDS": "15",
    "HARNESS_POLL_SECONDS": "3",
    "HARNESS_MAX_SECONDS": "120",
    "TG_BOT_TOKEN": "",
    "TG_CHAT_ID": "",
    "HARNESS_MONITOR_FILE": "/tmp/zairenkai-harness-monitor-test.json",
}
os.environ.update(ENV)

path = Path(__file__).resolve().parents[1] / "scripts" / "harness_monitor.py"
spec = importlib.util.spec_from_file_location("harness_monitor", path)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

clock = [0.0]
mod.time.time = lambda: clock[0]
mod.time.sleep = lambda seconds: clock.__setitem__(0, clock[0] + seconds)
mod.send = lambda text: "1"
mod.edit = lambda message_id, text: True
mod.github_progress_state = lambda: (None, "", "")
mod.github_release_state = lambda: ("", "")

calls = {"count": 0}
def api_get(path):
    calls["count"] += 1
    if calls["count"] == 1:
        return {"data": {"planExecution": {"status": "RUNNING"}, "stages": [
            {"name": "Kernel Build", "status": "RUNNING", "steps": [
                {"name": "Build Universal Kernel Matrix", "status": "RUNNING"}
            ]}
        ]}}
    return {"data": {"planExecution": {"status": "UNKNOWN"}, "stages": [
        {"name": "Kernel Build", "status": "UNKNOWN", "steps": [
            {"name": "Build Universal Kernel Matrix", "status": "UNKNOWN"}
        ]}
    ]}}
mod.api_get = api_get

rc = mod.main()
state = json.loads(Path(ENV["HARNESS_MONITOR_FILE"]).read_text())
assert rc == 0
assert state["status"] == "FAILED", state
assert "UNKNOWN" in state["error"], state
print("PASS harness monitor UNKNOWN fail-safe")
