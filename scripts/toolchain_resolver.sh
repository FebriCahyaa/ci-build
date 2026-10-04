#!/usr/bin/env bash
# Resolve a reproducible kernel toolchain.
#
#   TOOLCHAIN=<family|preset> TOOLCHAIN_VERSION=<rev|auto> ARCH=arm64 \
#     toolchain_resolver.sh <kernel-source-dir> <work-dir>
#
# stdout: RESOLVED_* shell assignments (shell-quoted); diagnostics go to stderr.
#
# Note: helpers that can fail are called in assignments (bin_dir="$(...)") so
# that `set -e` aborts; a failing $(...) used as a plain argument would not.
#
# Families / presets (see docs in README "Toolchains"):
#   auto            AOSP clang from the tree's build.config, else a per-kernel default
#   aosp            AOSP prebuilt clang revision (TOOLCHAIN_VERSION=clang-rXXXXXX)
#   aosp-r416183b   AOSP Clang 12 (LineageOS GitHub mirror)   Linux 4.4 .. 5.10
#   zyc-10          ZyC Clang 10.0.1                          Linux 4.4 .. 4.19
#   proton          Proton Clang 13 (kdrag0n)                 Linux 4.9 .. 5.10
#   llvm-18         Official LLVM 18.1.8 release              Linux 4.19 .. 5.10
#   neutron         Neutron Clang (latest or TOOLCHAIN_VERSION tag)  Linux 4.19+
#   llvm|system     Distribution clang from PATH
#   gcc             Distribution GNU cross compiler
#   custom URL      TOOLCHAIN_URL / CLANG_URL / GCC_URL archive
#
# Downloads are cached under TOOLCHAIN_CACHE_DIR (default <work-dir>/toolchain)
# and reused when the same toolchain id was already extracted there.
set -Eeuo pipefail

KERNEL_DIR="${1:?kernel source directory required}"
WORK_DIR="${2:?work directory required}"
REQUESTED="${TOOLCHAIN:-auto}"
VERSION_REQUEST="${TOOLCHAIN_VERSION:-auto}"
ARCH="${ARCH:-arm64}"
TC_ROOT="${TOOLCHAIN_CACHE_DIR:-$WORK_DIR/toolchain}"
TOOLCHAIN_FORCE="${TOOLCHAIN_FORCE:-false}"
# One URL input for custom archives; the family decides how it is used.
if [[ -n "${TOOLCHAIN_URL:-}" ]]; then
  case "$REQUESTED" in
    gcc) GCC_URL="${GCC_URL:-$TOOLCHAIN_URL}" ;;
    *) CLANG_URL="${CLANG_URL:-$TOOLCHAIN_URL}" ;;
  esac
fi

log() { echo "[toolchain] $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

arch_cross() {
  case "$1" in
    arm64) printf '%s\n' 'aarch64-linux-gnu-' ;;
    arm)   printf '%s\n' 'arm-linux-gnueabi-' ;;
    *)     printf '%s\n' '' ;;
  esac
}

mkdir -p "$TC_ROOT"

# ------------------------------------------------------------
# build.config hints (GKI / Android common kernels)
# ------------------------------------------------------------
BUILD_CONFIG_CLANG_BIN=""
BUILD_CONFIG_CLANG_REV=""
BUILD_CONFIG_BRANCH=""
BUILD_CONFIG_CROSS=""
strip_quotes() { local v="${1//\"/}"; printf '%s' "${v//\'/}"; }
# build.config.common/constants are authoritative; other fragments only fill gaps.
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  while IFS= read -r line; do
    value="$(strip_quotes "${line#*=}")"
    case "$line" in
      CLANG_PREBUILT_BIN=*) [[ -n "$BUILD_CONFIG_CLANG_BIN" ]] || BUILD_CONFIG_CLANG_BIN="$value" ;;
      CLANG_VERSION=*) [[ -n "$BUILD_CONFIG_CLANG_REV" ]] || BUILD_CONFIG_CLANG_REV="$value" ;;
      BRANCH=*) [[ -n "$BUILD_CONFIG_BRANCH" ]] || BUILD_CONFIG_BRANCH="$value" ;;
      CROSS_COMPILE=*) [[ -n "$BUILD_CONFIG_CROSS" ]] || BUILD_CONFIG_CROSS="$value" ;;
    esac
  done < <(grep -E '^(CLANG_PREBUILT_BIN|CLANG_VERSION|BRANCH|CROSS_COMPILE)=' "$f" 2>/dev/null || true)
