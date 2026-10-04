#!/usr/bin/env python3
"""Validate the local patch registry without requiring a kernel checkout."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATCH_ROOT = ROOT / "patches"
HUNK_RE = re.compile(
    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:\s.*)?$"
)


def fail(message: str) -> None:
    print(f"[patch-format] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_patch(path: Path) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()

    if any(line == "@@" for line in lines):
        fail(f"bare '@@' hunk header in {path.relative_to(ROOT)}")

    for index, header in enumerate(lines):
        if not header.startswith("@@ "):
            continue

        match = HUNK_RE.match(header)
        if not match:
            fail(f"invalid hunk header in {path.relative_to(ROOT)}: {header}")

        end = index + 1
        while end < len(lines):
            candidate = lines[end]
            if candidate.startswith("@@ ") or candidate.startswith("diff --git "):
                break
            end += 1

        body = lines[index + 1 : end]
        invalid = [line for line in body if line and line[0] not in " +-\\"]
        if invalid:
            fail(
                f"invalid hunk line in {path.relative_to(ROOT)}: "
                f"{invalid[0]!r}"
            )

        expected_old = int(match.group(2) or "1")
        expected_new = int(match.group(4) or "1")
        actual_old = sum(line.startswith((" ", "-")) for line in body)
        actual_new = sum(line.startswith((" ", "+")) for line in body)

        if (actual_old, actual_new) != (expected_old, expected_new):
            fail(
                f"hunk count mismatch in {path.relative_to(ROOT)}: {header}; "
                f"found old/new={actual_old}/{actual_new}, "
                f"expected={expected_old}/{expected_new}"
            )


SERIES_NAMES = ("series.conf", "host-series.conf", "provider-series.conf")


def series_entries(path: Path) -> list[Path]:
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        entries.append(Path(entry) if entry.startswith("/") else path.parent / entry)
    return entries


def validate_series(path: Path) -> list[Path]:
    entries = series_entries(path)
    for patch in entries:
        if not patch.is_file():
            fail(
                f"series {path.relative_to(ROOT)} references missing patch "
                f"{patch.relative_to(ROOT) if patch.is_relative_to(ROOT) else patch}"
            )
    return entries


def main() -> int:
    patches = sorted(PATCH_ROOT.rglob("*.patch"))
    if not patches:
        fail("no .patch files found")
    for patch in patches:
        validate_patch(patch)

    series = sorted(p for name in SERIES_NAMES for p in PATCH_ROOT.rglob(name))
    for legacy in (p for p in series if p.name == "series.conf" and "root-manager" in p.parts):
        fail(f"{legacy.relative_to(ROOT)}: root-manager patches must be listed in "
             "provider-series.conf or host-series.conf")

    referenced: set[Path] = set()
    for series_file in series:
        referenced.update(p.resolve() for p in validate_series(series_file))

    # A patch that no series lists is dead code: it is never applied and
    # silently drifts away from the trees it was written for.
    orphans = [p for p in patches if p.resolve() not in referenced]
    if orphans:
        fail("unreferenced patch files: " + ", ".join(str(p.relative_to(ROOT)) for p in orphans))

    print(f"[patch-format] PASS: {len(patches)} patches, {len(series)} series files, no orphans")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
