#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$ROOT/.github/workflows/harness-kernel.yml"
PIPE="$ROOT/harness/kernel-pipeline.yaml"
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

python3 - "$TMP/harness-inputs.yaml" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
lines=p.read_text(encoding='utf-8').splitlines()
assert lines[:3] == ['pipeline:', '  identifier: Universal_Kernel_Build', '  variables:']
names=[]
for i,line in enumerate(lines):
    if line.startswith('    - name: '):
        names.append(line.split(': ',1)[1])
        assert lines[i+1] == '      type: String'
        assert lines[i+2].startswith('      value: ')
assert len(names) == 25, len(names)
assert len(names) == len(set(names))
print('PASS Harness Runtime Input YAML shape: identifier + 25 variables')
PY

grep -q 'lines = \["pipeline:", "  identifier: Universal_Kernel_Build", "  variables:"\]' "$WF"
grep -q '^  variables:$' "$PIPE"
[[ "$(grep -c 'TG_RELEASE_TOPIC_ID:' "$PIPE")" -eq 0 ]]

echo 'PASS Harness runtime trigger regression contract'
