"""Tests for the SHPI/FSH decoder using synthetic containers (no game files needed)."""

from __future__ import annotations

import json
import struct
from pathlib import Path

import pytest

from openrugby_tools import fsh

Image = pytest.importorskip("PIL.Image")

REPO = Path(__file__).resolve().parents[2]


def _attach(code: int, payload: bytes, last: bool) -> bytes:
    """Attachment block: u32 (code | next << 8) + payload, padded to 4 bytes."""
    payload += b"\0" * (-len(payload) % 4)
    nxt = 0 if last else 4 + len(payload)
    return struct.pack("<I", code | nxt << 8) + payload


def _bitmap(
    code: int, w: int, h: int, pixels: bytes, *, mips: int = 0, name: str | None = None
) -> bytes:
    pixels += b"\0" * (-len(pixels) % 16)
    attachments = b""
    if name is not None:
        attachments = _attach(0x69, b"\0" * 8, last=False) + _attach(
            0x70, name.encode() + b"\0", last=True
        )
    attach_off = 16 + len(pixels) if attachments else 0
    head = struct.pack("<IHHHHHH", code | attach_off << 8, w, h, 0, 0, 0, mips << 12)
    return head + pixels + attachments


def _shpi(entries: list[tuple[str, bytes]], dir_id: str = "G359") -> bytes:
    base = 16 + 8 * len(entries) + 8
    body = b""
    directory = b""
    for tag, blob in entries:
        directory += tag.encode().ljust(4)[:4] + struct.pack("<I", base + len(body))
        body += blob
    total = base + len(body)
    return (
        b"SHPI"
        + struct.pack("<II", total, len(entries))
        + dir_id.encode()
        + directory
        + (b"Buy ERTS")
        + body
    )


def _dxt1_block(rgb565: int) -> bytes:
    return struct.pack("<HHI", rgb565, rgb565, 0)


def _dxt5_block(alpha: int, rgb565: int) -> bytes:
    return bytes([alpha, alpha]) + b"\0" * 6 + _dxt1_block(rgb565)


def test_parse_directory_and_attachments() -> None:
    blob = _bitmap(0x7D, 1, 1, b"\x01\x02\x03\x04", name="longname")
    parsed = fsh.parse_fsh(_shpi([("lon", blob)]))
    assert parsed.directory_id == "G359"
    (bm,) = parsed.bitmaps
    assert (bm.tag, bm.code, bm.width, bm.height) == ("lon ", 0x7D, 1, 1)
    assert [a.code for a in bm.attachments] == [0x69, 0x70]
    assert bm.name == "longname"


def test_bad_magic_and_truncated() -> None:
    with pytest.raises(fsh.FshError):
        fsh.parse_fsh(b"NOPE" + b"\0" * 20)
    with pytest.raises(fsh.FshError):
        fsh.parse_fsh(b"SHPI" + struct.pack("<II", 0, 99) + b"G359")


def test_decode_argb8888_is_bgra() -> None:
    px = bytes([10, 20, 30, 40])  # B G R A
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x7D, 1, 1, px))]))
    (img,) = fsh.decode_bitmap(f, f.bitmaps[0])
    assert img.mode == "RGBA"
    assert img.getpixel((0, 0)) == (30, 20, 10, 40)


def test_decode_rgb888_is_bgr() -> None:
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x7F, 2, 1, bytes([1, 2, 3, 4, 5, 6])))]))
    (img,) = fsh.decode_bitmap(f, f.bitmaps[0])
    assert img.mode == "RGB"
    assert img.getpixel((0, 0)) == (3, 2, 1)
    assert img.getpixel((1, 0)) == (6, 5, 4)


def test_decode_dxt1_solid_red() -> None:
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x60, 4, 4, _dxt1_block(0xF800)))]))
    (img,) = fsh.decode_bitmap(f, f.bitmaps[0])
    assert img.size == (4, 4)
    assert img.getpixel((2, 2))[:3] == (255, 0, 0)


