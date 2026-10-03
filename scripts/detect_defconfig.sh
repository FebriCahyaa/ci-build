#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: detect_defconfig.sh --repo DIR [--arch auto|arm64|arm|x86|...] [--device NAME]
                           [--defconfig auto|TARGET] [--fragment auto|PATH|none]
USAGE
  exit 2
}

REPO=""
ARCH_REQ="auto"
DEVICE="generic"
DEFCONFIG_REQ="auto"
FRAGMENT_REQ="auto"

while (($#)); do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --arch) ARCH_REQ="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --defconfig) DEFCONFIG_REQ="$2"; shift 2 ;;
    --fragment) FRAGMENT_REQ="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -d "$REPO" ]] || { echo "ERROR: kernel repo is required" >&2; exit 1; }
cd "$REPO"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

KVER_MAJOR=0
KVER_MINOR=0
if [[ -f Makefile ]]; then
  KVER_MAJOR="$(awk '/^VERSION[[:space:]]*=/{print $3; exit}' Makefile)"
  KVER_MINOR="$(awk '/^PATCHLEVEL[[:space:]]*=/{print $3; exit}' Makefile)"
fi

if [[ "$ARCH_REQ" == "auto" ]]; then
  if [[ -f arch/arm64/Makefile ]]; then
    ARCH=arm64
  elif [[ -f arch/arm/Makefile ]]; then
    ARCH=arm
  elif [[ -f arch/x86/Makefile ]]; then
    ARCH=x86
  elif [[ -f arch/riscv/Makefile ]]; then
    ARCH=riscv
  else
    echo "ERROR: unable to detect architecture; specify ARCH explicitly" >&2
    exit 1
  fi
else
  ARCH="$ARCH_REQ"
fi

CONFIG_ROOT="arch/$ARCH/configs"
[[ -d "$CONFIG_ROOT" ]] || { echo "ERROR: $CONFIG_ROOT does not exist" >&2; exit 1; }

declare -a ALIASES
D="$(lower "$DEVICE")"
ALIASES=("$D")
case "$D" in
  lavender|xiaomi-lavender)
    ALIASES+=(lavender sdm660 xiaomi lavender-sdm660)
    ;;
  garnet|xiaomi-garnet)
    ALIASES+=(garnet sm7435 parrot xiaomi-garnet)
    ;;
  moonstone|poco-moonstone)
    ALIASES+=(moonstone sm6375 garnet)
    ;;
esac

# Discover device fragments first. They provide strong evidence for the base config.
FRAGMENT=""
if [[ "$FRAGMENT_REQ" != "none" ]]; then
  if [[ "$FRAGMENT_REQ" == "auto" && "$D" == "lavender" && -f "$CONFIG_ROOT/vendor/xiaomi/lavender.config" ]]; then
    FRAGMENT="$CONFIG_ROOT/vendor/xiaomi/lavender.config"
  elif [[ "$FRAGMENT_REQ" != "auto" ]]; then
    if [[ -f "$CONFIG_ROOT/$FRAGMENT_REQ" ]]; then
      FRAGMENT="$CONFIG_ROOT/$FRAGMENT_REQ"
    elif [[ -f "$FRAGMENT_REQ" ]]; then
      FRAGMENT="$FRAGMENT_REQ"
    else
      echo "ERROR: CONFIG_FRAGMENT not found: $FRAGMENT_REQ" >&2
      exit 1
    fi
  else
    while IFS= read -r f; do
      base="$(basename "$f")"
      name="${base%.config}"
      lname="$(lower "$name")"
      for alias in "${ALIASES[@]}"; do
        if [[ "$lname" == "$(lower "$alias")" ]]; then
          FRAGMENT="$f"
          break 2
        fi
      done
    done < <(find "$CONFIG_ROOT" -type f \( -name '*.config' -o -name '*.fragment' \) | sort)
  fi
fi

if [[ "$DEFCONFIG_REQ" != "auto" ]]; then
  if [[ -f "$CONFIG_ROOT/$DEFCONFIG_REQ" ]]; then
    DEFCONFIG="$DEFCONFIG_REQ"
  elif [[ -f "$CONFIG_ROOT/${DEFCONFIG_REQ}.config" ]]; then
    DEFCONFIG="${DEFCONFIG_REQ}.config"
  else
    echo "ERROR: DEFCONFIG not found under $CONFIG_ROOT: $DEFCONFIG_REQ" >&2
    exit 1
  fi
