#!/usr/bin/env python3
"""Workflow / Harness contract checks (offline).

* workflow_dispatch inputs stay within GitHub's 25-input limit
* the GitHub -> Harness bridge sends exactly the variables the Harness
  pipeline declares, all as runtime inputs
* every `run:` block (GitHub) and the Harness `command:` parse with `bash -n`
* scripts are invoked through `bash`, so lost executable bits cannot break CI
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = sorted((ROOT / ".github" / "workflows").glob("*.yml"))
KERNEL_PIPELINE = ROOT / "harness" / "kernel-pipeline.yaml"
ROM_PIPELINE = ROOT / "harness" / "rom-pipeline.yaml"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def on_block(data: dict) -> dict:
    # PyYAML parses the bare key `on:` as boolean True.
    return (data.get("on") if "on" in data else data.get(True)) or {}


def bash_syntax(label: str, script: str) -> None:
    normalized = re.sub(r"\$\{\{.*?\}\}", "dummy", script)        # GitHub expressions
    normalized = re.sub(r"<\+[^>]*>", "dummy", normalized)          # Harness expressions
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False, encoding="utf-8") as fh:
        fh.write(normalized)
        path = fh.name
    try:
        proc = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
    finally:
        Path(path).unlink()
    if proc.returncode != 0:
        fail(f"{label}: {proc.stderr.strip()}")


def walk_runs(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == "run" and isinstance(value, str):
                yield value
            yield from walk_runs(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk_runs(item)


# 1. Input limits + run-block syntax + direct script execution.
for wf in WORKFLOWS:
    data = yaml.safe_load(wf.read_text(encoding="utf-8"))
    inputs = (on_block(data).get("workflow_dispatch") or {}).get("inputs") or {}
    if len(inputs) > 25:
        fail(f"{wf.name}: {len(inputs)} workflow_dispatch inputs exceed GitHub's limit of 25")
    runs = list(walk_runs(data))
    for index, run in enumerate(runs, 1):
        bash_syntax(f"{wf.name} run block {index}", run)
        for line in run.splitlines():
            if re.match(r"^\s*\./scripts/\S+\.sh", line):
                fail(f"{wf.name}: invoke scripts via `bash scripts/...`, not `{line.strip()}`")
    print(f"PASS {wf.name}: {len(inputs)} inputs, {len(runs)} run blocks")

# 2. Harness pipelines: command syntax.
for pipeline in (KERNEL_PIPELINE, ROM_PIPELINE):
    data = yaml.safe_load(pipeline.read_text(encoding="utf-8"))
    for stage in data["pipeline"]["stages"]:
        for step in stage["stage"]["spec"]["execution"]["steps"]:
            spec = step["step"].get("spec", {})
            if "command" in spec:
                bash_syntax(f"{pipeline.name}:{step['step']['identifier']}", spec["command"])
    print(f"PASS {pipeline.name}: command blocks parse")

# 3. GitHub -> Harness runtime input bridge.
pipeline = yaml.safe_load(KERNEL_PIPELINE.read_text(encoding="utf-8"))
variables = pipeline["pipeline"]["variables"]
declared = [v["name"] for v in variables]
if len(declared) != len(set(declared)):
    fail("harness/kernel-pipeline.yaml declares duplicate variables")
if len(declared) > 25:
    fail(f"harness/kernel-pipeline.yaml declares {len(declared)} variables (> 25)")
for var in variables:
    if var.get("type") != "String" or str(var.get("value")).strip() != "<+input>":
        fail(f"Harness variable {var['name']} must be a String runtime input")

bridge = (ROOT / ".github" / "workflows" / "harness-kernel.yml").read_text(encoding="utf-8")
blocks = re.findall(r"names = \[(.*?)\n\s*\]", bridge, re.S)
if not blocks:
    fail("harness-kernel.yml: runtime-input names block missing")
for block in blocks:
    sent = re.findall(r'"([A-Z][A-Z0-9_]+)"', block)
    if sorted(sent) != sorted(declared):
        fail(f"bridge/pipeline variable mismatch: only-bridge={set(sent) - set(declared)} "
             f"only-pipeline={set(declared) - set(sent)}")
for needle in ('"kernel_name":', '"apt_packages":', "  identifier: Universal_Kernel_Build"):
    if needle not in bridge:
        fail(f"harness-kernel.yml is missing {needle!r}")
if "TG_RELEASE_TOPIC_ID" in KERNEL_PIPELINE.read_text(encoding="utf-8"):
    fail("the Harness build step must not receive TG_RELEASE_TOPIC_ID")

# 3b. Zairenkai token wiring stays outside the 25 runtime-input contract.
harness_pipeline_text = KERNEL_PIPELINE.read_text(encoding="utf-8")
kernel_workflow_text = (ROOT / ".github" / "workflows" / "kernel.yml").read_text(encoding="utf-8")
for needle in (
    'ZAIRENKAI_LICENSE_INC: <+secrets.getValue("zairenkai_license_inc")>',
    'license_file=/tmp/zairenkai-zkfc-license.inc',
    'ZAIRENKAI_LICENSE_INC_FILE: /tmp/zairenkai-zkfc-license.inc',
    'name: Cleanup Zairenkai license',
):
    if needle not in harness_pipeline_text:
        fail(f"Harness Zairenkai wiring missing {needle!r}")
for needle in (
    "ZAIRENKAI_LICENSE_INC: ${{ secrets.ZAIRENKAI_LICENSE_INC }}",
    'license_file="$RUNNER_TEMP/zkfc_license.inc"',
    'ZAIRENKAI_LICENSE_INC_FILE=$license_file',
    'name: Remove temporary Zairenkai license',
):
    if needle not in kernel_workflow_text:
        fail(f"GitHub Zairenkai wiring missing {needle!r}")
if "ZAIRENKAI_LICENSE_INC" in "\n".join(re.findall(r'"([A-Z][A-Z0-9_]+)"', blocks[0])):
    fail("Zairenkai license must not be a Harness runtime input")
build_kernel_text = (ROOT / "scripts" / "build_kernel.sh").read_text(encoding="utf-8")
if 'rm -f "${ZAIRENKAI_LICENSE_INC_FILE:-}"' in build_kernel_text:
    fail("build_kernel.sh must not delete the shared Harness Zairenkai license input")
for needle in (
    'rm -f /tmp/zairenkai-zkfc-license.inc',
    "Zairenkai license",
):
    if needle not in harness_pipeline_text:
        fail(f"Harness Zairenkai cleanup is missing {needle!r}")
print(f"PASS Harness bridge: {len(declared)} runtime inputs match the pipeline")

# 4. scripts/start_local_ci.sh sends exactly the workflow_dispatch inputs.
local_ci = (ROOT / "scripts" / "start_local_ci.sh").read_text(encoding="utf-8")
for wf_name, func in (("kernel.yml", "run_github"), ("harness-kernel.yml", "run_harness")):
    body = local_ci.split(f"{func}() {{", 1)[1].split("\n}", 1)[0]
    sent = set(re.findall(r"-f ([a-z0-9_]+)=", body))
    data = yaml.safe_load((ROOT / ".github" / "workflows" / wf_name).read_text(encoding="utf-8"))
    inputs = set(((on_block(data).get("workflow_dispatch") or {}).get("inputs") or {}).keys())
    if sent != inputs:
        fail(f"start_local_ci.sh {func}: missing={sorted(inputs - sent)} unknown={sorted(sent - inputs)}")
print("PASS start_local_ci.sh matches both workflow input sets")