def test_decode_dxt5_alpha() -> None:
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x62, 4, 4, _dxt5_block(128, 0x07E0)))]))
    (img,) = fsh.decode_bitmap(f, f.bitmaps[0])
    r, g, b, a = img.getpixel((1, 1))
    assert (r, g, b) == (0, 255, 0)
    assert a == 128


def test_mip_chain_dxt1() -> None:
    pixels = _dxt1_block(0xF800) * 4 + _dxt1_block(0x001F)  # 8x8 then 4x4
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x60, 8, 8, pixels, mips=1))]))
    assert f.bitmaps[0].mip_count == 1
    base, mip = fsh.decode_bitmap(f, f.bitmaps[0], mips=True)
    assert base.size == (8, 8) and mip.size == (4, 4)
    assert mip.getpixel((0, 0))[:3] == (0, 0, 255)
    assert len(fsh.decode_bitmap(f, f.bitmaps[0])) == 1


def test_unsupported_format_raises() -> None:
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x7B, 1, 1, b"\0\0\0\0"))]))
    with pytest.raises(fsh.FshError):
        fsh.decode_bitmap(f, f.bitmaps[0])


def test_truncated_pixels_raise() -> None:
    f = fsh.parse_fsh(_shpi([("a", _bitmap(0x7D, 1, 1, b"\0" * 4))]))
    f.bitmaps[0].width = 64
    with pytest.raises(fsh.FshError):
        fsh.decode_bitmap(f, f.bitmaps[0])


def test_cli_convert_roundtrip_and_name_dedupe(tmp_path: Path) -> None:
    src = tmp_path / "in" / "pack.gob"
    src.mkdir(parents=True)
    entries = [
        ("kit", _bitmap(0x7D, 1, 1, bytes(4), name="kit_home")),
        ("kit", _bitmap(0x7D, 1, 1, bytes(4), name="kit_home")),  # same name -> suffix
        ("bad", _bitmap(0x62, 4, 4, _dxt5_block(255, 0xFFFF))),
    ]
    # Raw (compressed) member plus its decoded .unpacked sibling: the sibling wins.
    (src / "a.fsh").write_bytes(b"\x10\xfbnotshpi")
    (src / "a.fsh.unpacked").write_bytes(_shpi(entries))
    (src / "readme.txt").write_text("not a texture")
    out = tmp_path / "out"
    rc = fsh.main(["convert", "--root", str(tmp_path / "in"), "--out", str(out), "--jobs", "1"])
    assert rc == 0
    assert (out / "pack.gob" / "a.fsh" / "kit_home.png").is_file()
    assert (out / "pack.gob" / "a.fsh" / "kit_home_2.png").is_file()
    assert (out / "pack.gob" / "a.fsh" / "bad.png").is_file()
    index = json.loads((out / "index.json").read_text())
    assert len(index["textures"]) == 1
    assert [b["format"] for b in index["textures"][0]["bitmaps"]] == ["0x7D", "0x7D", "0x62"]


def test_cli_census(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "x.fsh").write_bytes(_shpi([("a", _bitmap(0x7F, 1, 1, bytes(3)))]))
    assert fsh.main(["census", "--root", str(tmp_path), "--jobs", "1"]) == 0
    text = capsys.readouterr().out
    assert "0x7F: 1" in text and "failures: 0" in text


_SAMPLES = sorted((REPO / "extracted" / "data.gob").glob("*.fsh.unpacked"))[:1]


@pytest.mark.skipif(not _SAMPLES, reason="extracted game files not present")
def test_real_sample_decodes() -> None:
    data = _SAMPLES[0].read_bytes()
    f = fsh.parse_fsh(data)
    assert f.declared_size == len(data)
    assert f.bitmaps
    for bm in f.bitmaps:
        (img,) = fsh.decode_bitmap(f, bm)
        assert img.size == (bm.width, bm.height)
