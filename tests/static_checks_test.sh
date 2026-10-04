#!/usr/bin/env bash
# Static checks: shell syntax, shellcheck (error level), Python syntax, patch
# registry format, and the executable-bit contract of tracked scripts.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Vendored upstream AnyKernel3 files keep their upstream style.
VENDORED='^anykernel/(anykernel\.sh|tools/ak3-core\.sh|META-INF/)'
mapfile -t shells < <(find scripts tests anykernel aws -type f -name '*.sh' | sort)
bash -n "${shells[@]}"
echo "PASS bash -n (${#shells[@]} files)"

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t owned < <(printf '%s\n' "${shells[@]}" | grep -Ev "$VENDORED")
  shellcheck -S error -x "${owned[@]}"
  echo "PASS shellcheck -S error (${#owned[@]} files)"
else
  echo "SKIP shellcheck (not installed)"
fi

mapfile -t pys < <(find scripts tests -type f -name '*.py' | sort)
python3 - "${pys[@]}" <<'PY'
import ast, sys
for path in sys.argv[1:]:
    ast.parse(open(path, encoding="utf-8").read(), path)
PY
echo "PASS python syntax (${#pys[@]} files)"

python3 scripts/validate_patch_format.py

# Executable bits: every tracked *.sh/*.py entry point is 100755; data files are not.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bad=0
  while read -r mode _ _ path; do
    case "$path" in
      *.sh|*.py)
        [[ "$path" =~ $VENDORED ]] && continue
        [[ "$mode" == 100755 ]] || { echo "not executable in git: $path ($mode)" >&2; bad=1; } ;;
      *.conf|*.patch|*.md|*.fragment|*.config|*.yml|*.yaml)
        [[ "$mode" == 100644 ]] || { echo "data file marked executable: $path ($mode)" >&2; bad=1; } ;;
    esac
  done < <(git ls-files -s -- scripts tests anykernel aws patches profiles harness .github)
  ((bad == 0)) || fail "executable-bit contract (fix with: git update-index --chmod=+x <file>)"
  echo "PASS executable-bit contract"
fi
