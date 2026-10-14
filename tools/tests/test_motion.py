"""Tests for the motion clip reader using synthetic clips."""

from __future__ import annotations

import json
import struct
from pathlib import Path

import pytest

from openrugby_tools import motion

NCH = 1 + 8 + 3 + 4 * 26  # one translation bone, 26 rotation bones


def make_frames(n: int) -> list[list[int]]:
    frames = []
    for i in range(n):
        f = [0x0006 if i % 2 else 0x0002]
        f += [4 * i, 0, -3 * i, 1900 + i, 7, -230, 0, -729]  # header channels
        f += [i * 5, 1940 - i, -i]  # root translation
        for b in range(26):
            f += [100 * b - i, -50 + i * (b % 3), 3 * i, 16384 - 7 * b]
        frames.append(f)
    return frames


def test_round_trip_compressed() -> None:
    frames = make_frames(12)
    data = motion.encode_clip(frames)
    clip = motion.decode_clip(data, "TEST")
    assert clip.header.channel_count == NCH
    assert clip.header.data_offset == 0x24 + NCH
    assert clip.header.translation_bones == [0]
    assert clip.header.rotation_bones == list(range(26))
    assert len(clip.frames) == 12
    for src, fr in zip(frames, clip.frames, strict=True):
        assert fr.flags & 0x7FFF == src[0]
        assert list(fr.header) == src[1:9]
        assert list(fr.translations[0]) == src[9:12]
        assert [c for q in fr.rotations for c in q] == src[12:]
    assert not clip.frames[0].is_delta and clip.frames[1].is_delta


def test_round_trip_raw_keys() -> None:
    frames = make_frames(3)
    data = motion.encode_clip(frames, compressed=False)
    hdr = motion.parse_header(data)
    assert hdr.data_offset == 0x24 and hdr.bit_widths == ()
    assert hdr.flags & motion.CLIP_ALL_KEYS
    assert len(data) == 0x24 + 3 * (4 + 2 * (NCH - 1))
    clip = motion.decode_clip(data)
    assert [c for q in clip.frames[2].rotations for c in q] == frames[2][12:]


def test_bitstream_is_msb_first_u16_words() -> None:
    # widths 4, 8, 4 over one word 0xABCD (stored little-endian): A, BC, D, signed.
    assert motion._unpack_delta([0xABCD], [4, 8, 4]) == [-6, -68, -3]
    assert motion._unpack_delta([0x1234, 0x5678], [16, 0, 12, 4]) == [0x1234, 0, 0x567, -8]


def test_header_channels_are_absolute_others_delta() -> None:
    frames = make_frames(4)
    frames[3][4] = 1234  # header channel jumps; must not accumulate
    clip = motion.decode_clip(motion.encode_clip(frames))
    assert clip.frames[3].header[3] == 1234
    assert clip.frames[2].header[3] == frames[2][4]


def test_sixteen_bit_deltas_wrap() -> None:
    frames = make_frames(2)
    frames[0][12] = 32000
    frames[1][12] = -32000  # -64000 wraps to +1536 in 16 bits: 12-bit delta suffices
    clip = motion.decode_clip(motion.encode_clip(frames))
    assert clip.header.bit_widths[12] == 12
    assert clip.frames[1].rotations[0][0] == -32000


def test_full_translation_layout() -> None:
    mask = (1 << 26) - 1
    nch = 9 + 3 * 26 + 4 * 26
    frames = [[2] + [0] * 8 + list(range(78)) + [0, 0, 0, 16384] * 26 for _ in range(2)]
    clip = motion.decode_clip(motion.encode_clip(frames, translation_mask=mask))
    assert clip.header.channel_count == nch == 191
    assert clip.header.translation_bones == list(range(26))
    assert clip.frames[1].translations[25] == (75, 76, 77)


