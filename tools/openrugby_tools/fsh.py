"""EA SHPI / FSH texture container: parser, pixel decoders and PNG conversion.

Layout (little-endian)::

    "SHPI" u32 total_size u32 entry_count char[4] directory_id
    entry_count * { char[4] tag, u32 offset }      # offset from file start

Each bitmap entry starts with a 16-byte header::

    u32 code_and_attach   # low byte = format code, high 24 bits = offset (from the
                          # entry start) to the next attachment block, 0 if none
    u16 width, u16 height
    u16 x_centre, u16 y_centre
    u16 x_pos, u16 y_pos  # the top 4 bits of each hold mipmap count / flags

Pixel data follows the header. Attachments are ``u32 code_and_next`` blocks
(code 0x70 name, 0x2A/0x2D/0x24/0x22/0x23 palettes, ...) chained by the same
"next offset" convention.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import time
from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path

__all__ = [
    "FORMATS",
    "Attachment",
    "FshBitmap",
    "FshError",
    "FshFile",
    "decode_bitmap",
    "find_fsh_sources",
    "level_size",
    "main",
    "parse_fsh",
]

#: Format codes observed in Rugby 08 (see docs/re/02-fsh-textures.md) -> description.
FORMATS: dict[int, str] = {
    0x60: "DXT1 (BC1)",
    0x62: "DXT5 (BC3)",
    0x7D: "ARGB8888 (BGRA byte order)",
    0x7F: "RGB888 (BGR byte order)",
}
_DXT_BLOCK_BYTES = {0x60: 8, 0x62: 16}
_FOURCC = {0x60: b"DXT1", 0x62: b"DXT5"}
_RAW_MODE = {0x7D: ("RGBA", "BGRA", 4), 0x7F: ("RGB", "BGR", 3)}


class FshError(ValueError):
    """Raised when data is not a decodable SHPI container."""


@dataclass(frozen=True)
class Attachment:
    code: int
    data: bytes


@dataclass
class FshBitmap:
    tag: str
    code: int
    width: int
    height: int
    x_centre: int
    y_centre: int
    x_pos: int
    y_pos: int
    mip_count: int
    offset: int
    data_end: int
    attachments: list[Attachment] = field(default_factory=list)

    @property
    def name(self) -> str | None:
        for a in self.attachments:
            if a.code == 0x70:
                return a.data.split(b"\0", 1)[0].decode("latin-1") or None
        return None


@dataclass
class FshFile:
    directory_id: str
    declared_size: int
    bitmaps: list[FshBitmap]
    raw: bytes


def parse_fsh(data: bytes) -> FshFile:
    """Parse the SHPI directory and bitmap headers / attachments."""
    if len(data) < 16 or data[:4] != b"SHPI":
        raise FshError("missing SHPI magic")
    size, count = struct.unpack_from("<II", data, 4)
    dir_id = data[12:16].decode("latin-1")
    if 16 + 8 * count > len(data):
        raise FshError("directory exceeds file")
    entries = [
        (
            data[16 + 8 * i : 20 + 8 * i].decode("latin-1"),
            struct.unpack_from("<I", data, 20 + 8 * i)[0],
        )
        for i in range(count)
    ]
    offsets = sorted({o for _, o in entries} | {len(data)})
    bitmaps: list[FshBitmap] = []
    for tag, off in entries:
        if off + 16 > len(data):
            raise FshError(f"entry {tag!r} header out of range")
        word, w, h, xc, yc, xp, yp = struct.unpack_from("<IHHHHHH", data, off)
        code, attach = word & 0xFF, word >> 8
        nxt = next((o for o in offsets if o > off), len(data))
        # The mipmap count (extra levels beyond level 0) lives in the top nibble of y_pos.
        bm = FshBitmap(tag, code, w, h, xc, yc, xp & 0x0FFF, yp & 0x0FFF, yp >> 12, off, nxt)
        bm.data_end = off + attach if attach else nxt
        # Attachment chain: each block is u32 (code | next<<8) where next is a
        # relative byte count to the following block (0 = last block).
        pos = off + attach if attach else 0
        guard = 0
        while pos and pos + 4 <= len(data) and guard < 16:
            guard += 1
            w2 = struct.unpack_from("<I", data, pos)[0]
            acode, anext = w2 & 0xFF, w2 >> 8
            end = pos + anext if anext else nxt
            bm.attachments.append(Attachment(acode, data[pos + 4 : max(pos + 4, min(end, nxt))]))
            pos = pos + anext if anext else 0
        bitmaps.append(bm)
    return FshFile(dir_id, size, bitmaps, data)


def level_size(code: int, width: int, height: int) -> int:
    """Byte size of one mip level for format ``code``."""
    if code in _DXT_BLOCK_BYTES:
        return max(1, (width + 3) // 4) * max(1, (height + 3) // 4) * _DXT_BLOCK_BYTES[code]
    if code in _RAW_MODE:
        return width * height * _RAW_MODE[code][2]
    raise FshError(f"unsupported format code 0x{code:02X}")


def _image_cls():
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise FshError("Pillow is required (pip install '.[tools]')") from exc
    return Image


def _decode_level(code: int, width: int, height: int, data: bytes):
    """Decode one mip level to a ``PIL.Image`` (RGBA or RGB)."""
    Image = _image_cls()
    need = level_size(code, width, height)
    if len(data) < need:
        raise FshError(f"truncated pixel data: need {need}, have {len(data)}")
    data = data[:need]
    if code in _RAW_MODE:
        mode, raw, _ = _RAW_MODE[code]
        return Image.frombytes(mode, (width, height), data, "raw", raw)
    header = struct.pack(
        "<4s7I44s8I",
        b"DDS ",
        124,
        0x1 | 0x2 | 0x4 | 0x1000 | 0x80000,
        height,
        width,
        need,
        0,
        0,
        b"\0" * 44,
        32,
        4,
        int.from_bytes(_FOURCC[code], "little"),
        0,
        0,
        0,
        0,
        0x1000,
    )
    header += b"\0" * (128 - len(header))
    import io

    img = Image.open(io.BytesIO(header + data))
    img.load()
    return img.convert("RGBA")


def decode_bitmap(fsh: FshFile, bitmap: FshBitmap, *, mips: bool = False) -> list:
    """Decode ``bitmap`` to PIL images: level 0 only, or all levels if ``mips``."""
    if bitmap.width == 0 or bitmap.height == 0:
        raise FshError("zero-sized bitmap")
    pos = bitmap.offset + 16
    end = bitmap.data_end
    w, h = bitmap.width, bitmap.height
    images = []
    for level in range(bitmap.mip_count + 1 if mips else 1):
        size = level_size(bitmap.code, w, h)
        if pos + size > end + 16:
            if level == 0:
                raise FshError("pixel data overruns entry")
            break
        images.append(_decode_level(bitmap.code, w, h, fsh.raw[pos : pos + size]))
        pos += size
        w, h = max(1, w // 2), max(1, h // 2)
    return images


def find_fsh_sources(root: Path) -> Iterator[tuple[Path, Path]]:
    """Yield ``(logical_path, payload_path)`` for every SHPI member under ``root``.

    ``payload_path`` is the ``.unpacked`` sibling when present (the RefPack-decoded
    bytes), otherwise the member itself. Members are recognised by magic, not name.
    """
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix == ".unpacked":
            continue
        if "textures" in path.relative_to(root).parts[:1]:
            continue
        payload = path.with_name(path.name + ".unpacked")
        payload = payload if payload.is_file() else path
        with payload.open("rb") as fh:
            if fh.read(4) == b"SHPI":
                yield path, payload


def _safe(name: str) -> str:
    out = "".join(c if c.isalnum() or c in "_-." else "_" for c in name.strip())
    return out.strip(".") or "_"


def _entry_names(fsh: FshFile) -> list[str]:
    """Unique, filesystem-safe output stem per bitmap (name attachment, else tag)."""
    used: Counter[str] = Counter()
    names = []
    for bm in fsh.bitmaps:
        base = _safe(bm.name or bm.tag)
        used[base.lower()] += 1
        n = used[base.lower()]
        names.append(base if n == 1 else f"{base}_{n}")
    return names


def _read(payload: Path) -> bytes:
    return payload.read_bytes()


def _convert_one(args: tuple[str, str, str, bool]) -> dict:
    logical, payload, out_root, mips = args
    rec: dict = {"source": logical, "bitmaps": [], "error": None}
    try:
        fsh = parse_fsh(_read(Path(payload)))
    except (FshError, struct.error, OSError) as exc:
        rec["error"] = str(exc)
        return rec
    rec["directory_id"] = fsh.directory_id
    out_dir = Path(out_root) / logical
    names = _entry_names(fsh)
    for bm, stem in zip(fsh.bitmaps, names, strict=True):
        item = {
            "tag": bm.tag,
            "name": bm.name,
            "format": f"0x{bm.code:02X}",
            "width": bm.width,
            "height": bm.height,
            "mips": bm.mip_count,
            "centre": [bm.x_centre, bm.y_centre],
            "attachments": [f"0x{a.code:02X}" for a in bm.attachments],
            "files": [],
            "error": None,
        }
        try:
            images = decode_bitmap(fsh, bm, mips=mips)
            out_dir.mkdir(parents=True, exist_ok=True)
            for i, img in enumerate(images):
                fname = f"{stem}.png" if i == 0 else f"{stem}_mip{i}.png"
                img.save(out_dir / fname)
                item["files"].append(f"{logical}/{fname}")
        except (FshError, struct.error, OSError, ValueError) as exc:
            item["error"] = str(exc)
        rec["bitmaps"].append(item)
    return rec


def _census_one(args: tuple[str, str]) -> dict:
    logical, payload = args
    try:
        data = _read(Path(payload))
        fsh = parse_fsh(data)
    except (FshError, struct.error, OSError) as exc:
        return {"source": logical, "error": str(exc)}
    return {
        "source": logical,
        "error": None,
        "directory_id": fsh.directory_id,
        "size_ok": fsh.declared_size == len(data),
        "bitmaps": [
            {
                "code": bm.code,
                "w": bm.width,
                "h": bm.height,
                "mips": bm.mip_count,
                "att": [a.code for a in bm.attachments],
            }
            for bm in fsh.bitmaps
        ],
    }


def _run_pool(func, jobs: list, workers: int) -> list:
    if workers <= 1 or len(jobs) < 8:
        return [func(j) for j in jobs]
    import multiprocessing

    with multiprocessing.Pool(workers) as pool:
        return pool.map(func, jobs, chunksize=32)


def _cmd_census(ns: argparse.Namespace) -> int:
    root = Path(ns.root)
    t0 = time.perf_counter()
    jobs = [(str(p.relative_to(root)), str(q)) for p, q in find_fsh_sources(root)]
    results = _run_pool(_census_one, jobs, ns.jobs)
    fmt: Counter[str] = Counter()
    mips: Counter[str] = Counter()
    att: Counter[str] = Counter()
    dirs: Counter[str] = Counter()
    sizes: Counter[str] = Counter()
    failures = []
    nbitmaps = 0
    for r in results:
        if r["error"]:
            failures.append((r["source"], r["error"]))
            continue
        dirs[r["directory_id"]] += 1
        sizes["size_matches" if r["size_ok"] else "size_mismatch"] += 1
        for b in r["bitmaps"]:
            nbitmaps += 1
            key = f"0x{b['code']:02X}"
            fmt[key] += 1
            mips[f"{key} mips={b['mips']}"] += 1
            for a in b["att"]:
                att[f"0x{a:02X}"] += 1
    print(f"files: {len(jobs)}  bitmaps: {nbitmaps}  failures: {len(failures)}")
    for title, ctr in (
        ("format codes", fmt),
        ("mip counts", mips),
        ("attachments", att),
        ("directory ids", dirs),
        ("declared size", sizes),
    ):
        print(f"\n{title}:")
        for k, v in sorted(ctr.items()):
            known = ""
            if title == "format codes":
                known = f"  {FORMATS.get(int(k, 16), 'UNSUPPORTED')}"
            print(f"  {k}: {v}{known}")
    for src, err in failures[:20]:
        print(f"FAIL {src}: {err}")
    print(f"\nelapsed: {time.perf_counter() - t0:.1f}s")
    return 0


def _cmd_convert(ns: argparse.Namespace) -> int:
    root = Path(ns.root)
    out = Path(ns.out)
    t0 = time.perf_counter()
    out.mkdir(parents=True, exist_ok=True)
    jobs = [
        (str(p.relative_to(root)), str(q), str(out), ns.mips) for p, q in find_fsh_sources(root)
    ]
    if ns.limit:
        jobs = jobs[: ns.limit]
    results = _run_pool(_convert_one, jobs, ns.jobs)
    ok = bad = 0
    fmt_ok: Counter[str] = Counter()
    reasons: Counter[str] = Counter()
    for r in results:
        if r["error"]:
            bad += 1
            reasons[r["error"]] += 1
        for b in r["bitmaps"]:
            if b["error"]:
                bad += 1
                reasons[f"{b['format']}: {b['error']}"] += 1
            else:
                ok += 1
                fmt_ok[b["format"]] += 1
    (out / "index.json").write_text(
        json.dumps({"textures": results}, indent=1, sort_keys=True), encoding="utf-8"
    )
    print(f"sources: {len(results)}  converted: {ok}  failed: {bad}")
    for k, v in sorted(fmt_ok.items()):
        print(f"  {k}: {v}")
    for k, v in reasons.most_common(20):
        print(f"FAIL x{v}: {k}")
    print(f"elapsed: {time.perf_counter() - t0:.1f}s")
    return 1 if bad else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m openrugby_tools.fsh", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("census", "convert"):
        sp = sub.add_parser(name)
        sp.add_argument("--root", default="extracted", help="tree to scan (default: extracted)")
        sp.add_argument("--jobs", type=int, default=8, help="worker processes")
        if name == "convert":
            sp.add_argument("--out", default="extracted/textures")
            sp.add_argument("--mips", action="store_true", help="also write mip levels")
            sp.add_argument("--limit", type=int, default=0, help="convert only first N sources")
    ns = ap.parse_args(argv)
    return _cmd_census(ns) if ns.cmd == "census" else _cmd_convert(ns)


if __name__ == "__main__":
    sys.exit(main())