done < <(
  for f in "$KERNEL_DIR/build.config.constants" "$KERNEL_DIR/build.config.common"; do [[ -f "$f" ]] && echo "$f"; done
  find "$KERNEL_DIR" -maxdepth 1 -type f -name 'build.config*' ! -name build.config.common ! -name build.config.constants | sort
)
# CLANG_VERSION may be "r416183b"; normalize to the prebuilt directory name.
[[ -z "$BUILD_CONFIG_CLANG_REV" || "$BUILD_CONFIG_CLANG_REV" == clang-* ]] || BUILD_CONFIG_CLANG_REV="clang-$BUILD_CONFIG_CLANG_REV"
if [[ -z "$BUILD_CONFIG_CLANG_REV" && -n "$BUILD_CONFIG_CLANG_BIN" ]]; then
  if [[ "$BUILD_CONFIG_CLANG_BIN" == */bin ]]; then
    BUILD_CONFIG_CLANG_REV="$(basename "$(dirname "$BUILD_CONFIG_CLANG_BIN")")"
  else
    BUILD_CONFIG_CLANG_REV="$(basename "$BUILD_CONFIG_CLANG_BIN")"
  fi
fi

KERNEL_MAJOR="$(awk '/^VERSION[[:space:]]*=/{print $3; exit}' "$KERNEL_DIR/Makefile" 2>/dev/null || true)"
KERNEL_MINOR="$(awk '/^PATCHLEVEL[[:space:]]*=/{print $3; exit}' "$KERNEL_DIR/Makefile" 2>/dev/null || true)"
KERNEL_MAJOR="${KERNEL_MAJOR:-0}"
KERNEL_MINOR="${KERNEL_MINOR:-0}"
KVER=$((KERNEL_MAJOR * 100 + KERNEL_MINOR))   # 4.4 -> 404, 4.19 -> 419, 5.10 -> 510

# require_kernel_range <family> <min> <max>: fail (unless TOOLCHAIN_FORCE) when
# the family is known not to build this kernel generation.
require_kernel_range() {
  local family="$1" min="$2" max="$3"
  if (( KVER < min || KVER > max )); then
    local msg="$family is not validated for Linux ${KERNEL_MAJOR}.${KERNEL_MINOR} (supported: $((min / 100)).$((min % 100))..$((max / 100)).$((max % 100)))"
    if [[ "${TOOLCHAIN_FORCE,,}" == true ]]; then log "WARNING: $msg (TOOLCHAIN_FORCE=true)"; else die "$msg; set TOOLCHAIN_FORCE=true to override"; fi
  fi
}

# archive_ok <file> <url>: integrity check before extraction. Gitiles streams
# generated tarballs and can end the response early with a success status, so
# a truncated archive must be detected here rather than half-extracted.
archive_ok() {
  case "$2" in
    *.tar.zst|*.tzst) zstd -tq "$1" 2>/dev/null ;;
    *.tar.xz|*.txz)   xz -t "$1" 2>/dev/null ;;
    *.tar.gz|*.tgz)   gzip -t "$1" 2>/dev/null ;;
    *)                tar -tf "$1" >/dev/null 2>&1 ;;
  esac
}

