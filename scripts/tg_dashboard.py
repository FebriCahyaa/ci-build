#!/usr/bin/env python3
"""Live Telegram build dashboard for one kernel variant build.

build_kernel.sh starts this renderer in the background once the build message
exists. Build steps never talk to Telegram for progress any more; they only
write a small JSON state file (progress_beacon.sh). The renderer owns the
message and redraws it at a steady cadence, so the animation does not stall
between progress events and two writers never race on the same message.

Smoothness and rate limits
  * one edit per TG_UI_INTERVAL seconds (default 3.0s, ~20 edits/min, the
    Telegram group budget); HTTP 429 `retry_after` is honoured and the cadence
    backs off, then recovers gradually instead of bursting
  * the progress bar eases toward the reported percentage with 1/8-cell
    resolution, and during compilation it advances from the measured object
    rate, so it keeps moving between coarse progress events
  * spinner / elapsed / ETA change every frame, so every edit is a real change

State file (JSON, written atomically by progress_beacon.sh / build_kernel.sh):
  {"pct": 44, "phase": "compile", "detail": "objects 812/3100",
   "state": "pending|success|failure", "final": false,
   "compile_done": 812, "compile_total": 3100, "error_excerpt": "..."}

Optional state keys: kernel, toolchain (shown in the header once resolved).

Environment: TG_BOT_TOKEN TG_CHAT_ID TG_MESSAGE_ID [TG_API_BASE] TG_UI_INTERVAL
             BUILD_PROFILE DEVICE VARIANT_LABEL RUN_URL KERNEL_BRANCH
Usage:       tg_dashboard.py <state.json> <build.log>
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_BASE = os.environ.get("TG_API_BASE", "https://api.telegram.org").rstrip("/")
TOKEN = os.environ.get("TG_BOT_TOKEN", "")
CHAT = os.environ.get("TG_CHAT_ID", "")
MESSAGE_ID = os.environ.get("TG_MESSAGE_ID", "")
BASE_INTERVAL = max(1.0, float(os.environ.get("TG_UI_INTERVAL", "3.0")))
MAX_INTERVAL = 20.0
HTTP_TIMEOUT = max(4, int(os.environ.get("TG_HTTP_TIMEOUT", "8")))
MAX_SECONDS = int(os.environ.get("TG_DASHBOARD_MAX_SECONDS", str(4 * 3600)))
TEXT_LIMIT = 4096

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
EIGHTHS = " ▏▎▍▌▋▊▉"
STAGES = [
    ("source", "Source"),
    ("root-provider", "Root"),
    ("config", "Patches"),
    ("toolchain", "Toolchain"),
    ("defconfig", "Config"),
    ("compile", "Compile"),
    ("artifacts", "Package"),
    ("done", "Done"),
]
STAGE_ALIASES = {
    "identity": "defconfig", "anykernel": "artifacts",
    "config-patches": "config",
}
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def esc(value: object) -> str:
    return html.escape(str(value), quote=False)


def fmt_duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}h {minutes:02d}m {secs:02d}s" if hours else f"{minutes}m {secs:02d}s"


def bar(pct: float, width: int = 18) -> str:
    pct = max(0.0, min(100.0, pct))
    cells = pct / 100.0 * width
    full = int(cells)
    part = int((cells - full) * 8)
    text = "█" * full
    if full < width:
        text += EIGHTHS[part] + " " * (width - full - 1)
    return text


def runner_stats() -> tuple[int, int, str]:
    try:
        load = float(Path("/proc/loadavg").read_text().split()[0])
    except Exception:
        load = 0.0
    cpu = min(100, int(load / max(1, os.cpu_count() or 1) * 100))
    mem = 0
    try:
        info = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, value = line.split(":", 1)
            info[key] = int(value.split()[0])
        total, avail = info.get("MemTotal", 0), info.get("MemAvailable", 0)
        mem = int((total - avail) * 100 / total) if total else 0
    except Exception:
        pass
    return cpu, mem, f"{load:.2f}"


def log_tail(path: Path, lines: int = 6, limit: int = 900) -> str:
    try:
        with path.open("rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - 16384))
            data = fh.read().decode("utf-8", "replace")
    except Exception:
        return "waiting for build output…"
    rows = []
    for raw in data.replace("\r", "\n").splitlines():
        row = ANSI.sub("", raw).rstrip()
        if not row or row.startswith("[CI-HEARTBEAT]"):
            continue
        rows.append(row if len(row) <= 110 else row[:107] + "…")
    text = "\n".join(rows[-lines:]) or "waiting for build output…"
    return text[-limit:]


class Telegram:
    def __init__(self) -> None:
        self.retry_until = 0.0
        self.last_error = ""

    def call(self, method: str, payload: dict[str, str]) -> dict | None:
        if not (TOKEN and CHAT):
            return None
        data = urllib.parse.urlencode({"chat_id": CHAT, **payload}).encode()
        req = urllib.request.Request(f"{API_BASE}/bot{TOKEN}/{method}", data=data, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            try:
                decoded = json.loads(body)
            except Exception:
                decoded = {"ok": False, "description": body[:300], "error_code": exc.code}
            if exc.code == 429:
                retry = int(((decoded.get("parameters") or {}).get("retry_after")) or 5)
                self.retry_until = time.time() + retry
            return decoded
        except Exception as exc:  # network hiccup: keep the dashboard alive
            self.last_error = f"{type(exc).__name__}: {exc}"
            return None

    def edit(self, message_id: str, text: str) -> str:
        """Return 'ok', 'same', 'limited', 'html', or 'error'."""
        if time.time() < self.retry_until:
            return "limited"
        result = self.call("editMessageText", {
            "message_id": message_id, "text": text, "parse_mode": "HTML",
            "disable_web_page_preview": "true",
        })
        if not result:
            return "error"
        if result.get("ok"):
            return "ok"
        description = str(result.get("description", "")).lower()
        if "not modified" in description:
            return "same"
        if result.get("error_code") == 429:
            return "limited"
        if "parse entities" in description:
            return "html"
        self.last_error = description
        return "error"


class Dashboard:
    def __init__(self, state_path: Path, log_path: Path) -> None:
        self.state_path = state_path
        self.log_path = log_path
        self.started = time.time()
        self.frame = 0
        self.shown_pct = 0.0
        self.reached: set[str] = set()
        self.rate_samples: list[tuple[float, int]] = []
        self.state: dict = {}

    def read_state(self) -> dict:
        try:
            self.state = json.loads(self.state_path.read_text(encoding="utf-8"))
        except Exception:
            pass
        return self.state

    def stage_key(self) -> str:
        phase = str(self.state.get("phase", "")).split(" [", 1)[0]
        return STAGE_ALIASES.get(phase, phase)

    def target_pct(self, now: float) -> float:
        pct = float(self.state.get("pct", 0) or 0)
        done = int(self.state.get("compile_done", 0) or 0)
        total = int(self.state.get("compile_total", 0) or 0)
        if self.stage_key() == "compile" and total > 0:
            self.rate_samples.append((now, done))
            self.rate_samples = [s for s in self.rate_samples if now - s[0] <= 120]
            # Between beacons, extrapolate from the measured object rate so the
            # bar keeps moving; never pass the next milestone (90%).
            rate = self.objects_per_second()
            since = now - float(self.state.get("updated", now) or now)
            est = done + rate * min(since, 30)
            pct = max(pct, 44 + min(est, total) * 45.0 / total)
            pct = min(pct, 89.5)
        return pct

    def objects_per_second(self) -> float:
        if len(self.rate_samples) < 2:
            return 0.0
        (t0, d0), (t1, d1) = self.rate_samples[0], self.rate_samples[-1]
        return max(0.0, (d1 - d0) / (t1 - t0)) if t1 > t0 else 0.0

    def eta(self) -> str:
        done = int(self.state.get("compile_done", 0) or 0)
        total = int(self.state.get("compile_total", 0) or 0)
        rate = self.objects_per_second()
        if self.stage_key() != "compile" or not total or rate <= 0:
            return "—"
        return fmt_duration((total - done) / rate)

    def checklist(self, final_state: str) -> str:
        current = self.stage_key()
        keys = [k for k, _ in STAGES]
        if current in keys:
            self.reached.update(keys[: keys.index(current)])
        items = []
        for key, label in STAGES:
            if final_state == "success":
                mark = "✅"
            elif key == current:
                mark = "❌" if final_state == "failure" else "🔄"
            elif key in self.reached:
                mark = "✅"
            else:
                mark = "▫️"
            items.append(f"{mark}{label}")
        return " ".join(items[:4]) + "\n" + " ".join(items[4:])

    def render(self) -> str:
        now = time.time()
        state = self.state
        final_state = str(state.get("state", "pending")) if state.get("final") else "pending"
        target = 100.0 if final_state == "success" else self.target_pct(now)
        # Ease toward the target: smooth steps instead of jumps.
        self.shown_pct += (target - self.shown_pct) * (1.0 if state.get("final") else 0.45)
        pct = self.shown_pct
        spin = SPINNER[self.frame % len(SPINNER)]
        icon = {"success": "✅", "failure": "❌"}.get(final_state, spin)
        title = {"success": "Build selesai", "failure": "Build gagal"}.get(final_state, "Building kernel")
        cpu, mem, load = runner_stats()
        elapsed = fmt_duration(now - self.started)
        rate = self.objects_per_second()
        env = os.environ

        lines = [
            f"{icon} <b>Zairenkai — {esc(title)}</b>",
            f"🧭 <code>{esc(env.get('BUILD_PROFILE', 'unknown'))}</code> · 📱 <code>{esc(env.get('DEVICE', 'unknown'))}</code>"
            f" · 🔐 <code>{esc(env.get('VARIANT_LABEL', 'unknown'))}</code>",
        ]
        kernel = state.get("kernel") or ""
        toolchain = state.get("toolchain") or env.get("TOOLCHAIN_LABEL") or "resolving…"
        lines.append(f"🌿 <code>{esc(env.get('KERNEL_BRANCH', '-'))}</code>"
                     + (f" · 🐧 <code>{esc(kernel)}</code>" if kernel else ""))
        lines.append(f"🛠 <code>{esc(toolchain)}</code>")
        lines += [
            "",
            f"<code>{bar(pct)}</code> <b>{pct:5.1f}%</b>",
            f"🧩 <b>{esc(state.get('phase', 'starting'))}</b> — {esc(state.get('detail', 'preparing'))}",
            self.checklist(final_state),
            "",
            f"⏱ <code>{elapsed}</code> · ⏳ ETA <code>{self.eta()}</code>"
            + (f" · ⚡ <code>{rate * 60:.0f} obj/min</code>" if rate > 0 else ""),
            f"🖥 CPU <code>{cpu}%</code> · RAM <code>{mem}%</code> · load <code>{load}</code>",
        ]
        if env.get("RUN_URL"):
            lines.append(f'🔗 <a href="{html.escape(env["RUN_URL"], quote=True)}">CI log</a>')
        excerpt = str(state.get("error_excerpt", "") or "")
        if final_state == "failure" and excerpt:
            lines += ["", "🚨 <b>Error</b>", f"<blockquote expandable><pre>{esc(excerpt[-1500:])}</pre></blockquote>"]
        elif final_state == "pending":
            lines += ["", "📜 <b>Live log</b>", f"<pre>{esc(log_tail(self.log_path))}</pre>"]
        text = "\n".join(lines)
        return text if len(text) <= TEXT_LIMIT else text[: TEXT_LIMIT - 10] + "…</pre>"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    if not (TOKEN and CHAT and MESSAGE_ID):
        return 0
    tg = Telegram()
    dash = Dashboard(Path(sys.argv[1]), Path(sys.argv[2]))
    interval = BASE_INTERVAL
    html_ok = True
    while True:
        dash.read_state()
        final = bool(dash.state.get("final"))
        text = dash.render()
        if not html_ok:
            text = html.unescape(re.sub(r"<[^>]+>", "", text))
        result = tg.edit(MESSAGE_ID, text)
        if result == "limited":
            interval = min(MAX_INTERVAL, max(interval * 1.5, tg.retry_until - time.time()))
        elif result == "html":
            html_ok = False
        elif result in ("ok", "same"):
            interval = max(BASE_INTERVAL, interval * 0.9)
            if final:
                return 0
        if final and result == "error":
            return 1
        if time.time() - dash.started > MAX_SECONDS:
            return 0
        dash.frame += 1
        # Wake early when the build reports a final state.
        deadline = time.time() + interval
        while time.time() < deadline:
            time.sleep(0.25)
            try:
                if json.loads(dash.state_path.read_text(encoding="utf-8")).get("final") and not final:
                    break
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
