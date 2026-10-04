#!/usr/bin/env python3
"""Merge key=value pairs into the build progress state file (atomically).

  progress_state.py <state.json> pct=44 phase=compile detail="objects 1/2" final=false

Integers and true/false are stored as JSON numbers/booleans; everything else as
strings. `updated` is refreshed on every write. Readers (tg_dashboard.py)
never observe a partially written file because the update is a rename.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path


def coerce(value: str):
    if value in ("true", "false"):
        return value == "true"
    if value.lstrip("-").isdigit() and len(value) < 18:
        return int(value)
    return value


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        state = {}
    for pair in sys.argv[2:]:
        key, sep, value = pair.partition("=")
        if not sep or not key:
            print(f"invalid pair: {pair!r}", file=sys.stderr)
            return 2
        state[key] = coerce(value)
    state["updated"] = time.time()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False)
    os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
