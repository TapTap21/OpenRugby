"""Tests for tools/re/inline_securom.py using a synthetic image (no game data)."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "re"))

import inline_securom as m  # noqa: E402

SIZE = 0x1100000
PTR_BASE = 0x1100000 - 0x100  # pointer cells (VA 0x1000000+) are placed below
STUB_BASE = 0x4C0000


def _image() -> bytearray:
    return bytearray(SIZE)


def _put_trampoline(img: bytearray, addr: int, cell: int, stub: int) -> None:
    img[addr - m.IMAGE_BASE : addr - m.IMAGE_BASE + 6] = b"\xff\x25" + struct.pack("<I", cell)
    struct.pack_into("<I", img, cell - m.IMAGE_BASE, stub)


def _put_stub(img: bytearray, stub: int, code: bytes, back: int) -> None:
    jmp_at = stub + len(code)
    rel = back - (jmp_at + 5)
    blob = code + b"\xe9" + struct.pack("<i", rel)
    img[stub - m.IMAGE_BASE : stub - m.IMAGE_BASE + len(blob)] = blob


def _run(img: bytearray):
    out, results, _ = m.repair(bytes(img), redirect=False)
    return out, {r.addr: r for r in results}


def test_simple_inline_and_nop_pad() -> None:
    img = _image()
    t = 0x402000
    _put_trampoline(img, t, 0x1000100, STUB_BASE)
    _put_stub(img, STUB_BASE, b"\x55", t + 6)  # push ebp
    out, res = _run(img)
    assert res[t].status == m.OK
    assert bytes(out[t - m.IMAGE_BASE : t - m.IMAGE_BASE + 6]) == b"\x55" + b"\x90" * 5


def test_six_byte_instruction() -> None:
    img = _image()
    t = 0x402100
    _put_trampoline(img, t, 0x1000104, STUB_BASE)
    code = b"\x81\xec\xec\x00\x00\x00"  # sub esp, 0xec
    _put_stub(img, STUB_BASE, code, t + 6)
    out, res = _run(img)
    assert res[t].status == m.OK
    assert bytes(out[t - m.IMAGE_BASE : t - m.IMAGE_BASE + 6]) == code


def test_call_is_retargeted() -> None:
    img = _image()
    t = 0x402200
    _put_trampoline(img, t, 0x1000108, STUB_BASE)
    target = 0x410000
    call = b"\xe8" + struct.pack("<i", target - (STUB_BASE + 5))
    _put_stub(img, STUB_BASE, call, t + 6)
    out, res = _run(img)
    assert res[t].status == m.OK
    new = bytes(out[t - m.IMAGE_BASE : t - m.IMAGE_BASE + 6])
    assert new[0] == 0xE8
    assert t + 5 + struct.unpack("<i", new[1:5])[0] == target
    assert new[5] == 0x90


def test_short_jcc_is_retargeted() -> None:
    img = _image()
    t = 0x402300
    _put_trampoline(img, t, 0x100010C, STUB_BASE)
    target = t + 0x20
    # Stub is far from target, so the original rel8 cannot reach: build a rel32 jcc.
    jcc = b"\x0f\x84" + struct.pack("<i", target - (STUB_BASE + 6))
    _put_stub(img, STUB_BASE, jcc, t + 6)
    out, res = _run(img)
    assert res[t].status == m.OK
    new = bytes(out[t - m.IMAGE_BASE : t - m.IMAGE_BASE + 6])
    assert new[:2] == b"\x0f\x84"
    assert t + 6 + struct.unpack("<i", new[2:])[0] == target


def test_too_long_left_untouched() -> None:
    img = _image()
    t = 0x402400
    _put_trampoline(img, t, 0x1000110, STUB_BASE)
    _put_stub(img, STUB_BASE, b"\x8b\x0d\x00\x00\x00\x01\x8b\x09", t + 6)  # 8 bytes
    out, res = _run(img)
    assert res[t].status == m.TOO_LONG
    assert out == img


def test_bad_jmp_back_left_untouched() -> None:
    img = _image()
    t = 0x402500
    _put_trampoline(img, t, 0x1000114, STUB_BASE)
    _put_stub(img, STUB_BASE, b"\x55", t + 7)
    out, res = _run(img)
    assert res[t].status == m.BAD
    assert out == img


def test_ignores_jmp_outside_securom_block() -> None:
    img = _image()
    t = 0x402600
    img[t - m.IMAGE_BASE : t - m.IMAGE_BASE + 6] = b"\xff\x25" + struct.pack("<I", 0x8CD000)
    assert m.find_trampolines(bytes(img)) == []


def test_cli_roundtrip(tmp_path: Path) -> None:
    img = _image()
    t = 0x402700
    _put_trampoline(img, t, 0x1000118, STUB_BASE)
    _put_stub(img, STUB_BASE, b"\x55", t + 6)
    src, dst, rep = tmp_path / "a.exe", tmp_path / "b.exe", tmp_path / "r.json"
    src.write_bytes(bytes(img))
    assert m.main(["--in", str(src), "--out", str(dst), "--report", str(rep), "--no-redirect"]) == 0
    assert dst.stat().st_size == src.stat().st_size
    assert '"OK": 1' in rep.read_text()


def _with_pe(img: bytearray) -> None:
    """Minimal PE header: one .data section spanning the whole synthetic image."""
    pe = 0x80
    struct.pack_into("<I", img, 0x3C, pe)
    img[pe : pe + 4] = b"PE\0\0"
    struct.pack_into("<H", img, pe + 6, 1)
    struct.pack_into("<H", img, pe + 20, 224)
    opt = pe + 24
    struct.pack_into("<I", img, opt + 4, 0x1000)
    struct.pack_into("<I", img, opt + 8, 0x1000000)
    struct.pack_into("<I", img, opt + 60, 0x1000)
    sec = opt + 224
    img[sec : sec + 8] = b".data\0\0\0"
    rva, size = 0x1000, SIZE - 0x1000 - 0x400000 + 0x400000
    struct.pack_into("<6I", img, sec + 8, size, rva, size, rva, 0, 0)
    struct.pack_into("<I", img, sec + 36, 0xC0000040)


def test_redirect_and_section_split() -> None:
    size = 0x1500000
    img = bytearray(size)
    _with_pe(img)
    struct.pack_into(
        "<6I", img, 0x80 + 24 + 224 + 8, size - 0x1000, 0x1000, size - 0x1000, 0x1000, 0, 0
    )
    t = 0x402800
    stub = 0x1100000  # inside the measured stub range
    cell = 0x1000200
    _put_trampoline(img, t, cell, stub)
    img[stub - m.IMAGE_BASE : stub - m.IMAGE_BASE + 3] = b"\x55\x8b\xec"  # no jmp-back
    bad = 0x402900  # false match: pointer cell holds a non-code value
    _put_trampoline(img, bad, cell + 4, 0x24748908)
    out, results, info = m.repair(bytes(img))
    by = {r.addr: r for r in results}
    assert by[t].status == m.REDIRECT
    assert by[bad].status == m.BAD
    new = bytes(out[t - m.IMAGE_BASE : t - m.IMAGE_BASE + 6])
    assert new[0] == 0xE9 and new[5] == 0x90
    assert t + 5 + struct.unpack("<i", new[1:5])[0] == stub
    assert bytes(out[bad - m.IMAGE_BASE : bad - m.IMAGE_BASE + 6]) == bytes(
        img[bad - m.IMAGE_BASE : bad - m.IMAGE_BASE + 6]
    )
    assert info is not None and info["sections"] == 3
    table = 0x80 + 24 + 224
    names = [bytes(out[table + 40 * i : table + 40 * i + 8]).rstrip(b"\0") for i in range(3)]
    assert names == [b".data", b".secu", b".data2"]
    secu = table + 40
    vsize, rva = struct.unpack_from("<2I", out, secu + 8)
    assert rva == m.REDIRECT_START - m.IMAGE_BASE and vsize == m.REDIRECT_END - m.REDIRECT_START
    assert struct.unpack_from("<I", out, secu + 36)[0] == m.SCN_CODE_EXEC_READ
    assert len(out) == len(img)