# fetch_archive <id> <url> [strip-components] [sha256]: download, verify and
# extract once into $TC_ROOT/<id>; retried on transfer or integrity failures.
# Only a complete extraction is marked ready, so the cache never keeps a
# broken toolchain. Returns non-zero (does not exit) so callers can fall back.
fetch_archive() {
  local id="$1" url="$2" strip="${3:-0}" sha="${4:-}" dest="$TC_ROOT/$1" archive attempt
  if [[ -f "$dest/.ci-toolchain-ready" ]]; then
    log "reusing cached $id"
    return 0
  fi
  archive="$TC_ROOT/$id.download"
  for attempt in 1 2 3; do
    log "downloading $id (attempt $attempt/3): $url"
    rm -f "$archive"
    # Silent transfer (a progress meter floods the log and the live view);
    # abort a stalled stream after 60s below 1 KiB/s so the retry can run.
    if ! curl -fsSL --retry 3 --retry-delay 3 --retry-all-errors --connect-timeout 30 \
        --speed-limit 1024 --speed-time 60 "$url" -o "$archive"; then
      log "download failed"
      continue
    fi
    if [[ -n "$sha" ]] && ! echo "$sha  $archive" | sha256sum -c --status -; then
      rm -f "$archive"
      die "$id sha256 mismatch (expected $sha)"
    fi
    if ! archive_ok "$archive" "$url"; then
      log "archive is truncated or corrupt ($(du -h "$archive" | cut -f1)); retrying"
      continue
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    if ! case "$url" in
      *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$dest" --strip-components="$strip" ;;
      *.tar.xz|*.txz)   tar -xJf "$archive" -C "$dest" --strip-components="$strip" ;;
      *.tar.gz|*.tgz)   tar -xzf "$archive" -C "$dest" --strip-components="$strip" ;;
      *)                tar -xf "$archive" -C "$dest" --strip-components="$strip" ;;
    esac; then
      log "extraction failed; retrying"
      continue
    fi
    log "installed $id ($(du -sh "$dest" | cut -f1))"
    rm -f "$archive"
    touch "$dest/.ci-toolchain-ready"
    return 0
  done
  rm -f "$archive"
  rm -rf "$dest"
  return 1
}

# fetch_git <id> <repo> <branch>: shallow clone once into $TC_ROOT/<id>.
fetch_git() {
  local id="$1" repo="$2" branch="$3" dest="$TC_ROOT/$1"
  if [[ -f "$dest/.ci-toolchain-ready" ]]; then
    log "reusing cached $id"
    return 0
  fi
  rm -rf "$dest"
  log "cloning $id: $repo@$branch"
  git clone -q --depth=1 --single-branch --branch "$branch" "$repo" "$dest" || return 1
  rm -rf "$dest/.git"
  touch "$dest/.ci-toolchain-ready"
}

find_clang_bin() {
  local bin
  # bin/clang is often a symlink to clang-NN inside release archives.
  bin="$(find "$TC_ROOT/$1" \( -type f -o -type l \) -path '*/bin/clang' -print -quit 2>/dev/null || true)"
  [[ -n "$bin" ]] || die "$1 toolchain contains no bin/clang"
  dirname "$bin"
}

# AOSP prebuilts: gitiles serves each revision only from branches that contain
# it (verified against android.googlesource.com), and refuses to archive the
# very large revisions; the LineageOS GitHub mirror is the reliable source there.
aosp_sources() {
  local rev="$1" base="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads"
  case "$rev" in
    clang-r416183b)
      echo "git https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b lineage-20.0"
      echo "url $base/android12-release/clang-r416183b.tar.gz" ;;
    clang-r416183b1|clang-r383902|clang-r383902b) echo "url $base/android12-release/$rev.tar.gz"; echo "url $base/android11-release/$rev.tar.gz" ;;
    clang-r353983c*|clang-r365631c|clang-r370808*|clang-r377782*)
      for branch in android11-release android11-qpr3-release android11-qpr2-release; do echo "url $base/$branch/$rev.tar.gz"; done ;;
    clang-r450784d) echo "url $base/android13-release/$rev.tar.gz" ;;
    clang-r450784e) echo "url $base/master-kernel-build-2022/$rev.tar.gz"; echo "url $base/android14-release/$rev.tar.gz" ;;
    clang-r475365b|clang-r487747c) echo "url $base/android14-release/$rev.tar.gz" ;;
    *) echo "url $base/${AOSP_CLANG_REF:-main}/$rev.tar.gz" ;;
  esac
}

