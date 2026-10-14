"""EA RefPack (QFS) decompression.

Header: two flag bytes ``<flags> 0xFB`` (``0x10FB``, ``0x11FB``, ``0x90FB``,
``0x91FB``) followed by big-endian sizes. Flag bit 0x80 selects 4-byte size
fields (otherwise 3-byte); bit 0x01 means a compressed-size field precedes the
uncompressed size. The reversed ``0xFB <flags>`` spelling is accepted as a
little-endian-size variant.
"""

from __future__ import annotations

from dataclasses import dataclass


class RefPackError(ValueError):
    """Raised when data is not valid RefPack."""


@dataclass(frozen=True)
class RefPackHeader:
    header_size: int
    compressed_size: int | None
    uncompressed_size: int
    little_endian: bool


def parse_header(data: bytes) -> RefPackHeader | None:
    """Parse a RefPack header from the start of ``data``; None if absent/implausible."""
    if len(data) < 5:
        return None
    if data[1] == 0xFB and data[0] in (0x10, 0x11, 0x90, 0x91):
        flags, le = data[0], False
    elif data[0] == 0xFB and data[1] in (0x10, 0x11, 0x90, 0x91):
        flags, le = data[1], True
    else:
        return None
    width = 4 if flags & 0x80 else 3
    has_comp = bool(flags & 0x01)
    need = 2 + width * (2 if has_comp else 1)
    if len(data) < need:
        return None
    order = "little" if le else "big"
    pos = 2
    comp: int | None = None
    if has_comp:
        comp = int.from_bytes(data[pos : pos + width], order)
        pos += width
    size = int.from_bytes(data[pos : pos + width], order)
    pos += width
    if size == 0:
        return None
    return RefPackHeader(pos, comp, size, le)


def is_refpack(data: bytes) -> bool:
    """True when ``data`` begins with a plausible RefPack header."""
    return parse_header(data) is not None


def decompress(data: bytes) -> bytes:
    """Decompress a RefPack stream (header included)."""
    hdr = parse_header(data)
    if hdr is None:
        raise RefPackError("missing RefPack header")
    out = bytearray()
    n = len(data)
    i = hdr.header_size
    target = hdr.uncompressed_size
    try:
        while i < n and len(out) < target + 4:
            cc = data[i]
            i += 1
            if cc < 0x80:
                b1 = data[i]
                i += 1
                lit = cc & 3
                ln = ((cc & 0x1C) >> 2) + 3
                off = ((cc & 0x60) << 3) + b1 + 1
            elif cc < 0xC0:
                b1, b2 = data[i], data[i + 1]
                i += 2
                lit = b1 >> 6
                ln = (cc & 0x3F) + 4
                off = ((b1 & 0x3F) << 8) + b2 + 1
            elif cc < 0xE0:
                b1, b2, b3 = data[i], data[i + 1], data[i + 2]
                i += 3
                lit = cc & 3
                ln = ((cc & 0x0C) << 6) + b3 + 5
                off = ((cc & 0x10) << 12) + (b1 << 8) + b2 + 1
            elif cc < 0xFC:
                lit = ((cc & 0x1F) << 2) + 4
                ln = 0
                off = 0
            else:
                lit = cc & 3
                ln = 0
                off = 0
                out += data[i : i + lit]
                i += lit
                break
            if lit:
                if i + lit > n:
                    raise RefPackError("literal run past end of input")
                out += data[i : i + lit]
                i += lit
            if ln:
                start = len(out) - off
                if start < 0:
                    raise RefPackError("back-reference before start of output")
                if off >= ln:
                    out += out[start : start + ln]
                else:
                    for _ in range(ln):  # overlapping copy
                        out.append(out[start])
                        start += 1
    except IndexError as exc:
        raise RefPackError("truncated RefPack stream") from exc
    if len(out) != target:
        raise RefPackError(f"size mismatch: header {target}, got {len(out)}")
    return bytes(out)
