#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

check_series() {
  local provider="$1"
  local dir="$ROOT/patches/root-manager/$provider/4.4"
  local source="$ROOT/third_party/root-managers/$provider"
  local tmp
  test -f "$dir/series.conf" || { echo "FAIL: missing $dir/series.conf" >&2; fail=1; return; }

  # CI intentionally checks out the superproject without recursive
  # submodules. Never run git -C against a missing provider worktree.
  if [[ ! -d "$source" ]]; then
    echo "SKIP: $provider submodule worktree is not present"
    return 0
  fi
  if ! git -C "$source" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "SKIP: $provider submodule is not initialized"
    return 0
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone -q --local --no-hardlinks "$source" "$tmp/provider"
  while IFS= read -r patch || [[ -n "$patch" ]]; do
    [[ -z "$patch" || "$patch" == \#* ]] && continue
    test -f "$dir/$patch" || { echo "FAIL: missing provider patch $dir/$patch" >&2; fail=1; continue; }
    if git -C "$tmp/provider" apply --check --whitespace=error-all "$dir/$patch"; then
      echo "PASS: $provider 4.4 patch preflight $patch"
      git -C "$tmp/provider" apply --whitespace=error-all "$dir/$patch"
    else
      echo "FAIL: $provider 4.4 patch does not apply cleanly" >&2
      fail=1
    fi
  done < "$dir/series.conf"
  rm -rf "$tmp"
  trap - RETURN
}

check_series kernelsu-next
check_series sukisu-ultra

# Static regression guards for the 4.4 compatibility layer.
grep -q 'KERNEL_VERSION(4, 8, 0)' "$ROOT/patches/root-manager/kernelsu-next/4.4/0001-linux-4.4-compat.patch" && echo 'PASS: KSU-Next nofault compat guard' || { echo 'FAIL: KSU-Next nofault compat guard' >&2; fail=1; }
grep -q 'KERNEL_VERSION(4, 11, 0)' "$ROOT/patches/root-manager/kernelsu-next/4.4/0001-linux-4.4-compat.patch" && echo 'PASS: KSU-Next refcount compat guard' || { echo 'FAIL: KSU-Next refcount compat guard' >&2; fail=1; }
grep -q 'pud = pud_offset(pgd, addr)' "$ROOT/patches/root-manager/kernelsu-next/4.4/0001-linux-4.4-compat.patch" && echo 'PASS: KSU-Next pre-P4D page-table path' || { echo 'FAIL: KSU-Next pre-P4D page-table path' >&2; fail=1; }
grep -q 'kernel/kpm/compat/linux/set_memory.h' "$ROOT/patches/root-manager/sukisu-ultra/4.4/0001-linux-4.4-compat.patch" && echo 'PASS: SukiSU KPM set_memory shim' || { echo 'FAIL: SukiSU KPM set_memory shim' >&2; fail=1; }
grep -q '^diff --git a/kernel/kpm/compat/linux/set_memory.h b/kernel/kpm/compat/linux/set_memory.h' "$ROOT/patches/root-manager/sukisu-ultra/4.4/0001-linux-4.4-compat.patch" && echo 'PASS: SukiSU KPM compat header is included in patch' || { echo 'FAIL: SukiSU KPM compat header missing from patch' >&2; fail=1; }
grep -q 'KERNEL_VERSION(4, 12, 0)' "$ROOT/patches/root-manager/sukisu-ultra/4.4/0001-linux-4.4-compat.patch" && echo 'PASS: SukiSU kvmalloc compat guard' || { echo 'FAIL: SukiSU kvmalloc compat guard' >&2; fail=1; }

exit "$fail"
