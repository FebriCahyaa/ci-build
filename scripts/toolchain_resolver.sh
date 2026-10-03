#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve a reproducible kernel toolchain.
# stdout is shell assignments; diagnostics go to stderr.

KERNEL_DIR="${1:?kernel source directory required}"
WORK_DIR="${2:?work directory required}"
REQUESTED="${TOOLCHAIN:-auto}"
VERSION_REQUEST="${TOOLCHAIN_VERSION:-auto}"
ARCH="${ARCH:-arm64}"

mkdir -p "$WORK_DIR/toolchain"
TC_ROOT="$WORK_DIR/toolchain"
BUILD_CONFIG_CLANG_BIN=""
BUILD_CONFIG_CLANG_REV=""
BUILD_CONFIG_BRANCH=""

while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  while IFS= read -r line; do
    case "$line" in
      CLANG_PREBUILT_BIN=*) BUILD_CONFIG_CLANG_BIN="${line#*=}"; BUILD_CONFIG_CLANG_BIN="${BUILD_CONFIG_CLANG_BIN//\"/}" ;;
      CLANG_VERSION=*) BUILD_CONFIG_CLANG_REV="${line#*=}"; BUILD_CONFIG_CLANG_REV="${BUILD_CONFIG_CLANG_REV//\"/}" ;;
      BRANCH=*) [[ -z "$BUILD_CONFIG_BRANCH" ]] && BUILD_CONFIG_BRANCH="${line#*=}" ;;
    esac
  done < <(grep -E '^(CLANG_PREBUILT_BIN|CLANG_VERSION|BRANCH)=' "$f" 2>/dev/null || true)
done < <(find "$KERNEL_DIR" -maxdepth 1 -type f -name 'build.config*' | sort)

KERNEL_MAJOR="$(awk '/^VERSION[[:space:]]*=/{print $3; exit}' "$KERNEL_DIR/Makefile" 2>/dev/null || echo 0)"
KERNEL_MINOR="$(awk '/^PATCHLEVEL[[:space:]]*=/{print $3; exit}' "$KERNEL_DIR/Makefile" 2>/dev/null || echo 0)"

family="$REQUESTED"
if [[ -n "${CLANG_URL:-}" ]]; then
  family=custom-clang
elif [[ -n "${GCC_URL:-}" ]]; then
  family=custom-gcc
elif [[ "$family" == auto ]]; then
  if [[ -n "$BUILD_CONFIG_CLANG_BIN" || -n "$BUILD_CONFIG_CLANG_REV" ]]; then
    family=aosp
  elif ((KERNEL_MAJOR < 4 || (KERNEL_MAJOR == 4 && KERNEL_MINOR < 14))); then
    family=gcc
  elif ((KERNEL_MAJOR == 4)); then
    family=proton
  else
    family=aosp
  fi
fi

CLANG_TRIPLE_VALUE=""
RESOLVED_VERSION="${VERSION_REQUEST:-auto}"

