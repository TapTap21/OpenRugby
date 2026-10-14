from __future__ import annotations

import json
import shutil
import struct
from pathlib import Path

import pytest

from openrugby_tools import audio

HAS_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None
needs_ffmpeg = pytest.mark.skipif(not HAS_FFMPEG, reason="ffmpeg/ffprobe not on PATH")

VGMSTREAM = audio.find_vgmstream()
needs_vgmstream = pytest.mark.skipif(
    not HAS_FFMPEG or VGMSTREAM is None, reason="vgmstream-cli or ffmpeg not available"
)

REPO = Path(__file__).resolve().parents[2]
AUDIO = REPO / "extracted" / "audio"


def item(tag: int, value: int, length: int) -> bytes:
    return bytes([tag, length]) + value.to_bytes(length, "big")


def build_schl(items: bytes, variant: str = "PT") -> bytes:
    """Build a synthetic SCHl header; the size field covers everything up to the terminator."""
    if variant == "PT":
        prefix = b"PT\x00\x00"
    else:
        prefix = b"GSTR" + b"\x01\x00\x00\x00"
    body = prefix + items + b"\xff"
    total = 8 + len(body)
    return b"SCHl" + struct.pack("<I", total) + body + b"SCCl" + b"\x0c\x00\x00\x00" + b"\0" * 4


PT_STREAM = build_schl(
    b"\x06\x01\x65"  # unknown tag 0x06, value 101 (present in every real stream)
    + b"\x80\x01\x01"  # codec: adpcm_ea_r1
    + b"\x82\x01\x02"  # channels: 2
    + b"\x84\x03\x00\xac\x44"  # rate: 44100
    + b"\x85\x03\x0d\xe9\x7d",  # samples per channel
    variant="PT",
)

GSTR_STREAM = build_schl(
    b"\xfd"  # marker that precedes the codec item in GSTR streams
    + item(0x80, 3, 1)  # codec: adpcm_ea_r3
    + item(0x85, 0x0C2000, 3)
    + item(0xA0, 4, 1)  # revision2 = 4, which ffmpeg rejects
    + item(0x84, 22050, 2),
    variant="GSTR",
)


def test_parse_pt_header() -> None:
    head = audio.parse_schl_header(PT_STREAM)
    assert head.variant == "PT"
    assert head.header_size == PT_STREAM.index(b"SCCl")  # size field ends where SCCl starts
    assert head.codec == 1
    assert head.channels == 2
    assert head.sample_rate == 44100
    assert head.sample_count == 0x0DE97D
    assert head.revision2 is None
    assert head.tags[0x06] == [101]
    assert head.duration_s == pytest.approx(0x0DE97D / 44100)


def test_parse_gstr_header_with_missing_channels() -> None:
    head = audio.parse_schl_header(GSTR_STREAM)
    assert head.variant == "GSTR"
    assert head.codec == 3
    assert head.channels is None
    assert head.sample_rate == 22050
    assert head.sample_count == 0x0C2000
    assert head.revision2 == 4


def test_header_only_needs_leading_bytes() -> None:
    head = audio.parse_schl_header(PT_STREAM[:40])
    assert head.sample_rate == 44100


def test_truncated_item_stops_without_error() -> None:
    truncated = PT_STREAM[:20]
    head = audio.parse_schl_header(truncated)
    assert head.codec == 1


def test_unknown_tags_are_kept_raw() -> None:
    data = build_schl(item(0x9C, 57343, 3) + item(0x0B, 2, 1), variant="PT")
    head = audio.parse_schl_header(data)
    assert head.tags[0x9C] == [57343]
    assert head.tags[0x0B] == [2]
    doc = head.as_dict()
    assert doc["tags"]["0x9C"] == [57343]


def test_rejects_bad_magic() -> None:
    with pytest.raises(audio.SchlError):
        audio.parse_schl_header(b"BIGF" + b"\0" * 20)


def test_rejects_unknown_patch_marker() -> None:
    with pytest.raises(audio.SchlError):
        audio.parse_schl_header(b"SCHl" + struct.pack("<I", 24) + b"XXXX" + b"\0" * 12)


