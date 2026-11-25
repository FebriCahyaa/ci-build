#!/usr/bin/env python3
"""Offline contract checks for the garnet 6.6 cross-ROM drop-in helpers."""
from __future__ import annotations

import gzip
import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

CONFIG = """# test config
CONFIG_LOCALVERSION="-BetterWorld-By-Zen-Itsu"
CONFIG_CC_VERSION_TEXT="Android (14054515, +pgo, +bolt, +lto, +mlgo, based on r563880c) clang version 21.0.0"
CONFIG_MODVERSIONS=y
"""
PAGE = 4096
HEADER_SIZE = 1584


def align(n: int) -> int:
    return (n + PAGE - 1) // PAGE * PAGE


def make_boot(config: str) -> bytes:
    kernel = (b"Linux version 6.6.144-Test+\x00" + b"IKCFG_ST" +
              gzip.compress(config.encode()) + b"IKCFG_ED")
    ramdisk = b"RAMDISK-PAYLOAD"
    vbmeta = b"AVB0" + bytes(124)

    header = bytearray(HEADER_SIZE)
    header[:8] = b"ANDROID!"
    struct.pack_into("<IIII", header, 8, len(kernel), len(ramdisk), 0, HEADER_SIZE)
    struct.pack_into("<I", header, 40, 4)

    payload_end = PAGE + align(len(kernel)) + align(len(ramdisk))
    image = bytearray(payload_end + len(vbmeta) + 64)
    image[:HEADER_SIZE] = header
    off = PAGE
    image[off:off + len(kernel)] = kernel
    off = PAGE + align(len(kernel))
    image[off:off + len(ramdisk)] = ramdisk
    image[payload_end:payload_end + len(vbmeta)] = vbmeta
    footer_off = len(image) - 64
    image[footer_off:footer_off + 4] = b"AVBf"
    struct.pack_into(">IIQQQ", image, footer_off + 4,
                     1, 0, payload_end, payload_end, len(vbmeta))
    return bytes(image)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        boot = tmpdir / "boot.img"
        boot.write_bytes(make_boot(CONFIG))

        meta_raw = subprocess.check_output([
            sys.executable, str(ROOT / "scripts/extract_rom_config.py"),
            str(boot), "--name", "test-rom", "--print",
        ], text=True)
        meta = json.loads(meta_raw)
        assert meta["kernel_release"] == "6.6.144-Test+", meta
        assert meta["localversion"] == "-BetterWorld-By-Zen-Itsu", meta
        assert meta["clang_revision"] == "clang-r563880c", meta

        frags = tmpdir / "frags"
        out = subprocess.check_output([
            sys.executable, str(ROOT / "scripts/extract_rom_config.py"),
            str(boot), "--name", "test-rom", "--fragment-dir", str(frags),
        ], text=True)
        fragment = frags / "garnet-6.6-test-rom.config"
        assert "fragment: " + str(fragment) in out, out
        assert "CONFIG_MODVERSIONS=y" in fragment.read_text()
        assert (frags / "garnet-6.6-test-rom.metadata.json").is_file()

        new_kernel = b"NEW-KERNEL-IMAGE"
        kernel_image = tmpdir / "kernel"
        kernel_image.write_bytes(new_kernel)
        repacked = tmpdir / "repacked.img"
        subprocess.check_call([
            sys.executable, str(ROOT / "scripts/repack_boot.py"),
            str(boot), str(kernel_image), str(repacked),
        ])

        data = repacked.read_bytes()
        kernel_size, ramdisk_size, _os, header_size = struct.unpack_from("<IIII", data, 8)
        assert kernel_size == len(new_kernel), kernel_size
        assert ramdisk_size == len("RAMDISK-PAYLOAD"), ramdisk_size
        assert header_size == HEADER_SIZE, header_size
        assert data[PAGE:PAGE + len(new_kernel)] == new_kernel
        ramdisk_off = PAGE + align(len(new_kernel))
        assert data[ramdisk_off:ramdisk_off + len("RAMDISK-PAYLOAD")] == b"RAMDISK-PAYLOAD"
        new_payload_end = ramdisk_off + align(len("RAMDISK-PAYLOAD"))
        footer = struct.unpack_from(">IIQQQ", data, len(data) - 60)
        assert footer[0] == 1 and footer[1] == 0, footer
        assert footer[2] == new_payload_end and footer[3] == new_payload_end, footer
        assert footer[4] == 128, footer
        assert data[new_payload_end:new_payload_end + 4] == b"AVB0"

    print("PASS garnet 6.6 drop-in helpers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