case "$family" in
  custom-clang)
    archive="$WORK_DIR/custom-clang-toolchain.tar"
    echo "[toolchain] downloading custom Clang archive" >&2
    curl -fL --retry 3 --retry-delay 2 "$CLANG_URL" -o "$archive"
    rm -rf "$TC_ROOT/custom-clang"
    mkdir -p "$TC_ROOT/custom-clang"
    case "$CLANG_URL" in
      *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$TC_ROOT/custom-clang" ;;
      *) tar -xf "$archive" -C "$TC_ROOT/custom-clang" ;;
    esac
    BIN="$(find "$TC_ROOT/custom-clang" -type f -path '*/bin/clang' -print -quit)"
    [[ -n "$BIN" ]] || { echo "ERROR: custom Clang archive contains no bin/clang" >&2; exit 1; }
    export PATH="$(dirname "$BIN"):$PATH"
    CROSS_DEFAULT=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    CLANG_TRIPLE_VALUE=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    LLVM_VALUE=1
    LLVM_IAS_VALUE=1
    RESOLVED_VERSION=custom-url
    ;;

  custom-gcc)
    archive="$WORK_DIR/custom-gcc-toolchain.tar"
    echo "[toolchain] downloading custom GCC archive" >&2
    curl -fL --retry 3 --retry-delay 2 "$GCC_URL" -o "$archive"
    rm -rf "$TC_ROOT/custom-gcc"
    mkdir -p "$TC_ROOT/custom-gcc"
    case "$GCC_URL" in
      *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$TC_ROOT/custom-gcc" ;;
      *) tar -xf "$archive" -C "$TC_ROOT/custom-gcc" ;;
    esac
    if [[ "$ARCH" == arm64 ]]; then
      GCC_BIN="$(find "$TC_ROOT/custom-gcc" -type f -path '*/bin/aarch64-linux-gnu-gcc' -print -quit)"
      CROSS_DEFAULT="$([[ -n "$GCC_BIN" ]] && dirname "$GCC_BIN")/aarch64-linux-gnu-"
      [[ -n "$GCC_BIN" ]] || { echo "ERROR: custom GCC archive contains no aarch64-linux-gnu-gcc" >&2; exit 1; }
    elif [[ "$ARCH" == arm ]]; then
      GCC_BIN="$(find "$TC_ROOT/custom-gcc" -type f -path '*/bin/arm-linux-gnueabi-gcc' -print -quit)"
      CROSS_DEFAULT="$([[ -n "$GCC_BIN" ]] && dirname "$GCC_BIN")/arm-linux-gnueabi-"
      [[ -n "$GCC_BIN" ]] || { echo "ERROR: custom GCC archive contains no arm-linux-gnueabi-gcc" >&2; exit 1; }
    else
      GCC_BIN="$(find "$TC_ROOT/custom-gcc" -type f -name 'gcc' -print -quit)"
      CROSS_DEFAULT=""
      [[ -n "$GCC_BIN" ]] || { echo "ERROR: custom GCC archive contains no gcc" >&2; exit 1; }
    fi
    export PATH="$(dirname "$GCC_BIN"):$PATH"
    CLANG_TRIPLE_VALUE=""
    LLVM_VALUE=0
    LLVM_IAS_VALUE=0
    RESOLVED_VERSION=custom-url
    ;;

  gcc)
    if [[ "$ARCH" == arm64 ]]; then
      command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || { echo "ERROR: aarch64-linux-gnu-gcc is missing" >&2; exit 1; }
      CROSS_DEFAULT=aarch64-linux-gnu-
    elif [[ "$ARCH" == arm ]]; then
      command -v arm-linux-gnueabi-gcc >/dev/null 2>&1 || { echo "ERROR: arm-linux-gnueabi-gcc is missing" >&2; exit 1; }
      CROSS_DEFAULT=arm-linux-gnueabi-
    else
      CROSS_DEFAULT=""
    fi
    CLANG_TRIPLE_VALUE=""
    LLVM_VALUE=0
    LLVM_IAS_VALUE=0
    ;;

  llvm|system)
    command -v clang >/dev/null 2>&1 || { echo "ERROR: clang is missing" >&2; exit 1; }
    CROSS_DEFAULT=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    CLANG_TRIPLE_VALUE=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    LLVM_VALUE=1
    LLVM_IAS_VALUE=1
    ;;

  aosp)
    rev="${VERSION_REQUEST}"
    [[ "$rev" == auto ]] && rev="$BUILD_CONFIG_CLANG_REV"
    if [[ -z "$rev" && -n "$BUILD_CONFIG_CLANG_BIN" ]]; then
      rev="$(basename "$BUILD_CONFIG_CLANG_BIN")"
    fi
    [[ -n "$rev" ]] || { echo "ERROR: cannot detect AOSP Clang revision; set TOOLCHAIN_VERSION" >&2; exit 1; }
    ref="${AOSP_CLANG_REF:-auto}"
    if [[ "$ref" == auto ]]; then
      case "$rev" in
        clang-r416183b|clang-r416183b1*) ref=android12-release ;;
        clang-r450784e*) ref=android13-release ;;
        clang-r468909*) ref=main ;;
        *)
          case "$BUILD_CONFIG_BRANCH" in
            *4.19*) ref=android12-release ;;
            *5.10*) ref=android13-release ;;
            *) ref=android13-release ;;
          esac
          ;;
      esac
    fi
    archive_dir="$rev"
    url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${ref}/${archive_dir}.tar.gz"
    archive="$WORK_DIR/aosp-${rev}.tar.gz"
    echo "[toolchain] downloading AOSP $rev from $ref" >&2
    if ! curl -fL --retry 3 --retry-delay 2 "$url" -o "$archive"; then
      if [[ "$rev" == clang-r416183b ]]; then
        rev=clang-r416183b1
        url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${ref}/${rev}.tar.gz"
        curl -fL --retry 3 --retry-delay 2 "$url" -o "$archive"
      else
        exit 1
      fi
    fi
    rm -rf "$TC_ROOT/aosp"
    mkdir -p "$TC_ROOT/aosp"
    tar -xzf "$archive" -C "$TC_ROOT/aosp"
    BIN="$(find "$TC_ROOT/aosp" -type f -path '*/bin/clang' -print -quit)"
    [[ -n "$BIN" ]] || { echo "ERROR: AOSP clang binary not found" >&2; exit 1; }
    export PATH="$(dirname "$BIN"):$PATH"
    CROSS_DEFAULT=""
    CLANG_TRIPLE_VALUE=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    LLVM_VALUE=1
    LLVM_IAS_VALUE=1
    RESOLVED_VERSION="$rev"
    ;;

  proton)
    ver="${VERSION_REQUEST}"
    [[ "$ver" == auto ]] && ver=20210522
    url="https://github.com/kdrag0n/proton-clang/archive/refs/tags/${ver}.tar.gz"
    archive="$WORK_DIR/proton-${ver}.tar.gz"
    echo "[toolchain] downloading Proton Clang $ver" >&2
    curl -fL --retry 3 --retry-delay 2 "$url" -o "$archive"
    rm -rf "$TC_ROOT/proton"
    mkdir -p "$TC_ROOT/proton"
    tar -xzf "$archive" -C "$TC_ROOT/proton" --strip-components=1
    [[ -x "$TC_ROOT/proton/bin/clang" ]] || { echo "ERROR: Proton Clang bin/clang not found" >&2; exit 1; }
    export PATH="$TC_ROOT/proton/bin:$PATH"
    CROSS_DEFAULT=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    CLANG_TRIPLE_VALUE=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    LLVM_VALUE=1
    LLVM_IAS_VALUE=1
    RESOLVED_VERSION="$ver"
    ;;

  neutron)
    ver="${VERSION_REQUEST}"
    if [[ "$ver" == auto || "$ver" == latest ]]; then
      metadata="$WORK_DIR/neutron-release.json"
      curl -fsSL --retry 3 https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest -o "$metadata"
      readarray -t asset_info < <(python3 - "$metadata" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding='utf-8'))
