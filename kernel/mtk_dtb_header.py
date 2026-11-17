#!/usr/bin/env python3
"""Wrap a plain FDT in the 64-byte MTK LK header the bootloader expects."""
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
fdt = path.read_bytes()
if fdt[:4] != b"\xd0\x0d\xfe\xed":
    raise SystemExit("input is not a plain FDT (bad d00dfeed magic)")

header = b"\xd7\xb7\xab\x1e"
header += struct.pack(">IIIIIII", len(fdt) + 64, 0x20, 0x20, 1, 0x20, 0x800, 0)
header += struct.pack(">II", len(fdt), 64)
header += b"\x00" * 24
assert len(header) == 64
path.write_bytes(header + fdt)
