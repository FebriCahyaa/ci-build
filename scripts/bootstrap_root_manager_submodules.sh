#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: run inside the actual ci-build Git repository" >&2; exit 2; }
is_gitlink(){
  local path="$1"
  git ls-files --stage -- "$path" | awk '$1 == "160000" {found=1} END {exit found ? 0 : 1}'
}

add_or_init(){
  local path="$1" url="$2" branch="$3"

  if [[ -e "$path" ]] && ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: $path exists but is not a usable Git worktree; refusing to overwrite it" >&2
    exit 2
  fi

  # .gitmodules alone is not enough. Git only treats a path as a real
  # submodule when the superproject index contains a 160000 gitlink entry.
  # Older ci-build snapshots may contain .gitmodules but have lost these
  # gitlinks (for example after exporting/importing a ZIP). Repair them here
  # so CI and local bootstrap both converge on the canonical submodule layout.
  if ! is_gitlink "$path"; then
    if [[ -n "$(git ls-files -- "$path")" ]]; then
      echo "ERROR: $path is tracked but is not a gitlink; refusing to rewrite it" >&2
      exit 2
    fi
    if [[ -e "$path" ]]; then
      echo "ERROR: $path exists but is not a registered submodule; refusing to overwrite it" >&2
      exit 2
    fi
    echo "Repairing missing submodule gitlink: $path" >&2
    git submodule add -b "$branch" "$url" "$path"
  else
    git submodule sync -- "$path" >/dev/null 2>&1 || true
    git submodule update --init "$path"
  fi
}
add_or_init third_party/root-managers/kernelsu https://github.com/tiann/KernelSU.git main
add_or_init third_party/root-managers/kernelsu-next https://github.com/KernelSU-Next/KernelSU-Next.git dev
add_or_init third_party/root-managers/resukisu https://github.com/ReSukiSU/ReSukiSU.git main
add_or_init third_party/root-managers/sukisu-ultra https://github.com/SukiSU-Ultra/SukiSU-Ultra.git main
git submodule sync --recursive; git submodule update --init --recursive
echo "Root-manager submodules initialized. Use: bash scripts/sync_root_managers.sh remote"
