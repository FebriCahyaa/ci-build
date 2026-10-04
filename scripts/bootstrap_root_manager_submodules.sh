#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
[[ -d .git ]] || { echo "ERROR: run inside the actual ci-build Git repository" >&2; exit 2; }
add_or_init(){
  local path="$1" url="$2" branch="$3"
  if [[ -e "$path" ]] && ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Never delete a non-submodule working tree silently. The caller must clean
    # an accidental vendored copy before bootstrap can create the gitlink.
    if ! git ls-files --stage -- "$path" | awk '$1 == "160000" {ok=1} END {exit ok ? 0 : 1}'; then
      echo "ERROR: $path exists but is not a Git submodule; refusing to overwrite it" >&2
      exit 2
    fi
  fi
  if git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}' | grep -Fxq "$path"; then
    git submodule sync -- "$path" >/dev/null 2>&1 || true
    if git config --file .git/config --get "submodule.$path.url" >/dev/null 2>&1; then git submodule update --init "$path"; else git submodule add -b "$branch" "$url" "$path"; fi
  else git submodule add -b "$branch" "$url" "$path"; fi
}
add_or_init third_party/root-managers/kernelsu https://github.com/tiann/KernelSU.git main
add_or_init third_party/root-managers/kernelsu-next https://github.com/KernelSU-Next/KernelSU-Next.git dev
add_or_init third_party/root-managers/resukisu https://github.com/ReSukiSU/ReSukiSU.git main
add_or_init third_party/root-managers/sukisu-ultra https://github.com/SukiSU-Ultra/SukiSU-Ultra.git main
git submodule sync --recursive; git submodule update --init --recursive
echo "Root-manager submodules initialized. Use: bash scripts/sync_root_managers.sh remote"
