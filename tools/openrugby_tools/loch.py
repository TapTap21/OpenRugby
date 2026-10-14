"""Parser for Rugby 08 LOCH locale string tables (``.loc``).

Format (observed on all 6 shipped files):

    LOCH  u32 size(=20) u32 version(=1) u32 ?(=1) u32 offset_of_LOCL
    LOCI  u32 size      u32 count       u32 ?(=0)  count * (u16 id, u16 index)
    LOCL  u32 size      u32 ?(=0)       u32 count  count * u32 offset(from LOCL start)
          UTF-16LE strings, each NUL-terminated (offsets index into them)

``LOCI`` maps string ids to indices into the ``LOCL`` offset table.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path


class LochError(ValueError):
    pass


def parse_strtab(data: bytes, encoding: str = "cp1252") -> dict:
    """Parse a compiled HBS string table (``*.english`` / ``*.french``, hbsstringcompiler output).

    Header: u32 entry_count, u32 payload_bytes (= file size - 12), u32 max_id; then
    entry_count * (u16 id, NUL-terminated cp1252 string). Ids are sparse (0..max_id).
    """
    if len(data) < 12:
        raise LochError("too short")
    count, payload, max_id = struct.unpack_from("<3I", data, 0)
    if payload != len(data) - 12:
        raise LochError("payload size mismatch")
    pos, out = 12, {}
    for _ in range(count):
        if pos + 3 > len(data):
            raise LochError("truncated string table")
        sid = struct.unpack_from("<H", data, pos)[0]
        end = data.index(b"\0", pos + 2)
        out[str(sid)] = data[pos + 2 : end].decode(encoding, "replace")
        pos = end + 1
    return {"count": count, "max_id": max_id, "ids": out}


def build_strtab(entries: dict[int, str], encoding: str = "cp1252") -> bytes:
    body = b"".join(struct.pack("<H", k) + v.encode(encoding) + b"\0" for k, v in entries.items())
    return struct.pack("<3I", len(entries), len(body), max(entries, default=0)) + body


def parse_any(data: bytes) -> dict:
    return parse_loch(data) if data[:4] == b"LOCH" else parse_strtab(data)


def parse_loch(data: bytes) -> dict:
    if data[:4] != b"LOCH":
        raise LochError("missing LOCH magic")
    hdr_size, version, unk, locl_off = struct.unpack_from("<4I", data, 4)
    pos = hdr_size
    if data[pos : pos + 4] != b"LOCI":
        raise LochError("missing LOCI chunk")
    _isize, count, loci_unk = struct.unpack_from("<3I", data, pos + 4)
    pairs = [struct.unpack_from("<HH", data, pos + 16 + 4 * i) for i in range(count)]
    if data[locl_off : locl_off + 4] != b"LOCL":
        raise LochError("missing LOCL chunk")
    _lsize, lunk, lcount = struct.unpack_from("<3I", data, locl_off + 4)
    offs = struct.unpack_from(f"<{lcount}I", data, locl_off + 16)
    strings = []
    for o in offs:
        p = locl_off + o
        e = p
        while e + 2 <= len(data) and data[e : e + 2] != b"\0\0":
            e += 2
        strings.append(data[p:e].decode("utf-16-le", "replace"))
    entries = {}
    for sid, idx in pairs:
        if idx >= len(strings):
            raise LochError(f"string index {idx} out of range")
        entries[sid] = strings[idx]
    return {
        "version": version,
        "header_unknowns": [unk, loci_unk, lunk],
        "count": len(strings),
        "strings": strings,
        "ids": {str(k): v for k, v in entries.items()},
    }


def build_loch(strings: list[str], ids: list[tuple[int, int]] | None = None) -> bytes:
    """Build a LOCH blob (used by tests)."""
    ids = ids if ids is not None else [(i + 1, i) for i in range(len(strings))]
    loci = b"LOCI" + struct.pack("<3I", 16 + 4 * len(ids), len(ids), 0)
    loci += b"".join(struct.pack("<HH", a, b) for a, b in ids)
    blobs = [s.encode("utf-16-le") + b"\0\0\0\0" for s in strings]
    base = 16 + 4 * len(strings)
    offs, cur = [], base
    for b in blobs:
        offs.append(cur)
        cur += len(b)
    locl = b"LOCL" + struct.pack("<3I", cur, 0, len(strings))
    locl += struct.pack(f"<{len(offs)}I", *offs) + b"".join(blobs)
    head = b"LOCH" + struct.pack("<4I", 20, 1, 1, 20 + len(loci))
    return head + loci + locl


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m openrugby_tools.loch", description="LOCH string table to JSON"
    )
    ap.add_argument("input", type=Path)
    ap.add_argument("-o", "--output", type=Path)
    a = ap.parse_args(argv)
    out = json.dumps(parse_any(a.input.read_bytes()), ensure_ascii=False, indent=1)
    if a.output:
        a.output.write_text(out, encoding="utf-8")
    else:
        sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
