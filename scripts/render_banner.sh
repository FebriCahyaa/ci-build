#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="$("$ROOT_DIR/scripts/select_banner_variant.sh" "${ROOT_PROVIDER:-none}")"
TEMPLATE="$ROOT_DIR/anykernel/banners/${VARIANT}.txt"
OUT="${1:-banner}"

[[ -f "$TEMPLATE" ]] || {
  echo "ERROR: missing banner template: $TEMPLATE" >&2
  exit 1
}

export TEMPLATE OUT
python3 - <<'PY'
import os
from pathlib import Path

text=Path(os.environ["TEMPLATE"]).read_text(encoding="utf-8")
values={
    "ASCII": os.environ.get("ASCII_LOGO",""),
    "BUILD_LABEL": os.environ.get("BUILD_LABEL","Zairenkai-VEGA1"),
    "KERNEL_RELEASE": os.environ.get("KERNEL_RELEASE","unknown"),
    "TOOLCHAIN": os.environ.get("TOOLCHAIN","unknown"),
    "BUILD_USER": os.environ.get("KBUILD_BUILD_USER","FebriCahyaa"),
    "BUILD_HOST": os.environ.get("KBUILD_BUILD_HOST","ZairenkaiProject"),
    "PROFILE": os.environ.get("BANNER_PROFILE",""),
}
for key,value in values.items():
    text=text.replace("@"+key+"@",value)
Path(os.environ["OUT"]).write_text(text.rstrip()+"\n",encoding="utf-8")
PY
