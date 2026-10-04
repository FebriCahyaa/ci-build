#!/usr/bin/env bash
set -Eeuo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP/harness-inputs.yaml" <<'PY'
import json
import sys
from pathlib import Path

names = [
    "CI_BUILD_SHA", "BUILD_PROFILE", "ROOT_VARIANTS",
    "KERNEL_REPO_OVERRIDE", "KERNEL_REF_OVERRIDE",
    "DEFCONFIG_OVERRIDE", "CONFIG_FRAGMENT_OVERRIDE",
    "JOBS", "TOOLCHAIN", "TOOLCHAIN_VERSION", "LLVM_IAS",
    "CLANG_URL", "GCC_URL", "EXTRA_MAKE_ARGS",
    "PATCH_PROFILE", "UPSTREAM_PROFILE", "LTO_PLUS", "KSU_REF",
    "PACKAGE_ANYKERNEL", "ROM_FAMILY", "ANYKERNEL_PROFILE",
    "ANYKERNEL3_REF", "BUILD_CUSTOMIZATION", "PUBLISH_RELEASE", "TG_TOPIC_ID",
]
values = {name: "" for name in names}
values.update({
    "CI_BUILD_SHA": "0123456789abcdef0123456789abcdef01234567",
    "BUILD_PROFILE": "lavender-4.19",
    "ROOT_VARIANTS": "kernelsu-next",
    "JOBS": "0",
    "TOOLCHAIN": "auto",
    "TOOLCHAIN_VERSION": "auto",
    "LLVM_IAS": "auto",
    "PATCH_PROFILE": "auto",
    "UPSTREAM_PROFILE": "auto",
    "LTO_PLUS": "false",
    "KSU_REF": "auto",
    "PACKAGE_ANYKERNEL": "true",
    "ROM_FAMILY": "auto",
    "ANYKERNEL_PROFILE": "auto",
    "ANYKERNEL3_REF": "master",
    "PUBLISH_RELEASE": "false",
    "TG_TOPIC_ID": "13",
})
values["BUILD_CUSTOMIZATION"] = json.dumps({"kernel_name": "", "apt_packages": ""}, separators=(",", ":"))
lines = ["pipeline:", "  identifier: Universal_Kernel_Build", "  variables:"]
for name in names:
    lines.extend([
        f"    - name: {name}",
        "      type: String",
        "      value: " + json.dumps(values[name], ensure_ascii=False),
    ])
Path(sys.argv[1]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

ruby -ryaml -e 'd=YAML.load_file(ARGV[0]); abort "missing pipeline.identifier" unless d.dig("pipeline","identifier")=="Universal_Kernel_Build"; vars=d.dig("pipeline","variables"); abort "variables not list" unless vars.is_a?(Array); names=vars.map{|x| x["name"]}; abort "wrong variable count #{names.size}" unless names.size==25; abort "duplicate variable" unless names.uniq.size==names.size; puts "PASS: Harness Runtime Input YAML shape, identifier, and 25-variable contract"' "$TMP/harness-inputs.yaml"