def test_rotation_is_conjugated_and_normalised() -> None:
    frames = make_frames(1)
    frames[0][12:16] = [8192, 8192, 8192, 8192]  # stored (0.5, 0.5, 0.5, 0.5)
    clip = motion.decode_clip(motion.encode_clip(frames))
    q = clip.local_rotation(0, 0)
    assert q == pytest.approx((-0.5, -0.5, -0.5, 0.5))
    assert clip.local_translation(0, 0) == pytest.approx((0.0, 1940 / 32, 0.0))


def test_header_channel_accessors() -> None:
    clip = motion.decode_clip(motion.encode_clip(make_frames(3)))
    assert clip.heading(2) == pytest.approx(8 / 1024)
    assert clip.root_position(2) == pytest.approx((-6 / 32, 1902 / 32, 7 / 32))
    assert clip.target_point() == pytest.approx((-230 / 32, 0.0, -729 / 32))
    assert clip.duration == pytest.approx(2 / 15)


def test_plant_flags() -> None:
    clip = motion.decode_clip(motion.encode_clip(make_frames(2)))
    assert clip.frames[0].left_foot_planted and not clip.frames[0].right_foot_planted
    assert clip.frames[1].left_foot_planted and clip.frames[1].right_foot_planted


@pytest.mark.parametrize(
    "patch, message",
    [
        (lambda d: b"\x02" + d[1:], "not a motion clip"),
        (lambda d: d[:0x10] + struct.pack("<H", 117) + d[0x12:], "channel count"),
        (lambda d: d + b"\0\0\0\0", "trailing"),
        (lambda d: d[:-2], "past end|bad record size|truncated"),
        (lambda d: d[:0x1C] + struct.pack("<I", 3) + d[0x20:], "masks"),
    ],
)
def test_malformed(patch, message: str) -> None:
    data = patch(motion.encode_clip(make_frames(3)))
    with pytest.raises(motion.MotionError, match=message):
        motion.decode_clip(data)


def test_census_and_dump(tmp_path: Path) -> None:
    (tmp_path / "a").mkdir()
    (tmp_path / "a" / "CLIP1").write_bytes(motion.encode_clip(make_frames(5)))
    (tmp_path / "a" / "CLIP2").write_bytes(motion.encode_clip(make_frames(5)))  # duplicate
    (tmp_path / "a" / "BAD").write_bytes(b"\x01\x0b" + b"\0" * 40)
    (tmp_path / "a" / "other.txt").write_bytes(b"1.000000\r\n")
    result = motion.census([tmp_path])
    assert result["stats"]["files"] == 3
    assert result["stats"]["duplicates"] == 1
    assert result["stats"]["decoded"] == 1
    assert len(result["failures"]) == 1
    text = motion.dump(motion.load_clip(tmp_path / "a" / "CLIP1"), every=1)
    assert "5 frames" in text and "plant=LR" in text


def test_append_animation() -> None:
    clip = motion.decode_clip(motion.encode_clip(make_frames(4)), "ANIM")
    doc: dict = {"nodes": [{"name": f"b{i}"} for i in range(26)]}
    binary = bytearray()
    idx = motion._append_animation(doc, binary, clip, {i: i for i in range(26)})
    anim = doc["animations"][idx]
    assert anim["name"] == "ANIM"
    paths = [c["target"]["path"] for c in anim["channels"]]
    assert paths.count("translation") == 1 and paths.count("rotation") == 26
    times = doc["accessors"][anim["samplers"][0]["input"]]
    assert times["count"] == 4 and times["max"] == [pytest.approx(3 / motion.FRAME_RATE)]
    assert len(binary) == sum(v["byteLength"] for v in doc["bufferViews"])
    json.dumps(doc)


def test_cli_dump(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    p = tmp_path / "CLIP"
    p.write_bytes(motion.encode_clip(make_frames(3)))
    assert motion.main(["dump", str(p)]) == 0
    assert "clip CLIP: 3 frames" in capsys.readouterr().out
