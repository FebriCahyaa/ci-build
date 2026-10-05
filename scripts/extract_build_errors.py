#!/usr/bin/env python3
"""Extract readable diagnostics from a kernel build log.

  extract_build_errors.py <build.log> --excerpt      short block for Telegram
  extract_build_errors.py <build.log> --summary ...  full failure-summary body

The excerpt is the first real error with a few lines of context (the line that
actually broke the build, not the cascade of `make: *** Error 2` that follows),
followed by the failing make target. The summary adds every unique error line
and the log tail.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# Ordered by how precisely they identify the root cause.
PRIMARY = [
    re.compile(r"\b(fatal )?error:", re.I),
    re.compile(r"undefined reference to|multiple definition of", re.I),
    re.compile(r"No rule to make target", re.I),
    re.compile(r"\*\*\* .*(Stop|Error)", re.I),
    re.compile(r"(Killed|out of memory|Segmentation fault|Permission denied|cannot find|not found)", re.I),
    re.compile(r"\[(build|root-manager|patches|toolchain|susfs|variants|anykernel)\] ERROR", re.I),
    re.compile(r"^(ERROR|FATAL|fatal):|unexpected end of file|Error is not recoverable", re.I),
]
NOISE = re.compile(r"(-W(no-)?error|error\.o\b|errors? (were|was) |\berror_[a-z]|_error\b)", re.I)
MAKE_CASCADE = re.compile(r"^make(\[\d+\])?: \*\*\* .*Error \d+")


def load(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    return [ANSI.sub("", line.rstrip("\r")) for line in text.splitlines()]


def is_error(line: str, pattern: re.Pattern[str]) -> bool:
    if not pattern.search(line):
        return False
    # Compiler diagnostics ("file.c:1:2: error: ... [-Werror=...]") are always
    # real; the looser patterns must not fire on object names like uterror.o.
    return pattern is PRIMARY[0] or not NOISE.search(line)


def first_error(lines: list[str]) -> int | None:
    for pattern in PRIMARY:
        for index, line in enumerate(lines):
            if is_error(line, pattern) and not MAKE_CASCADE.match(line.strip()):
                return index
    return None


def excerpt(lines: list[str], before: int = 3, after: int = 4) -> str:
    index = first_error(lines)
    if index is None:
        tail = [line for line in lines if line.strip() and not line.startswith("[CI-HEARTBEAT]")]
        return "\n".join(tail[-12:]) or "(build log is empty)"
    block = lines[max(0, index - before): index + after + 1]
    failing = next((line.strip() for line in lines[index:] if MAKE_CASCADE.match(line.strip())), "")
    if failing and failing not in block:
        block += ["…", failing]
    return "\n".join(line[:200] for line in block)


def unique_errors(lines: list[str], limit: int = 60) -> list[str]:
    seen: list[str] = []
    for line in lines:
        if any(is_error(line, p) for p in PRIMARY) and line.strip() not in seen:
            seen.append(line.strip())
        if len(seen) >= limit:
            break
    return seen


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[2] not in ("--excerpt", "--summary"):
        print(__doc__, file=sys.stderr)
        return 2
    lines = load(Path(sys.argv[1]))
    if sys.argv[2] == "--excerpt":
        print(excerpt(lines))
        return 0
    print("=== First error (with context) ===")
    print(excerpt(lines, before=6, after=8))
    print()
    errors = unique_errors(lines)
    print(f"=== Unique error lines ({len(errors)}) ===")
    print("\n".join(errors) if errors else "(no compiler/make diagnostic matched)")
    print()
    tail = [line for line in lines if not line.startswith("[CI-HEARTBEAT]")]
    print("=== Last 300 log lines ===")
    print("\n".join(tail[-300:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