use_clang() {
  TOOLCHAIN_BIN="$1"
  export PATH="$TOOLCHAIN_BIN:$PATH"
  CROSS_DEFAULT="$(arch_cross "$ARCH")"
  CLANG_TRIPLE_VALUE="$(arch_cross "$ARCH")"
  LLVM_VALUE=1
  LLVM_IAS_VALUE="${2:-1}"
}

# ------------------------------------------------------------
# Family selection
# ------------------------------------------------------------
family="$REQUESTED"
if [[ -n "${CLANG_URL:-}" ]]; then
  family=custom-clang
elif [[ -n "${GCC_URL:-}" ]]; then
  family=custom-gcc
elif [[ "$family" == auto ]]; then
  if [[ -n "$BUILD_CONFIG_CLANG_REV" ]]; then
    family=aosp
  elif (( KVER < 414 )); then
    family=gcc
  elif (( KVER < 500 )); then
    family=proton
  else
    family=aosp-r416183b
  fi
fi

CLANG_TRIPLE_VALUE=""
RESOLVED_VERSION="$VERSION_REQUEST"
TOOLCHAIN_BIN=""
CROSS_DEFAULT=""
LLVM_VALUE=0
LLVM_IAS_VALUE=0

case "$family" in
  custom-clang)
    id="custom-clang-$(printf '%s' "$CLANG_URL" | sha1sum | cut -c1-12)"
    fetch_archive "$id" "$CLANG_URL" || die "unable to download $id"
    bin_dir="$(find_clang_bin "$id")"
    use_clang "$bin_dir"
    RESOLVED_VERSION=custom-url
    ;;

  custom-gcc)
    id="custom-gcc-$(printf '%s' "$GCC_URL" | sha1sum | cut -c1-12)"
    fetch_archive "$id" "$GCC_URL" || die "unable to download $id"
    case "$ARCH" in
      arm64) gcc_name=aarch64-linux-gnu-gcc ;;
      arm) gcc_name=arm-linux-gnueabi-gcc ;;
      *) gcc_name=gcc ;;
    esac
    GCC_BIN="$(find "$TC_ROOT/$id" -type f -path "*/bin/$gcc_name" -print -quit)"
    [[ -n "$GCC_BIN" ]] || die "custom GCC archive contains no $gcc_name"
    TOOLCHAIN_BIN="$(dirname "$GCC_BIN")"
    export PATH="$TOOLCHAIN_BIN:$PATH"
    CROSS_DEFAULT="${gcc_name%gcc}"
    [[ "$ARCH" == arm64 || "$ARCH" == arm ]] && CROSS_DEFAULT="$TOOLCHAIN_BIN/$CROSS_DEFAULT"
    RESOLVED_VERSION=custom-url
    ;;

  gcc)
    case "$ARCH" in
      arm64) command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || die "aarch64-linux-gnu-gcc is missing"; CROSS_DEFAULT=aarch64-linux-gnu- ;;
      arm) command -v arm-linux-gnueabi-gcc >/dev/null 2>&1 || die "arm-linux-gnueabi-gcc is missing"; CROSS_DEFAULT=arm-linux-gnueabi- ;;
    esac
    RESOLVED_VERSION="$( "${CROSS_DEFAULT}gcc" -dumpversion 2>/dev/null || echo system)"
    ;;

  llvm|system)
    command -v clang >/dev/null 2>&1 || die "clang is missing"
    CROSS_DEFAULT="$(arch_cross "$ARCH")"
    CLANG_TRIPLE_VALUE="$(arch_cross "$ARCH")"
    LLVM_VALUE=1
    LLVM_IAS_VALUE=1
    RESOLVED_VERSION="$(clang -dumpversion 2>/dev/null || echo system)"
    ;;

  aosp)
    rev="$VERSION_REQUEST"
    [[ "$rev" == auto ]] && rev="$BUILD_CONFIG_CLANG_REV"
    [[ -n "$rev" ]] || die "cannot detect AOSP Clang revision; set TOOLCHAIN_VERSION=clang-rXXXXXX"
    [[ "$rev" == clang-* ]] || rev="clang-$rev"
    ok=false
    while read -r kind src branch; do
      case "$kind" in
        git) fetch_git "aosp-$rev" "$src" "$branch" && { ok=true; break; } ;;
        url) if fetch_archive "aosp-$rev" "$src"; then ok=true; break; fi ;;
      esac
      log "source unavailable, trying the next mirror"
    done < <(aosp_sources "$rev")
    [[ "$ok" == true ]] || die "unable to download AOSP Clang $rev from any configured source"
    bin_dir="$(find_clang_bin "aosp-$rev")"
    use_clang "$bin_dir"
    RESOLVED_VERSION="$rev"
    ;;

  aosp-r416183b)
    require_kernel_range "$family" 404 510
    fetch_git "aosp-clang-r416183b" \
      https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b lineage-20.0 ||
      die "unable to clone AOSP clang-r416183b"
    bin_dir="$(find_clang_bin aosp-clang-r416183b)"
    use_clang "$bin_dir"
    RESOLVED_VERSION="clang-r416183b"
    ;;

  zyc-10)
    require_kernel_range "$family" 404 419
    fetch_archive zyc-clang-10.0.1 \
      https://github.com/ZyCromerZ/Clang/releases/download/10.0.1-20220724-release/Clang-10.0.1-20220724.tar.gz ||
      die "unable to download ZyC Clang 10.0.1"
    bin_dir="$(find_clang_bin zyc-clang-10.0.1)"
    use_clang "$bin_dir" 0
    RESOLVED_VERSION="zyc-10.0.1-20220724"
    ;;

  proton)
    require_kernel_range "$family" 409 510
    ver="$VERSION_REQUEST"; [[ "$ver" == auto ]] && ver=20210522
    fetch_archive "proton-$ver" "https://github.com/kdrag0n/proton-clang/archive/refs/tags/${ver}.tar.gz" 1 ||
      die "unable to download Proton Clang $ver"
    use_clang "$TC_ROOT/proton-$ver/bin"
    [[ -x "$TOOLCHAIN_BIN/clang" ]] || die "Proton Clang bin/clang not found"
    RESOLVED_VERSION="proton-$ver"
    ;;

  llvm-18)
    require_kernel_range "$family" 419 510
    fetch_archive llvm-18.1.8 \
      https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz 1 ||
      die "unable to download LLVM 18.1.8"
    bin_dir="$(find_clang_bin llvm-18.1.8)"
    use_clang "$bin_dir"
    RESOLVED_VERSION="llvm-18.1.8"
    ;;

  neutron)
    require_kernel_range "$family" 419 999
    ver="$VERSION_REQUEST"
    digest=""
    if [[ "$ver" == auto || "$ver" == latest ]]; then
      metadata="$TC_ROOT/neutron-release.json"
      curl -fsSL --retry 3 https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest -o "$metadata"
      readarray -t asset_info < <(python3 - "$metadata" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding='utf-8'))
