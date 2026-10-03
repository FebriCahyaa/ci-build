#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_PROVIDER="${1:-${KSU_PROVIDER:-none}}"
case "${ROOT_PROVIDER,,}" in
  ""|none|false|0|disabled)
    echo "none" ;;
  official|kernelsu|kernel-su)
    echo "kernelsu" ;;
  kernelsu-next|ksu-next|next)
    echo "kernelsu-next" ;;
  resukisu|re-sukisu)
    echo "resukisu" ;;
  *)
    echo "none" ;;
esac
