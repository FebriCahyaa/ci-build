#!/usr/bin/env bash
# Assemble deterministic release assets from one or more nested build workspaces.
# This is shared by GitHub Actions and Harness so release assembly never depends
# on a particular artifact-download directory shape.
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
CI_LOG_TAG=release-assemble

SOURCE_ROOT="${SOURCE_ROOT:-${INFO_ROOT:-}}"
ASSET_DIR="${ASSET_DIR:-}"
CHANGELOG_OUT="${CHANGELOG_OUT:-}"
BUILD_PROFILE="${BUILD_PROFILE:-unknown}"

: "${SOURCE_ROOT:?SOURCE_ROOT is required}"
: "${ASSET_DIR:?ASSET_DIR is required}"
: "${CHANGELOG_OUT:?CHANGELOG_OUT is required}"
[[ -d "$SOURCE_ROOT" ]] || ci_die "SOURCE_ROOT does not exist: $SOURCE_ROOT"

mkdir -p "$ASSET_DIR" "$(dirname -- "$CHANGELOG_OUT")"
shopt -s nullglob

copy_unique() {
  local src="$1" name dest stem ext candidate i
  name="$(basename "$src")"
  dest="$ASSET_DIR/$name"
  if [[ ! -e "$dest" ]]; then
    cp -f "$src" "$dest"
    return 0
  fi
  if cmp -s "$src" "$dest" 2>/dev/null; then
    return 0
  fi

  stem="$name"
  ext=""
  if [[ "$name" == *.tar.gz ]]; then
    stem="${name%.tar.gz}"
    ext=".tar.gz"
  elif [[ "$name" == *.* ]]; then
    stem="${name%.*}"
    ext=".${name##*.}"
  fi

  candidate="$ASSET_DIR/${stem}-${BUILD_PROFILE}${ext}"
  i=2
  while [[ -e "$candidate" ]]; do
    candidate="$ASSET_DIR/${stem}-${BUILD_PROFILE}-${i}${ext}"
    i=$((i + 1))
  done
  cp -f "$src" "$candidate"
}

package_count=0
while IFS= read -r -d '' file; do
  copy_unique "$file"
  package_count=$((package_count + 1))
done < <(
  find "$SOURCE_ROOT" -type f \( -name '*.tar.gz' -o -name '*.zip' \) \
    -not -path "$ASSET_DIR/*" -print0 | sort -z
)

# Preserve failure diagnostics with a unique variant prefix. They are useful on
# partial matrix failures and never overwrite each other.
while IFS= read -r -d '' file; do
  rel="${file#"$SOURCE_ROOT/"}"
  safe="$(dirname -- "$rel" | tr '/[:space:]' '--' | sed -E 's/[^A-Za-z0-9_.-]+/-/g; s/-+/-/g; s/^-|-$//g')"
  [[ -n "$safe" && "$safe" != "." ]] || safe="build"
  base="$(basename "$file")"
  cp -f "$file" "$ASSET_DIR/${safe}-${base}"
done < <(
  find "$SOURCE_ROOT" -type f \( -name 'failure-summary.txt' -o -name 'failure-build.log.gz' \) \
    -not -path "$ASSET_DIR/*" -print0 | sort -z
)

# Include the matrix result when it exists. It is intentionally named uniquely
# because nested Harness/GitHub workspaces can otherwise collide.
if [[ -n "${MATRIX_SUMMARY:-}" && -f "$MATRIX_SUMMARY" ]]; then
  cp -f "$MATRIX_SUMMARY" "$ASSET_DIR/MATRIX-SUMMARY.txt"
elif [[ -f "$SOURCE_ROOT/matrix-summary.txt" ]]; then
  cp -f "$SOURCE_ROOT/matrix-summary.txt" "$ASSET_DIR/MATRIX-SUMMARY.txt"
fi

# Aggregate changelog from per-variant build-info files when available. On a
# total early failure there may be no successful variant, so keep the release
# workspace useful rather than failing before diagnostics are assembled.
if find "$SOURCE_ROOT" -type f -name build-info.txt -print -quit | grep -q .; then
  INFO_ROOT="$SOURCE_ROOT" OUT_FILE="$CHANGELOG_OUT" \
    bash "$CI_ROOT/scripts/generate_changelog.sh" aggregate
else
  {
    printf '# Zairenkai CI Build\n\n'
    printf 'Profile: `%s`\n\n' "$BUILD_PROFILE"
    printf 'No completed variant produced `build-info.txt`.\n'
  } > "$CHANGELOG_OUT"
fi

MATRIX_SUMMARY="${MATRIX_SUMMARY:-}"
if [[ -n "$MATRIX_SUMMARY" && -f "$MATRIX_SUMMARY" ]]; then
  {
    printf '\n## Matrix result\n\n'
    printf '```text\n'
    cat "$MATRIX_SUMMARY"
    printf '```\n'
  } >> "$CHANGELOG_OUT"
fi

cp -f "$CHANGELOG_OUT" "$ASSET_DIR/CHANGELOG.md"

# Generate checksums only for installable artifacts + changelog. Diagnostics are
# published separately and are not mixed into the release checksum contract.
if (( package_count > 0 )); then
  mapfile -t CHECKSUM_FILES < <(
    find "$ASSET_DIR" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.zip' -o -name 'CHANGELOG.md' \) \
      -printf '%f\n' | sort
  )
  (
    cd "$ASSET_DIR"
    sha256sum "${CHECKSUM_FILES[@]}" > SHA256SUMS
  )
else
  rm -f "$ASSET_DIR/SHA256SUMS"
fi

printf '[release-assemble] packages=%s assets=%s dir=%s\n' \
  "$package_count" "$(find "$ASSET_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')" "$ASSET_DIR"