for a in p.get('assets', []):
    n = a.get('name', '')
    if n.startswith('neutron-clang-') and n.endswith('.tar.zst'):
        print(p.get('tag_name', ''))
        print(a.get('browser_download_url', ''))
        print((a.get('digest') or '').replace('sha256:', ''))
        break
PY
)
      [[ "${#asset_info[@]}" -ge 2 && -n "${asset_info[1]}" ]] || die "no Neutron release asset found"
      ver="${asset_info[0]}"
      url="${asset_info[1]}"
      digest="${asset_info[2]:-}"
    else
      url="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${ver}/neutron-clang-${ver}.tar.zst"
    fi
    fetch_archive "neutron-$ver" "$url" 0 "$digest" || die "unable to download Neutron Clang $ver"
    bin_dir="$(find_clang_bin "neutron-$ver")"
    use_clang "$bin_dir"
    RESOLVED_VERSION="neutron-$ver"
    ;;

  *)
    die "unsupported TOOLCHAIN=$family (auto, aosp, aosp-r416183b, zyc-10, proton, llvm-18, neutron, llvm, system, gcc)"
    ;;
esac

CLANG_PATH=""
if [[ "$LLVM_VALUE" == 1 ]]; then
  CLANG_PATH="$(command -v clang 2>/dev/null || true)"
  [[ -n "$CLANG_PATH" ]] || die "selected LLVM toolchain has no clang executable"
  [[ -z "$TOOLCHAIN_BIN" || "$CLANG_PATH" == "$TOOLCHAIN_BIN/clang" ]] ||
    die "$family: PATH resolves clang to $CLANG_PATH instead of $TOOLCHAIN_BIN/clang"
  if ! "$CLANG_PATH" --version >/dev/null 2>&1; then
    missing="$(ldd "$(readlink -f "$CLANG_PATH")" 2>/dev/null | awk '/not found/ {print $1}' | tr '\n' ' ')"
    die "$family clang cannot run on this host${missing:+ (missing: $missing; add the providing package to APT_PACKAGES)}"
  fi
