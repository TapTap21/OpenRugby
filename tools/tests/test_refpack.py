from __future__ import annotations

import pytest
from openrugby_tools import refpack


def header(size: int, flags: int = 0x10) -> bytes:
    return bytes([flags, 0xFB]) + size.to_bytes(3, "big")


def literal_stream(data: bytes) -> bytes:
    """Encode using only literal runs (0xE0-0xFB) and a stop code."""
    out = bytearray(header(len(data)))
    i = 0
    while len(data) - i > 3:
        run = min((len(data) - i) // 4 * 4, 112)
        out.append(0xE0 + (run - 4) // 4)
        out += data[i : i + run]
        i += run
    rest = data[i:]
    out.append(0xFC + len(rest))
    out += rest
    return bytes(out)


def test_literal_roundtrip() -> None:
    data = bytes(range(200))
    assert refpack.decompress(literal_stream(data)) == data


def test_short_backref_and_overlap() -> None:
    # literal "ab" via 2-byte code: lit=2, len=3?, off=2 -> "ab"+"aba"... then stop
    # cc: lit=2 (bits0-1), len-3=0 (bits2-4), off high bits 0 -> cc=0x02, b1=off-1=1
    stream = header(5) + bytes([0x02, 0x01]) + b"ab" + bytes([0xFC])
    assert refpack.decompress(stream) == b"ababa"


def test_three_byte_and_four_byte_codes() -> None:
    # 3-byte: lit=1, len=4+2=6, off=1 -> "x" then 6x"x"
    cc3 = 0x80 | 2
    stream = header(7) + bytes([cc3, (1 << 6) | 0, 0]) + b"x" + bytes([0xFC])
    assert refpack.decompress(stream) == b"x" * 7
    # 4-byte code: copy 6 bytes from 4 back after a 4-byte literal run
    lit = bytes([0xE0]) + b"abcd"  # literal run of 4
    cc4 = 0xC0  # len=5+b3, off=b1<<8|b2 + 1
    stream = header(4 + 6) + lit + bytes([cc4, 0, 3, 1]) + bytes([0xFC])
    assert refpack.decompress(stream) == b"abcd" + b"abcdab"


def test_header_variants() -> None:
    assert refpack.parse_header(bytes([0x90, 0xFB]) + (7).to_bytes(4, "big")) is not None
    h = refpack.parse_header(bytes([0x11, 0xFB]) + (9).to_bytes(3, "big") + (7).to_bytes(3, "big"))
    assert h is not None and h.compressed_size == 9 and h.uncompressed_size == 7
    le = refpack.parse_header(bytes([0xFB, 0x10]) + (7).to_bytes(3, "little"))
    assert le is not None and le.little_endian and le.uncompressed_size == 7
    assert refpack.parse_header(b"BIGFxxxx") is None


def test_errors() -> None:
    with pytest.raises(refpack.RefPackError):
        refpack.decompress(b"nope")
    with pytest.raises(refpack.RefPackError):
        refpack.decompress(header(10) + bytes([0xFC]))  # size mismatch
    with pytest.raises(refpack.RefPackError):
        refpack.decompress(header(3) + bytes([0x00, 0x05, 0xFC]))  # ref before start
