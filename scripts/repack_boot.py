#!/usr/bin/env python3
"""Replace only the kernel Image in an Android boot header v3/v4 image.

The generic ramdisk, cmdline, dtb/vendor vbmeta block and AVB footer are
preserved byte-for-byte. Only kernel_size, the kernel payload and the footer's
original_image_size / vbmeta_offset are updated, so no ROM partition other
than boot is touched.

Usage:
  scripts/repack_boot.py STOCK_BOOT_IMG KERNEL_IMAGE [OUTPUT_IMG]
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

PAGE = 4096


def align(n: int) -> int:
    return (n + PAGE - 1) // PAGE * PAGE


def repack(stock: bytes, kernel: bytes) -> bytes:
    if stock[:8] != b"ANDROID!":
        raise ValueError("not an Android boot image")
    kernel_size, ramdisk_size, _os_version, header_size = struct.unpack_from("<IIII", stock, 8)
    if header_size < 1584:
        raise ValueError(f"unexpected boot header size: {header_size}")
    header_version, = struct.unpack_from("<I", stock, 40)
    if header_version not in (3, 4):
        raise ValueError(f"unsupported boot header version: {header_version}")

    kernel_off = PAGE
    ramdisk_off = kernel_off + align(kernel_size)
    payload_end = ramdisk_off + align(ramdisk_size)
    if payload_end > len(stock):
        raise ValueError("boot image is truncated")
    ramdisk = stock[ramdisk_off:ramdisk_off + ramdisk_size]
    if len(ramdisk) != ramdisk_size:
        raise ValueError("ramdisk payload is truncated")

    trailer = b""
    footer = b""
    footer_off = len(stock) - 64
    if stock[footer_off:footer_off + 4] == b"AVBf":
        # AVB footer integers are big-endian on garnet boot images.
        _maj, _min, orig_size, vbmeta_off, vbmeta_size = struct.unpack_from(">IIQQQ", stock, footer_off + 4)
        if orig_size != payload_end or vbmeta_off != payload_end:
            raise ValueError("AVB footer does not describe the boot payload")
        if vbmeta_off + vbmeta_size > footer_off:
            raise ValueError("vbmeta block overlaps the AVB footer")
        trailer = stock[vbmeta_off:vbmeta_off + vbmeta_size]
        footer = bytes(stock[footer_off:])

    new_ramdisk_off = kernel_off + align(len(kernel))
    new_payload_end = new_ramdisk_off + align(len(ramdisk))
    total = max(len(stock), new_payload_end + len(trailer) + (64 if footer else 0))
    new_footer_off = total - 64 if footer else 0

    header = bytearray(stock[:header_size])
    struct.pack_into("<I", header, 8, len(kernel))

    image = bytearray(total)
    image[:header_size] = header
    image[kernel_off:kernel_off + len(kernel)] = kernel
    image[new_ramdisk_off:new_ramdisk_off + len(ramdisk)] = ramdisk
    if footer:
        image[new_payload_end:new_payload_end + len(trailer)] = trailer
        new_footer = bytearray(footer)
        struct.pack_into(">QQ", new_footer, 12, new_payload_end, new_payload_end)
        image[new_footer_off:] = new_footer
    return bytes(image)


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    stock = Path(sys.argv[1]).read_bytes()
    kernel = Path(sys.argv[2]).read_bytes()
    out = Path(sys.argv[3]) if len(sys.argv) == 4 else Path(sys.argv[1]).with_suffix(".repacked.img")
    out.write_bytes(repack(stock, kernel))
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