def test_find_schl_files_uses_magic(tmp_path: Path) -> None:
    (tmp_path / "sub").mkdir()
    (tmp_path / "a.dat").write_bytes(PT_STREAM)
    (tmp_path / "sub" / "b.asf").write_bytes(GSTR_STREAM)
    (tmp_path / "zeros.dat").write_bytes(b"\0" * 64)
    (tmp_path / "manifest.json").write_text("{}")
    found = [p.name for p in audio.find_schl_files(tmp_path)]
    assert found == ["a.dat", "b.asf"]


@needs_ffmpeg
def test_convert_real_pt_stream(tmp_path: Path) -> None:
    src = AUDIO / "chants.big" / "Aus001.asf"
    if not src.exists():
        pytest.skip("extracted audio not present (run the extract step first)")
    result = audio.convert_one(src, src.parent, tmp_path)
    assert result.ok, result.error
    assert result.channels == 2
    assert result.rate == 44100
    assert (tmp_path / "Aus001.ogg").stat().st_size > 0
    assert result.header["sample_count"] == 0x0DE97D


@needs_ffmpeg
def test_gstr_revision2_4_fails_cleanly(tmp_path: Path) -> None:
    src = AUDIO / "dat_eng.big" / "0001_Abril.dat"
    if not src.exists():
        pytest.skip("extracted audio not present (run the extract step first)")
    result = audio.convert_one(src, src.parent, tmp_path, vgmstream=None)
    assert not result.ok
    assert result.error
    assert result.header["revision2"] == 4
    assert not (tmp_path / "0001_Abril.ogg").exists()


@needs_ffmpeg
def test_convert_tree_writes_index(tmp_path: Path) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "bad.dat").write_bytes(GSTR_STREAM)
    (src / "zeros.dat").write_bytes(b"\0" * 64)
    out = tmp_path / "out"
    index = audio.convert_tree(src, out, workers=2, vgmstream=None)
    assert index["summary"]["total"] == 1
    assert index["summary"]["failed"] == 1
    doc = json.loads((out / "index.json").read_text(encoding="utf-8"))
    assert doc["entries"][0]["source"] == "bad.dat"
    assert doc["entries"][0]["ok"] is False
    assert doc["entries"][0]["header"]["codec"] == 3


def test_find_vgmstream_explicit_and_missing(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = tmp_path / "vgmstream-cli"
    fake.write_bytes(b"")
    assert audio.find_vgmstream(fake) == fake
    assert audio.find_vgmstream(tmp_path / "nope") is None  # no silent fallthrough
    monkeypatch.setenv(audio.VGMSTREAM_ENV, str(fake))
    assert audio.find_vgmstream() == fake
    monkeypatch.setenv(audio.VGMSTREAM_ENV, str(tmp_path / "nope"))
    assert audio.find_vgmstream() is None


@needs_vgmstream
def test_microtalk_stream_decodes_via_vgmstream(tmp_path: Path) -> None:
    src = AUDIO / "dat_eng.big" / "0001_Abril.dat"
    if not src.exists():
        pytest.skip("extracted audio not present (run the extract step first)")
    result = audio.convert_one(src, src.parent, tmp_path, vgmstream=VGMSTREAM)
    assert result.ok, result.error
    assert result.decoder == "vgmstream"
    assert result.rate == 22050
    assert result.channels == 1
    assert result.duration == pytest.approx(result.header["duration_s"], abs=0.02)
    assert (tmp_path / "0001_Abril.ogg").stat().st_size > 0


@needs_vgmstream
def test_referee_stream_decodes_via_vgmstream(tmp_path: Path) -> None:
    src = AUDIO / "ref_eng.big" / "Referee_Australia_Colours_Advantage_Calling_1.snd"
    if not src.exists():
        pytest.skip("extracted audio not present (run the extract step first)")
    result = audio.convert_one(src, src.parent, tmp_path, vgmstream=VGMSTREAM)
    assert result.ok, result.error
    assert result.rate == 44100
    assert result.duration == pytest.approx(53717 / 44100, abs=0.02)


@needs_vgmstream
def test_ffmpeg_stream_keeps_ffmpeg_decoder(tmp_path: Path) -> None:
    src = AUDIO / "chants.big" / "Aus001.asf"
    if not src.exists():
        pytest.skip("extracted audio not present (run the extract step first)")
    result = audio.convert_one(src, src.parent, tmp_path, vgmstream=VGMSTREAM)
    assert result.ok, result.error
    assert result.decoder == "ffmpeg"
