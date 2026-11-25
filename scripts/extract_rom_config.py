#!/usr/bin/env python3
"""Extract the kernel .config and build identity from a prebuilt boot image.

Works with Android boot header v3/v4 images. The extracted config is written
as a CI config fragment together with a small metadata JSON file so a drop-in
build of another garnet 6.6 ROM can reuse the exact config and localversion.

Usage:
  scripts/extract_rom_config.py BOOT_IMG --name ROM_NAME [--fragment-dir DIR]

Example:
  scripts/extract_rom_config.py risingos-261120-boot.img --name risingos-9-261120
"""
from __future__ import annotations

import argparse
import gzip
import json
import re
import struct
from pathlib import Path

PAGE = 4096
ROOT = Path(__file__).resolve().parent.parent


def align(n: int) -> int:
    return (n + PAGE - 1) // PAGE * PAGE


def parse_boot(data: bytes) -> bytes:
    if data[:8] != b"ANDROID!":
        raise ValueError("not an Android boot image")
    kernel_size, ramdisk_size, _os, header_size = struct.unpack_from("<IIII", data, 8)
    header_version, = struct.unpack_from("<I", data, 40)
    if header_version not in (3, 4):
        raise ValueError(f"unsupported boot header version: {header_version}")
    return data[PAGE:PAGE + kernel_size]


def embedded_config(kernel: bytes) -> str:
    start = kernel.find(b"IKCFG_ST")
    if start < 0:
        raise ValueError("kernel has no embedded IKCFG config")
    end = kernel.find(b"IKCFG_ED", start + 8)
    if end < 0:
        raise ValueError("truncated IKCFG config")
    return gzip.decompress(kernel[start + 8:end]).decode("utf-8", errors="replace")


def kernel_release(kernel: bytes) -> str:
    match = re.search(rb"Linux version ([A-Za-z0-9._+-]+)", kernel)
    return match.group(1).decode("ascii", errors="replace") if match else ""


def config_value(config: str, key: str) -> str:
    prefix = key + "="
    for line in config.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].strip().strip('"')
    return ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("boot_img", type=Path)
    ap.add_argument("--name", required=True, help="ROM preset name, e.g. risingos-9-261120")
    ap.add_argument("--fragment-dir", type=Path, default=ROOT / "profiles" / "fragments")
    ap.add_argument("--print", action="store_true", help="print metadata JSON only")
    args = ap.parse_args()

    name = re.sub(r"[^A-Za-z0-9._-]+", "-", args.name).strip("-")
    if not name or name in (".", ".."):
        raise ValueError(f"invalid ROM preset name: {args.name!r}")
    kernel = parse_boot(args.boot_img.read_bytes())
    config = embedded_config(kernel)
    release = kernel_release(kernel)
    cc_text = config_value(config, "CONFIG_CC_VERSION_TEXT")
    clang = re.search(r"based on r([0-9a-zA-Z]+)", cc_text)
    metadata = {
        "name": name,
        "source_boot_image": str(args.boot_img),
        "kernel_release": release,
        "localversion": config_value(config, "CONFIG_LOCALVERSION"),
        "localversion_auto": config_value(config, "CONFIG_LOCALVERSION_AUTO"),
        "clang_revision": "clang-r" + clang.group(1) if clang else "",
        "compiler": cc_text,
        "config_lines": len(config.splitlines()),
    }
    if args.print:
        print(json.dumps(metadata, indent=2))
        return 0

    args.fragment_dir.mkdir(parents=True, exist_ok=True)
    fragment = args.fragment_dir / f"garnet-6.6-{name}.config"
    header = (
        f"# Kernel .config extracted from {name} boot image.\n"
        f"# kernel release: {release}\n"
        f"# clang revision: {metadata['clang_revision']}\n"
        "# Use only with the matching kernel source/ref. Any config or ABI change\n"
        "# requires the matching vendor modules to be rebuilt as well.\n"
    )
    fragment.write_text(header + config)
    meta_path = fragment.with_suffix(".metadata.json")
    meta_path.write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))
    print(f"fragment: {fragment}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
