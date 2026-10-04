#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; fail=0
check(){ grep -qE "$2" "$1" && echo "PASS: $3" || { echo "FAIL: $3" >&2; fail=1; }; }
check "$ROOT/.gitmodules" 'third_party/root-managers/kernelsu' 'KernelSU submodule path'
check "$ROOT/.gitmodules" 'https://github.com/tiann/KernelSU\.git' 'KernelSU upstream URL'
check "$ROOT/.gitmodules" 'third_party/root-managers/kernelsu-next' 'KernelSU-Next submodule path'
check "$ROOT/.gitmodules" 'https://github.com/KernelSU-Next/KernelSU-Next\.git' 'KernelSU-Next upstream URL'
check "$ROOT/.gitmodules" 'third_party/root-managers/resukisu' 'ReSukiSU submodule path'
check "$ROOT/.gitmodules" 'https://github.com/ReSukiSU/ReSukiSU\.git' 'ReSukiSU upstream URL'
check "$ROOT/.gitmodules" 'third_party/root-managers/sukisu-ultra' 'SukiSU Ultra submodule path'
check "$ROOT/.gitmodules" 'https://github.com/SukiSU-Ultra/SukiSU-Ultra\.git' 'SukiSU Ultra upstream URL'
check "$ROOT/scripts/root_manager_apply.sh" 'ROOT_MANAGER_SOURCE_ROOT' 'configurable root-manager source root'
check "$ROOT/scripts/root_manager_apply.sh" 'prepare_from_submodule' 'submodule snapshot path'
check "$ROOT/scripts/root_manager_apply.sh" 'git clone -q --local --no-hardlinks' 'isolated submodule checkout'
check "$ROOT/scripts/sync_root_managers.sh" 'git submodule update --init --recursive' 'recursive submodule sync'
exit "$fail"
