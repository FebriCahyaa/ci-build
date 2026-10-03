#!/usr/bin/env bash
set -Eeuo pipefail

SRC_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_ROOT="${1:-}"

if [[ -z "$DEST_ROOT" ]]; then
  cat >&2 <<'USAGE'
Usage:
  ./scripts/install_modular_patch_registry.sh /path/to/ci-build

The destination must be a CI-Build git working tree.
The script creates timestamped backups of modified files.
USAGE
  exit 2
fi

DEST_ROOT="$(cd -- "$DEST_ROOT" && pwd)"
test -d "$DEST_ROOT/.git" || {
  echo "ERROR: destination is not a git working tree: $DEST_ROOT" >&2
  exit 1
}

timestamp="$(date +%Y%m%d-%H%M%S)"
backup="$DEST_ROOT/.ci-build-backup-$timestamp"
mkdir -p "$backup"

backup_file() {
  local rel="$1"
  if [[ -f "$DEST_ROOT/$rel" ]]; then
    mkdir -p "$backup/$(dirname "$rel")"
    cp -a "$DEST_ROOT/$rel" "$backup/$rel"
    echo "[install] backup $rel"
  fi
}

copy_file() {
  local rel="$1"
  mkdir -p "$DEST_ROOT/$(dirname "$rel")"
  cp -a "$SRC_ROOT/$rel" "$DEST_ROOT/$rel"
  echo "[install] install $rel"
}

backup_file scripts/build_kernel.sh
backup_file scripts/apply_patch_series.sh
backup_file scripts/set_kernel_name.sh
backup_file scripts/install_modular_patch_registry.sh
backup_file kernel-name
backup_file harness/kernel-pipeline.yaml
backup_file .github/workflows/ci-validation.yml
backup_file README.md

copy_file scripts/build_kernel.sh
copy_file scripts/apply_patch_series.sh
copy_file scripts/set_kernel_name.sh
copy_file scripts/install_modular_patch_registry.sh
copy_file kernel-name
copy_file harness/kernel-pipeline.yaml
copy_file .github/workflows/ci-validation.yml
copy_file README.md

rm -rf "$DEST_ROOT/patches"
cp -a "$SRC_ROOT/patches" "$DEST_ROOT/patches"

echo
bash -n "$DEST_ROOT/scripts/build_kernel.sh"
bash -n "$DEST_ROOT/scripts/apply_patch_series.sh"
bash -n "$DEST_ROOT/scripts/set_kernel_name.sh"

echo "[install] PASS"
echo "[install] backup=$backup"
