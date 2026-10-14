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


def _prefix(n: int) -> tuple[bytes, bytes]:
    """Literal-only stream body producing ``n`` (multiple of 4) pseudo-random bytes."""
    data = bytes((i * 7 + (i >> 8) * 13 + 1) & 0xFF for i in range(n))
    body = bytearray()
    i = 0
    while i < n:
        run = min(n - i, 112)
        body.append(0xE0 + (run - 4) // 4)
        body += data[i : i + run]
        i += run
    return data, bytes(body)


def _expect(out: bytearray, off: int, ln: int) -> None:
    for _ in range(ln):
        out.append(out[-off])


def test_two_byte_code_high_offset_and_length_bits() -> None:
    data, body = _prefix(1000)
    off, ln = 700, 10  # off-1 = 699 -> cc bits 5-6 = 2, b1 = 187; ln-3 = 7
    cc = ((off - 1) >> 3 & 0x60) | ((ln - 3) << 2) | 2
    out = bytearray(data)
    out += b"ZZ"
    _expect(out, off, ln)
    stream = header(len(out)) + body + bytes([cc, (off - 1) & 0xFF]) + b"ZZ" + bytes([0xFC])
    assert refpack.decompress(stream) == bytes(out)


def test_three_byte_code_fields() -> None:
    data, body = _prefix(1000)
    off, ln, lit = 9000 % 1000 + 600, 67, 3  # off 1..16384, ln 4..67
    cc = 0x80 | (ln - 4)
    b1 = (lit << 6) | ((off - 1) >> 8)
    out = bytearray(data)
    out += b"abc"
    _expect(out, off, ln)
    stream = header(len(out)) + body + bytes([cc, b1, (off - 1) & 0xFF]) + b"abc" + bytes([0xFC])
    assert refpack.decompress(stream) == bytes(out)


def test_four_byte_code_fields() -> None:
    data, body = _prefix(70000)
    off, ln, lit = 66000, 900, 2  # needs offset bit 16 (cc&0x10) and length bits 8-9
    ol, ll = off - 1, ln - 5
    cc = 0xC0 | ((ol >> 16) << 4) | ((ll >> 8) << 2) | lit
    out = bytearray(data)
    out += b"QR"
    _expect(out, off, ln)
    stream = (
        header(len(out))
        + body
        + bytes([cc, (ol >> 8) & 0xFF, ol & 0xFF, ll & 0xFF])
        + b"QR"
        + bytes([0xFC])
    )
    assert refpack.decompress(stream) == bytes(out)


def test_four_byte_code_overlap_and_trailing_literals() -> None:
    # off=2, ln=300 overlaps; stop code carries 3 trailing literals
    stream = header(4 + 300 + 3) + bytes([0xE0]) + b"abcd"
    stream += (
        bytes([0xC0 | (((300 - 5) >> 8) << 2), 0, 1, (300 - 5) & 0xFF]) + bytes([0xFF]) + b"xyz"
    )
    exp = bytearray(b"abcd")
    _expect(exp, 2, 300)
    assert refpack.decompress(stream) == bytes(exp) + b"xyz"


def test_header_flag_decoding() -> None:
    body = bytes([0xE0]) + b"abcd" + bytes([0xFC])
    h4 = bytes([0x90, 0xFB]) + (4).to_bytes(4, "big")
    assert refpack.decompress(h4 + body) == b"abcd"
    h91 = bytes([0x91, 0xFB]) + (9).to_bytes(4, "big") + (4).to_bytes(4, "big")
    assert refpack.decompress(h91 + body) == b"abcd"
    h11 = bytes([0x11, 0xFB]) + (9).to_bytes(3, "big") + (4).to_bytes(3, "big")
    assert refpack.decompress(h11 + body) == b"abcd"
    hle = bytes([0xFB, 0x10]) + (4).to_bytes(3, "little")
    assert refpack.decompress(hle + body) == b"abcd"