assets = p.get('assets', [])
for a in assets:
    n = a.get('name', '')
    if n.startswith('neutron-clang-') and n.endswith('.tar.zst'):
        print(p.get('tag_name',''))
        print(a.get('browser_download_url',''))
        print(a.get('digest','').replace('sha256:',''))
        break
PY
)
      [[ "${#asset_info[@]}" -ge 2 && -n "${asset_info[1]}" ]] || { echo "ERROR: no Neutron release asset found" >&2; exit 1; }
      ver="${asset_info[0]}"
      url="${asset_info[1]}"
      digest="${asset_info[2]:-}"
    else
      url="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${ver}/neutron-clang-${ver}.tar.zst"
      digest=""
    fi
    archive="$WORK_DIR/neutron-${ver}.tar.zst"
    echo "[toolchain] downloading Neutron Clang $ver" >&2
    curl -fL --retry 3 --retry-delay 2 "$url" -o "$archive"
    if [[ -n "${digest:-}" ]]; then
      echo "${digest}  ${archive}" | sha256sum -c -
    fi
    rm -rf "$TC_ROOT/neutron"
    mkdir -p "$TC_ROOT/neutron"
    tar --zstd -xf "$archive" -C "$TC_ROOT/neutron"
    BIN="$(find "$TC_ROOT/neutron" -type f -path '*/bin/clang' -print -quit)"
    [[ -n "$BIN" ]] || { echo "ERROR: Neutron clang binary not found" >&2; exit 1; }
    export PATH="$(dirname "$BIN"):$PATH"
    CROSS_DEFAULT=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    CLANG_TRIPLE_VALUE=$([[ "$ARCH" == arm64 ]] && echo aarch64-linux-gnu- || [[ "$ARCH" == arm ]] && echo arm-linux-gnueabi- || echo "")
    LLVM_VALUE=1
    LLVM_IAS_VALUE=1
    RESOLVED_VERSION="$ver"
    ;;

  *)
    echo "ERROR: unsupported TOOLCHAIN=$family" >&2
    exit 1
    ;;
esac

CLANG_PATH="$(command -v clang 2>/dev/null || true)"
if [[ "$LLVM_VALUE" == 1 && -z "$CLANG_PATH" ]]; then
  echo "ERROR: selected LLVM toolchain has no clang executable" >&2
  exit 1
fi

printf 'RESOLVED_TOOLCHAIN=%q\n' "$family"
printf 'RESOLVED_TOOLCHAIN_VERSION=%q\n' "${RESOLVED_VERSION:-${ver:-${BUILD_CONFIG_CLANG_REV:-system}}}"
printf 'RESOLVED_CLANG=%q\n' "$CLANG_PATH"
printf 'RESOLVED_CLANG_TRIPLE=%q\n' "$CLANG_TRIPLE_VALUE"
printf 'RESOLVED_CROSS_DEFAULT=%q\n' "$CROSS_DEFAULT"
printf 'RESOLVED_LLVM=%q\n' "$LLVM_VALUE"
printf 'RESOLVED_LLVM_IAS=%q\n' "$LLVM_IAS_VALUE"
printf 'RESOLVED_BUILD_CONFIG_CLANG_BIN=%q\n' "$BUILD_CONFIG_CLANG_BIN"
printf 'RESOLVED_BUILD_CONFIG_BRANCH=%q\n' "$BUILD_CONFIG_BRANCH"
>&2 echo "[toolchain] family=$family version=${ver:-${BUILD_CONFIG_CLANG_REV:-system}} clang=${CLANG_PATH:-none} cross=$CROSS_DEFAULT"
