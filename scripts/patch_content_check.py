#!/usr/bin/env python3
"""Detect a patch whose resulting additions are already present in a source tree.

This is intentionally a conservative fallback for shallow Git clones where
`git apply -R --check` can fail even though a later vendor commit already
contains the upstream change.
"""
from __future__ import annotations

import sys
from pathlib import Path


def collect_additions(patch: Path) -> dict[str, list[str]]:
    files: dict[str, list[str]] = {}
    current: str | None = None

    for raw in patch.read_text(encoding="utf-8").splitlines():
        if raw.startswith("diff --git a/"):
            current = None
            continue
        if raw.startswith("+++ b/"):
            current = raw[6:].strip()
            files.setdefault(current, [])
            continue
        if current is None:
            continue
        if raw.startswith("+") and not raw.startswith("+++"):
            line = raw[1:]
            if line.strip():
                files[current].append(line)

    return files


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch_content_check.py SOURCE_DIR PATCH", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]).resolve()
    patch = Path(sys.argv[2]).resolve()
    additions = collect_additions(patch)

    total = 0
    for relative, lines in additions.items():
        target = source / relative
        if not target.is_file():
            return 1
        content = target.read_text(encoding="utf-8", errors="replace").splitlines()
        available = set(content)
        unique_lines = set(lines)
        total += len(unique_lines)
        if not unique_lines or not unique_lines.issubset(available):
            return 1

    # Require multiple resulting lines so a coincidental single-line match
    # cannot classify an unapplied patch as already present.
    if total < 3:
        return 1

    print(f"[patches] CONTENT MATCH {patch} ({total} added lines already present)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())