fi

# Human-readable compiler identity consumed by build metadata and AnyKernel.
RESOLVED_COMPILER_STRING="unknown"
if [[ "$LLVM_VALUE" == 1 ]]; then
  clang_line="$("$CLANG_PATH" --version 2>/dev/null | head -n1 || true)"
  RESOLVED_COMPILER_STRING="${clang_line:-clang}"
elif [[ -n "$CROSS_DEFAULT" ]]; then
  gcc_line="$("${CROSS_DEFAULT}gcc" --version 2>/dev/null | head -n1 || true)"
  RESOLVED_COMPILER_STRING="${gcc_line:-${CROSS_DEFAULT}gcc}"
fi

printf 'RESOLVED_TOOLCHAIN=%q\n' "$family"
printf 'RESOLVED_TOOLCHAIN_BIN=%q\n' "$TOOLCHAIN_BIN"
printf 'RESOLVED_TOOLCHAIN_VERSION=%q\n' "${RESOLVED_VERSION:-system}"
printf 'RESOLVED_CLANG=%q\n' "$CLANG_PATH"
printf 'RESOLVED_COMPILER_STRING=%q\n' "$RESOLVED_COMPILER_STRING"
printf 'RESOLVED_CLANG_TRIPLE=%q\n' "$CLANG_TRIPLE_VALUE"
printf 'RESOLVED_CROSS_DEFAULT=%q\n' "$CROSS_DEFAULT"
printf 'RESOLVED_LLVM=%q\n' "$LLVM_VALUE"
printf 'RESOLVED_LLVM_IAS=%q\n' "$LLVM_IAS_VALUE"
printf 'RESOLVED_BUILD_CONFIG_CLANG_BIN=%q\n' "$BUILD_CONFIG_CLANG_BIN"
printf 'RESOLVED_BUILD_CONFIG_BRANCH=%q\n' "$BUILD_CONFIG_BRANCH"
printf 'RESOLVED_BUILD_CONFIG_CROSS=%q\n' "$BUILD_CONFIG_CROSS"
log "family=$family version=${RESOLVED_VERSION:-system} clang=${CLANG_PATH:-none} cross=${CROSS_DEFAULT:-none} llvm_ias=$LLVM_IAS_VALUE"