else
  # Source-backed explicit base-config mappings for trees where the device
  # fragment is intentionally separate from the SoC/base defconfig.
  PREFERRED_DEFCONFIG=""
  case "$D" in
    lavender)
      [[ -f "$CONFIG_ROOT/vendor/xiaomi/sdm660_defconfig" ]] && \
        PREFERRED_DEFCONFIG="vendor/xiaomi/sdm660_defconfig"
      ;;
  esac
  if [[ -n "$PREFERRED_DEFCONFIG" ]]; then
    DEFCONFIG="$PREFERRED_DEFCONFIG"
  else
  declare -a candidates=()
  while IFS= read -r f; do candidates+=("$f"); done < <(find "$CONFIG_ROOT" -type f -name '*defconfig' | sort)
  ((${#candidates[@]})) || { echo "ERROR: no *defconfig files found under $CONFIG_ROOT" >&2; exit 1; }

  # Candidate ranking deliberately uses only source evidence. A close/ambiguous match is fatal.
  declare -a ranked=()
  for f in "${candidates[@]}"; do
    base="$(basename "$f")"
    rel="${f#"$CONFIG_ROOT/"}"
    lbase="$(lower "$base")"
    lrel="$(lower "$rel")"
    score=0

    for alias in "${ALIASES[@]}"; do
      a="$(lower "$alias")"
      [[ "$lbase" == "$a"* ]] && score=$((score+120))
      [[ "$lbase" == *"$a"* ]] && score=$((score+35))
      [[ "$lrel" == *"/$a/"* ]] && score=$((score+45))
      [[ "$lrel" == *"$a"* ]] && score=$((score+15))
      if grep -qiE "(^|[^[:alnum:]])${a}([^[:alnum:]]|$)" "$f" 2>/dev/null; then
        score=$((score+30))
      fi
    done

    if [[ "$D" == lavender ]]; then
      grep -q 'CONFIG_ARCH_SDM660=y' "$f" 2>/dev/null && score=$((score+70)) || true
      grep -q 'CONFIG_MACH_XIAOMI_LAVENDER=y' "$f" 2>/dev/null && score=$((score+100)) || true
      [[ "$rel" == vendor/xiaomi/* ]] && score=$((score+35))
      [[ -n "$FRAGMENT" && "$FRAGMENT" == *"/xiaomi/lavender.config" ]] && [[ "$rel" == vendor/xiaomi/* ]] && score=$((score+55))
    fi

    if [[ "$D" == garnet ]]; then
      grep -qiE 'CONFIG_ARCH_(SM7435|PARROT)=y' "$f" 2>/dev/null && score=$((score+70)) || true
      grep -qiE 'CONFIG_MACH_.*GARNET|CONFIG_MACH_.*PARROT' "$f" 2>/dev/null && score=$((score+100)) || true
    fi

    # Exact generic defconfig is a weak fallback, never a strong device match.
    [[ "$base" == defconfig ]] && score=$((score+5))

    ranked+=("$score|$rel")
  done

  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\n' "${ranked[@]}" | sort -t'|' -k1,1nr -k2,2 | tr '\n' '\0') || true
  best="${sorted[0]:-}"
  second="${sorted[1]:-}"
  best_score="${best%%|*}"
  best_rel="${best#*|}"
  second_score="${second%%|*}"

  if [[ -z "$best" || "$best_score" -le 5 ]]; then
    echo "ERROR: automatic defconfig detection found no device-specific candidate" >&2
    printf 'Candidates:\n%s\n' "$(printf '%s\n' "${ranked[@]}" | sort -t'|' -k1,1nr | head -n 15 | sed 's/|/ score=/' )" >&2
    exit 1
  fi

  if [[ -n "$second" && "$best_score" == "$second_score" ]]; then
    echo "ERROR: automatic defconfig detection is ambiguous" >&2
    printf '%s\n' "$(printf '%s\n' "${ranked[@]}" | sort -t'|' -k1,1nr -k2,2 | head -n 15 | sed 's/|/ score=/')" >&2
    echo "Set DEFCONFIG explicitly." >&2
    exit 1
  fi

  DEFCONFIG="$best_rel"
  fi
fi

# Emit only shell-safe assignments on stdout; diagnostics go to stderr.
printf 'DETECTED_ARCH=%q\n' "$ARCH"
printf 'DETECTED_KERNEL_VERSION=%q\n' "${KVER_MAJOR}.${KVER_MINOR}"
printf 'DETECTED_DEFCONFIG=%q\n' "$DEFCONFIG"
if [[ -n "$FRAGMENT" ]]; then
  relfrag="${FRAGMENT#"$CONFIG_ROOT/"}"
  printf 'DETECTED_FRAGMENT=%q\n' "$relfrag"
else
  printf 'DETECTED_FRAGMENT=%q\n' ""
fi

>&2 echo "[detect] kernel=${KVER_MAJOR}.${KVER_MINOR} arch=$ARCH defconfig=$DEFCONFIG fragment=${relfrag:-none}"
