#!/usr/bin/env bash
# update-binary runtime contract: Android/ROM detection, no build-info dump while
# flashing, supported Android range, and narrow banner rendering.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UB="$ROOT/anykernel/META-INF/com/google/android/update-binary"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bash -n "$UB" || fail "update-binary syntax"

# Static contract.
! grep -q 'ui_printfile version' "$UB" || fail "build-info dump must not be printed while flashing"
grep -q '^SUPPORTED_VERSIONS="11 - 17"' "$ROOT/anykernel/profiles/lavender-4.19.conf" || fail "lavender-4.19 must support Android 11 - 17"
! grep -q 'Android    : [0-9]' "$ROOT/anykernel/banner" || fail "banner must not hard-code an Android range"
! grep -rq 'ANDROID_LABEL' "$ROOT/anykernel" || fail "ANDROID_LABEL is obsolete"

# Load only the detection helpers and drive them with a fake getprop.
helpers="$TMP/helpers.sh"
{
  echo 'file_getprop() { grep "^$2=" "$1" | tail -n1 | cut -d= -f2-; }'
  sed -n '/^rom_prop()/,/^do_devicecheck()/p' "$UB" | sed '$d'
} > "$helpers"

run_case() { # run_case <expected-rom> <expected-android> prop=value...
  local want_rom="$1" want_android="$2"; shift 2
  (
    declare -A P=()
    for kv in "$@"; do P["${kv%%=*}"]="${kv#*=}"; done
    getprop() { printf '%s' "${P[$1]:-}"; }
    # shellcheck source=/dev/null
    source "$helpers"
    detect_android_rom
    [[ "$AK_ROM" == "$want_rom" ]] || { echo "ROM: got '$AK_ROM' want '$want_rom'" >&2; exit 1; }
    [[ "$AK_ANDROID" == "$want_android" ]] || { echo "Android: got '$AK_ANDROID' want '$want_android'" >&2; exit 1; }
  ) || fail "detection case: $*"
}

run_case "LineageOS 21.0" "14 (SDK 34)" ro.build.version.release=14 ro.build.version.sdk=34 ro.lineage.version=21.0-20260101-NIGHTLY-lavender
run_case "crDroid 11.4"   "15 (SDK 35)" ro.build.version.release=15 ro.build.version.sdk=35 ro.lineage.version=22.2-x ro.crdroid.version=11.4
run_case "Evolution X 10.1" "16 (SDK 36)" ro.build.version.release=16 ro.build.version.sdk=36 ro.evolution.version=10.1-UNOFFICIAL
run_case "HyperOS OS1.0"  "14 (SDK 34)" ro.build.version.release=14 ro.build.version.sdk=34 ro.mi.os.version.name=OS1.0 ro.miui.ui.version.name=V816
run_case "AOSP"           "17 (SDK 37)" ro.build.version.release=17 ro.build.version.sdk=37 ro.build.flavor=aosp_lavender-userdebug
run_case "Unknown"        "Unknown"     ro.nothing=1
echo "PASS Android/ROM detection (6 cases)"

# Banner token substitution keeps special characters literal.
(
  cd "$TMP"
  printf 'Android    : @RT_ANDROID@\nROM        : @RT_ROM@\n' > banner
  AK_ANDROID='14 (SDK 34)'; AK_ROM='A&B|C\D'
  # shellcheck source=/dev/null
  source "$helpers"
  render_banner
  grep -qxF 'Android    : 14 (SDK 34)' banner || exit 1
  grep -qxF 'ROM        : A&B|C\D' banner || exit 1
) || fail "render_banner must substitute values literally"
echo "PASS banner runtime substitution"

# Version gate accepts 11..17 and rejects 10/18 using the real do_versioncheck.
vgate="$TMP/vgate.sh"
{
  echo 'file_getprop() { grep "^$2=" "$1" | tail -n1 | cut -d= -f2-; }'
  sed -n '/^int2ver()/,/^do_levelcheck()/p' "$UB" | sed '$d'
} > "$vgate"
for v in 11 12 13 14 15 16 17 18 10; do
  d="$TMP/ver$v"; mkdir -p "$d"
  printf 'supported.versions=11 - 17\n' > "$d/anykernel.sh"
  out="$(
    cd "$d"
    set +u # the stock helper relies on unset locals
    ui_print() { :; }
    abort() { echo ABORT; }
    # shellcheck source=/dev/null
    source "$vgate"
    file_getprop() {
      if [[ "$1" == /system/build.prop ]]; then echo "$v"; else grep "^$2=" "$1" | tail -n1 | cut -d= -f2-; fi
    }
    do_versioncheck
  )"
  case "$v" in
    10|18) [[ "$out" == ABORT ]] || fail "Android $v must be rejected" ;;
    *)     [[ "$out" != ABORT ]] || fail "Android $v must be accepted" ;;
  esac
done
echo "PASS supported.versions 11 - 17"
