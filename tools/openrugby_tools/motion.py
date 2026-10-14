"""Reader for Rugby 08 animation clips (FIFA-engine "MO" motion format) with glTF export.

Clip files are the hash-named members (for example ``HFOAAA2``) of
``Data/motion/moai.viv`` (gameplay library) and of the 1,687 set-piece ``.viv``
archives inside ``Data/motion/script.big``. They start with the bytes
``01 0B`` followed by a little-endian u16 giving the offset of the first frame
record. See ``docs/re/12-motion-animation.md`` for evidence and confidence.

Layout (all little-endian)::

    0x00 u8   version (1)            0x01 u8  type (0x0B)
    0x02 u16  offset of first frame record (0x98, 0x24 or 0xE4)
    0x04 u16  length in 60 Hz ticks (4*frames or 4*frames+2)
    0x06 u16  frame count
    0x08 6 x 0xFF
    0x0E u16  clip flags (bit 15: every frame is a raw key frame)
    0x10 u16  channel count C = 1 + 8 + 3*T + 4*R
    0x12 u16  5 (unknown)
    0x14 u16  T, number of bones with translation tracks
    0x16 u16  R, number of bones with rotation tracks
    0x18 u32  mask_18 (0x04000000; unknown)
    0x1C u32  translation bone mask (bit i = skeleton bone i)
    0x20 u32  rotation bone mask
    0x24 u8[C] bit width per channel (only when the first record is past 0x24)

Channels: 0 = frame flags, 1..8 = per-frame "header" values, then 3*T
translations (x, y, z per bone, 1/32 model unit) and 4*R rotations (quaternion
x, y, z, w in Q14). Every frame record starts ``u16 size, u16 flags`` and
holds the 8 header channels as raw int16. Frame 0 (and every frame of a clip
with flag bit 15) continues with the remaining channels as raw int16. Later
frames of a compressed clip continue with a bitstream: channels 9..C-1 in
order, ``width[i]`` bits each, read MSB-first from consecutive little-endian
u16 words, two's complement, added to the previous frame (16-bit wrap). All
delta records of a clip have the same size, so frame i is found by arithmetic.

CLI: ``python -m openrugby_tools.motion {census,dump,gltf}``.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
from collections import Counter
from collections.abc import Iterator, Sequence
from dataclasses import dataclass, field
from pathlib import Path

CLIP_MAGIC = b"\x01\x0b"
HEADER_SIZE = 0x24
HEADER_CHANNELS = 8  # channels 1..8, stored absolutely
FRAME_DELTA = 0x8000  # frame flag: bit-packed delta frame
FRAME_LEFT_PLANT = 0x0002  # inferred: left foot planted
FRAME_RIGHT_PLANT = 0x0004  # inferred: right foot planted
CLIP_ALL_KEYS = 0x8000  # clip flag: no bit-width table, raw frames only

FRAME_RATE = 15.0  # frames per second (engine: duration = (frames - 1) / 15)
TICKS_PER_FRAME = 4  # playback time is kept in 1/60 s ticks; frame = tick / 4
HEADING_UNITS_PER_TURN = 1024  # channel 1, wraps at 1024
TRANSLATION_SCALE = 1.0 / 32.0  # model units per stored unit (engine multiplies by 0.03125)
QUAT_SCALE = 1.0 / 16384.0  # Q14


class MotionError(ValueError):
    """Raised for malformed clip data."""


@dataclass(frozen=True)
class ClipHeader:
    version: int
    kind: int
    data_offset: int
    field_04: int
    frame_count: int
    flags: int
    channel_count: int
    field_12: int
    translation_count: int
    rotation_count: int
    mask_18: int
    translation_mask: int
    rotation_mask: int
    bit_widths: tuple[int, ...]

    @property
    def translation_bones(self) -> list[int]:
        return _mask_bits(self.translation_mask)

    @property
    def rotation_bones(self) -> list[int]:
        return _mask_bits(self.rotation_mask)


@dataclass
class Frame:
    flags: int
    # channels 1..8: heading (1/1024 turn), unused (0), root position x, y, z
    # (1/32 unit), target point x, y, z (1/32 unit; per-clip constant)
    header: tuple[int, ...]
    translations: list[tuple[int, int, int]]  # raw, one per translation bone
    rotations: list[tuple[int, int, int, int]]  # raw Q14 x, y, z, w

    @property
    def is_delta(self) -> bool:
        return bool(self.flags & FRAME_DELTA)

    @property
    def left_foot_planted(self) -> bool:
        return bool(self.flags & FRAME_LEFT_PLANT)

    @property
    def right_foot_planted(self) -> bool:
        return bool(self.flags & FRAME_RIGHT_PLANT)


@dataclass
class Clip:
    name: str
    header: ClipHeader
    frames: list[Frame] = field(default_factory=list)

    @property
    def duration(self) -> float:
        return max(len(self.frames) - 1, 0) / FRAME_RATE

    def local_rotation(self, frame: int, slot: int) -> tuple[float, float, float, float]:
        """Rotation track ``slot`` as a unit quaternion in the skeleton's convention.

        Stored quaternions are the conjugate of the ``!skel.o`` local rotation
        convention (observed: rest-like poses match the bind pose only after
        negating x, y and z).
        """
        x, y, z, w = (c * QUAT_SCALE for c in self.frames[frame].rotations[slot])
        n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
        return (-x / n, -y / n, -z / n, w / n)

    def heading(self, frame: int) -> float:
        """Root heading in turns (channel 1 / 1024, wrapping)."""
        return self.frames[frame].header[0] / HEADING_UNITS_PER_TURN

    def root_position(self, frame: int) -> tuple[float, float, float]:
        """Root trajectory point (channels 3-5) in model units."""
        h = self.frames[frame].header
        return (h[2] * TRANSLATION_SCALE, h[3] * TRANSLATION_SCALE, h[4] * TRANSLATION_SCALE)

    def target_point(self, frame: int = 0) -> tuple[float, float, float]:
        """Clip target point (channels 6-8) in model units; constant in shipped clips."""
        h = self.frames[frame].header
        return (h[5] * TRANSLATION_SCALE, h[6] * TRANSLATION_SCALE, h[7] * TRANSLATION_SCALE)

    def local_translation(self, frame: int, slot: int) -> tuple[float, float, float]:
        t = self.frames[frame].translations[slot]
        return (t[0] * TRANSLATION_SCALE, t[1] * TRANSLATION_SCALE, t[2] * TRANSLATION_SCALE)


def _mask_bits(mask: int) -> list[int]:
    return [i for i in range(32) if mask >> i & 1]


def is_clip(data: bytes) -> bool:
    return len(data) >= HEADER_SIZE and data[:2] == CLIP_MAGIC


def parse_header(data: bytes) -> ClipHeader:
    if not is_clip(data):
        raise MotionError("not a motion clip (missing 01 0B magic)")
    version, kind, off, f04, nframes = struct.unpack_from("<BBHHH", data, 0)
    flags, nch, f12, nt, nr, m18, mt, mr = struct.unpack_from("<HHHHHIII", data, 0x0E)
    if nch != 1 + HEADER_CHANNELS + 3 * nt + 4 * nr:
        raise MotionError(f"channel count {nch} != 9 + 3*{nt} + 4*{nr}")
    if len(_mask_bits(mt)) != nt or len(_mask_bits(mr)) != nr:
        raise MotionError("bone masks disagree with track counts")
    widths: tuple[int, ...] = ()
    if off > HEADER_SIZE:
        if off < HEADER_SIZE + nch or off > len(data):
            raise MotionError(f"bad data offset {off:#x}")
        widths = tuple(data[HEADER_SIZE : HEADER_SIZE + nch])
        if any(w > 16 for w in widths):
            raise MotionError("bit width above 16")
    elif off != HEADER_SIZE:
        raise MotionError(f"bad data offset {off:#x}")
    return ClipHeader(
        version, kind, off, f04, nframes, flags, nch, f12, nt, nr, m18, mt, mr, widths
    )


def _unpack_delta(words: Sequence[int], widths: Sequence[int]) -> list[int]:
    """Read signed fields of ``widths`` bits MSB-first from 16-bit words."""
    out: list[int] = []
    acc = nbits = pos = 0
    for w in widths:
        if w == 0:
            out.append(0)
            continue
        while nbits < w:
            if pos >= len(words):
                raise MotionError("delta frame bitstream truncated")
            acc = (acc << 16) | words[pos]
            pos += 1
            nbits += 16
        nbits -= w
        v = (acc >> nbits) & ((1 << w) - 1)
        acc &= (1 << nbits) - 1
        out.append(v - (1 << w) if v >> (w - 1) else v)
    return out


def _wrap16(v: int) -> int:
    return ((v + 0x8000) & 0xFFFF) - 0x8000


def iter_raw_frames(data: bytes, hdr: ClipHeader) -> Iterator[list[int]]:
    """Yield the absolute channel vector (index 0 = frame flags) for each frame."""
    n = hdr.channel_count
    off = hdr.data_offset
    prev: list[int] | None = None
    for index in range(hdr.frame_count):
        if off + 4 > len(data):
            raise MotionError(f"frame {index}: record header past end of file")
        size, flags = struct.unpack_from("<HH", data, off)
        if size < 4 or off + size > len(data):
            raise MotionError(f"frame {index}: bad record size {size}")
        # The engine keys off the clip flag: raw clips hold only key frames; in
        # compressed clips frame 0 is a key frame and every later record is a delta.
        if index == 0 or not hdr.bit_widths:
            if size < 4 + 2 * (n - 1):
                raise MotionError(f"frame {index}: key frame too short")
            vals = [flags, *struct.unpack_from(f"<{n - 1}h", data, off + 4)]
        else:
            assert prev is not None
            base = 4 + 2 * HEADER_CHANNELS  # size, flags, 8 raw header channels
            if size < base:
                raise MotionError(f"frame {index}: delta frame too short")
            vals = [flags, *struct.unpack_from(f"<{HEADER_CHANNELS}h", data, off + 4)]
            words = struct.unpack_from(f"<{(size - base) // 2}H", data, off + base)
            deltas = _unpack_delta(words, hdr.bit_widths[1 + HEADER_CHANNELS :])
            vals += [
                _wrap16(p + d) for p, d in zip(prev[1 + HEADER_CHANNELS :], deltas, strict=True)
            ]
        yield vals
        prev = vals
        off += size
    if off != len(data):
        raise MotionError(f"{len(data) - off} trailing bytes after {hdr.frame_count} frames")


def decode_clip(data: bytes, name: str = "") -> Clip:
    hdr = parse_header(data)
    clip = Clip(name, hdr)
    t0 = 1 + HEADER_CHANNELS
    r0 = t0 + 3 * hdr.translation_count
    for vals in iter_raw_frames(data, hdr):
        trans = [tuple(vals[t0 + 3 * i : t0 + 3 * i + 3]) for i in range(hdr.translation_count)]
        rots = [tuple(vals[r0 + 4 * i : r0 + 4 * i + 4]) for i in range(hdr.rotation_count)]
        clip.frames.append(
            Frame(vals[0], tuple(vals[1:t0]), trans, rots)  # type: ignore[arg-type]
        )
    return clip


def load_clip(path: str | Path) -> Clip:
    p = Path(path)
    return decode_clip(p.read_bytes(), p.name)


# --------------------------------------------------------------------------- encoder


def _pack_delta(values: Sequence[int], widths: Sequence[int]) -> bytes:
    acc = nbits = 0
    words: list[int] = []
    for v, w in zip(values, widths, strict=True):
        if w == 0:
            if v:
                raise MotionError("non-zero delta on a zero-width channel")
            continue
        if not -(1 << (w - 1)) <= v < (1 << (w - 1)) and w < 16:
            raise MotionError(f"delta {v} does not fit {w} bits")
        acc = (acc << w) | (v & ((1 << w) - 1))
        nbits += w
        while nbits >= 16:
            nbits -= 16
            words.append((acc >> nbits) & 0xFFFF)
            acc &= (1 << nbits) - 1
    if nbits:
        words.append((acc << (16 - nbits)) & 0xFFFF)
    if len(words) % 2:  # records are padded to 4 bytes
        words.append(0)
    return struct.pack(f"<{len(words)}H", *words)


def encode_clip(
    frames: Sequence[Sequence[int]],
    translation_mask: int = 1,
    rotation_mask: int = (1 << 26) - 1,
    compressed: bool = True,
    field_04: int | None = None,
) -> bytes:
    """Build a clip from absolute channel vectors (index 0 = frame flags).

    Frame 0 is always a key frame. With ``compressed`` the remaining frames are
    delta frames using the smallest bit width that fits each channel.
    """
    nt, nr = len(_mask_bits(translation_mask)), len(_mask_bits(rotation_mask))
    nch = 1 + HEADER_CHANNELS + 3 * nt + 4 * nr
    if any(len(f) != nch for f in frames):
        raise MotionError(f"every frame needs {nch} channels")
    widths = [16] * nch
    deltas: list[list[int]] = []
    if compressed:
        for i in range(1, len(frames)):
            d = [
                frames[i][c] if c <= HEADER_CHANNELS else _wrap16(frames[i][c] - frames[i - 1][c])
                for c in range(1, nch)
            ]
            deltas.append(d)
        for c in range(1 + HEADER_CHANNELS, nch):
            need = 0
            for d in deltas:
                v = d[c - 1]
                if v:
                    need = max(need, (v if v > 0 else ~v).bit_length() + 1)
            widths[c] = min(need, 16)
    off = HEADER_SIZE + (nch + (nch & 1) if compressed else 0)
    flags = 0x0001 | (0 if compressed else CLIP_ALL_KEYS)
    f04 = 4 * len(frames) if field_04 is None else field_04
    head = struct.pack("<BBHHH", 1, 0x0B, off, f04, len(frames)) + b"\xff" * 6
    head += struct.pack(
        "<HHHHHIII", flags, nch, 5, nt, nr, 1 << 26, translation_mask, rotation_mask
    )
    if compressed:
        head += bytes(widths) + b"\0" * (off - HEADER_SIZE - nch)
    body = bytearray()
    for i, f in enumerate(frames):
        if i == 0 or not compressed:
            payload = struct.pack(f"<{nch - 1}h", *f[1:])
            body += struct.pack("<HH", 4 + len(payload), f[0] & 0x7FFF) + payload
        else:
            payload = struct.pack(f"<{HEADER_CHANNELS}h", *f[1 : 1 + HEADER_CHANNELS])
            payload += _pack_delta(deltas[i - 1][HEADER_CHANNELS:], widths[1 + HEADER_CHANNELS :])
            body += struct.pack("<HH", 4 + len(payload), (f[0] | FRAME_DELTA) & 0xFFFF) + payload
    return bytes(head + body)


# --------------------------------------------------------------------------- census / dump


def find_clips(roots: Sequence[Path]) -> Iterator[Path]:
    for root in roots:
        if root.is_file():
            yield root
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in sorted(filenames):
                p = Path(dirpath) / name
                with p.open("rb") as fh:
                    if fh.read(2) == CLIP_MAGIC:
                        yield p


def census(roots: Sequence[Path]) -> dict:
    stats: Counter[str] = Counter()
    layouts: Counter[str] = Counter()
    frames: Counter[int] = Counter()
    failures: list[dict] = []
    seen: set[bytes] = set()
    total_frames = 0
    for p in find_clips(roots):
        data = p.read_bytes()
        stats["files"] += 1
        key = data[:64] + len(data).to_bytes(4, "little") + data[-64:]
        if key in seen:
            stats["duplicates"] += 1
            continue
        seen.add(key)
        try:
            clip = decode_clip(data, p.name)
        except MotionError as exc:
            failures.append({"path": str(p), "error": str(exc)})
            continue
        h = clip.header
        stats["decoded"] += 1
        layouts[f"T={h.translation_count} R={h.rotation_count} off={h.data_offset:#x}"] += 1
        frames[len(clip.frames) // 30 * 30] += 1
        total_frames += len(clip.frames)
        for fr in clip.frames:
            stats["delta_frames" if fr.is_delta else "key_frames"] += 1
    return {
        "stats": dict(stats),
        "layouts": dict(layouts),
        "frame_count_buckets_of_30": dict(sorted(frames.items())),
        "total_frames": total_frames,
        "failures": failures,
    }


def dump(clip: Clip, every: int = 10) -> str:
    h = clip.header
    lines = [
        f"clip {clip.name}: {len(clip.frames)} frames ({clip.duration:.2f} s at {FRAME_RATE:g} Hz)",
        f"  data offset {h.data_offset:#x}, length {h.field_04} ticks, flags {h.flags:#06x}, "
        f"channels {h.channel_count}, field_12 {h.field_12}",
        f"  translation bones {h.translation_bones}",
        f"  rotation bones {h.rotation_bones}",
        f"  mask_18 {h.mask_18:#010x}",
    ]
    if h.bit_widths:
        lines.append(f"  bit widths {list(h.bit_widths)}")
    for i, fr in enumerate(clip.frames):
        if i % every and i != len(clip.frames) - 1:
            continue
        root = clip.local_translation(i, 0) if fr.translations else (0.0, 0.0, 0.0)
        plant = ("L" if fr.left_foot_planted else "-") + ("R" if fr.right_foot_planted else "-")
        lines.append(
            f"  f{i:4d} {'D' if fr.is_delta else 'K'} plant={plant} hdr={list(fr.header)} "
            f"root=({root[0]:.2f}, {root[1]:.2f}, {root[2]:.2f})"
        )
    return "\n".join(lines)


# --------------------------------------------------------------------------- glTF


def _append_animation(
    doc: dict,
    binary: bytearray,
    clip: Clip,
    joint_nodes: dict[int, int],
    root_motion: bool = False,
) -> int:
    """Append one glTF animation for ``clip``; ``joint_nodes`` maps bone index to node."""

    def view(payload: bytes) -> int:
        while len(binary) % 4:
            binary.append(0)
        doc.setdefault("bufferViews", []).append(
            {"buffer": 0, "byteOffset": len(binary), "byteLength": len(payload)}
        )
        binary.extend(payload)
        return len(doc["bufferViews"]) - 1

    def accessor(values: list[Sequence[float]], atype: str, minmax: bool = False) -> int:
        flat = [c for v in values for c in v]
        acc: dict = {
            "bufferView": view(struct.pack(f"<{len(flat)}f", *flat)),
            "componentType": 5126,
            "count": len(values),
            "type": atype,
        }
        if minmax:  # spec: min/max must equal the stored float32 values exactly
            stored = struct.unpack(f"<{len(flat)}f", struct.pack(f"<{len(flat)}f", *flat))
            acc["min"] = [min(stored)]
            acc["max"] = [max(stored)]
        doc.setdefault("accessors", []).append(acc)
        return len(doc["accessors"]) - 1

    n = len(clip.frames)
    times = accessor([(i / FRAME_RATE,) for i in range(n)], "SCALAR", minmax=True)
    samplers: list[dict] = []
    channels: list[dict] = []

    def add(node: int, path: str, values: list[Sequence[float]]) -> None:
        out = accessor(values, "VEC4" if path == "rotation" else "VEC3")
        samplers.append({"input": times, "output": out, "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": path}})

    def translation(i: int, slot: int, bone: int) -> tuple[float, float, float]:
        t = clip.local_translation(i, slot)
        if root_motion and bone == 0:  # add the clip-space root trajectory (x, z)
            r = clip.root_position(i)
            return (t[0] + r[0], t[1], t[2] + r[2])
        return t

    for slot, bone in enumerate(clip.header.translation_bones):
        if bone in joint_nodes:
            add(joint_nodes[bone], "translation", [translation(i, slot, bone) for i in range(n)])
    for slot, bone in enumerate(clip.header.rotation_bones):
        if bone in joint_nodes:
            add(joint_nodes[bone], "rotation", [clip.local_rotation(i, slot) for i in range(n)])
    doc.setdefault("animations", []).append(
        {"name": clip.name or "clip", "samplers": samplers, "channels": channels}
    )
    return len(doc["animations"]) - 1


def export_gltf(
    clip: Clip,
    skeleton_path: Path,
    out_path: Path,
    model_path: Path | None = None,
    root_motion: bool = False,
) -> dict:
    """Write ``out_path`` (.gltf + .bin) with the clip as a glTF animation.

    Bones are the ``!skel.o`` skeleton (bone i = mask bit i). With ``model_path``
    the skinned EAGL model is exported first (via ``eagl.export_gltf``) and the
    animation is added to it; otherwise a skeleton-only scene is written.
    """
    from openrugby_tools import eagl  # local import: eagl is large

    skel_asset = eagl.load_asset(skeleton_path)
    if not skel_asset.skeletons:
        raise MotionError(f"{skeleton_path}: no __Skeleton symbol")
    skel = skel_asset.skeletons[0]
    bin_path = out_path.with_suffix(".bin")
    if model_path is not None:
        eagl.export_gltf(eagl.load_asset(model_path), out_path, skeleton=skel)
        doc = json.loads(out_path.read_text())
        binary = bytearray(bin_path.read_bytes()) if bin_path.exists() else bytearray()
    else:
        doc = {"asset": {"version": "2.0"}, "nodes": [], "scenes": [{"nodes": []}], "scene": 0}
        binary = bytearray()
        for bone in skel.bones:
            doc["nodes"].append(
                {
                    "name": bone.name,
                    "translation": list(bone.translation),
                    "rotation": list(bone.rotation),
                }
            )
        for bone in skel.bones:
            if bone.parent >= 0:
                doc["nodes"][bone.parent].setdefault("children", []).append(bone.index)
            else:
                doc["scenes"][0]["nodes"].append(bone.index)
    names = {b.name: b.index for b in skel.bones}
    joint_nodes: dict[int, int] = {}
    for ni, node in enumerate(doc["nodes"]):
        if node.get("name") in names and names[node["name"]] not in joint_nodes:
            joint_nodes[names[node["name"]]] = ni
    _append_animation(doc, binary, clip, joint_nodes, root_motion)
    doc["buffers"] = [{"uri": bin_path.name, "byteLength": len(binary)}]
    doc.setdefault("asset", {})["generator"] = "openrugby_tools.motion"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bin_path.write_bytes(bytes(binary))
    out_path.write_text(json.dumps(doc, indent=1))
    return {"frames": len(clip.frames), "joints_animated": len(joint_nodes)}


# --------------------------------------------------------------------------- CLI


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="openrugby_tools.motion", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("census", help="decode every clip under the given paths")
    c.add_argument("paths", nargs="+", type=Path)
    c.add_argument("--json", type=Path, help="write the full census here")
    d = sub.add_parser("dump", help="print header and sampled frames of clips")
    d.add_argument("paths", nargs="+", type=Path)
    d.add_argument("--every", type=int, default=10)
    g = sub.add_parser("gltf", help="export a clip as a glTF animation")
    g.add_argument("clip", type=Path)
    g.add_argument("--skeleton", type=Path, required=True, help="path to !skel.o")
    g.add_argument("--model", type=Path, help="optional skinned EAGL model (.o)")
    g.add_argument("-o", "--out", type=Path, required=True)
    g.add_argument("--root-motion", action="store_true", help="add the root trajectory")
    args = ap.parse_args(argv)
    if args.cmd == "census":
        result = census(args.paths)
        if args.json:
            args.json.write_text(json.dumps(result, indent=1))
        print(json.dumps({k: v for k, v in result.items() if k != "failures"}, indent=1))
        print(f"failures: {len(result['failures'])}")
        for f in result["failures"][:20]:
            print(f"  {f['path']}: {f['error']}")
        return 1 if result["failures"] else 0
    if args.cmd == "dump":
        rc = 0
        for p in find_clips(args.paths):
            try:
                print(dump(load_clip(p), args.every))
            except MotionError as exc:
                print(f"{p}: {exc}", file=sys.stderr)
                rc = 1
        return rc
    summary = export_gltf(
        load_clip(args.clip), args.skeleton, args.out, args.model, args.root_motion
    )
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
