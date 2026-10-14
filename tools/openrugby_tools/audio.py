"""EA ``SCHl`` audio stream header parsing and OGG Vorbis conversion (stdlib only).

An ``SCHl`` stream begins with a 4-byte magic, a little-endian uint32 total
header size (this value also marks the offset of the following ``SCCl`` chunk),
and then one of two patch blocks:

* ``PT\\0\\0`` (Rugby 08 ``chants.big``, ``aems.big``): items start at offset 12.
* ``GSTR`` followed by a 4-byte version word (``anthems``, ``music``, ``pamusic``,
  ``ref_eng``, ``dat_eng``): items start at offset 16.

Each patch item is ``tag(uint8) len(uint8) value(len bytes, big-endian)``. Two
single-byte markers are skipped: ``0xFD`` (precedes the codec item) and ``0x00``
(padding). ``0xFF`` terminates the list. Observed tags (see docs/re/03-audio.md):

* ``0x80`` codec: 1, 2, 3 map to ``adpcm_ea_r1/r2/r3`` (confirmed by ffmpeg).
* ``0x82`` channel count (absent in some streams).
* ``0x84`` sample rate in Hz.
* ``0x85`` sample count per channel (matches decoded length to within ~0.1%).
* ``0xA0`` unknown "revision2"; ffmpeg rejects streams where it is 4.
* ``0x06``, ``0x0B``, ``0xA0`` other values: recorded raw, meaning unverified.

Conversion shells out to ffmpeg using the ``ea`` demuxer. ffmpeg is never
required for header parsing.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import struct
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

MAGIC = b"SCHl"
PT_MARKER = b"PT\x00\x00"
GSTR_MARKER = b"GSTR"
DEFAULT_WORKERS = 8
DEFAULT_QUALITY = 5

TAG_CODEC = 0x80
TAG_CHANNELS = 0x82
TAG_RATE = 0x84
TAG_SAMPLES = 0x85
TAG_REVISION2 = 0xA0
_SKIP_MARKERS = frozenset({0x00, 0xFD})
_END_TAG = 0xFF


class SchlError(ValueError):
    """Raised when a byte string is not a parseable ``SCHl`` header."""


@dataclass(frozen=True)
class SchlHeader:
    """Metadata decoded from an ``SCHl`` patch block.

    ``codec``, ``channels``, ``sample_rate`` and ``sample_count`` are ``None``
    when the stream does not carry the corresponding tag. ``tags`` maps every
    tag seen to the list of values it carried, so unknown tags are not lost.
    """

    variant: str
    header_size: int
    codec: int | None
    channels: int | None
    sample_rate: int | None
    sample_count: int | None
    revision2: int | None
    tags: dict[int, list[int]] = field(default_factory=dict)

    @property
    def duration_s(self) -> float | None:
        """Playback length in seconds, from the header sample count and rate."""
        if not self.sample_count or not self.sample_rate:
            return None
        return self.sample_count / self.sample_rate

    def as_dict(self) -> dict[str, Any]:
        """JSON-friendly representation (tags keyed by hex string)."""
        data = asdict(self)
        data["tags"] = {f"0x{t:02X}": v for t, v in sorted(self.tags.items())}
        data["duration_s"] = self.duration_s
        return data


def _read_items(data: bytes, pos: int, end: int) -> dict[int, list[int]]:
    tags: dict[int, list[int]] = {}
    while pos < end:
        tag = data[pos]
        if tag == _END_TAG:
            break
        if tag in _SKIP_MARKERS:
            pos += 1
            continue
        if pos + 2 > end:
            break
        length = data[pos + 1]
        value_end = pos + 2 + length
        if value_end > end:
            break
        tags.setdefault(tag, []).append(int.from_bytes(data[pos + 2 : value_end], "big"))
        pos = value_end
    return tags


def parse_schl_header(data: bytes) -> SchlHeader:
    """Parse the ``SCHl`` patch block at the start of ``data``.

    Only the leading header is read; ``data`` may be the whole stream or just
    its first few hundred bytes.

    Raises:
        SchlError: if the magic, size field or patch marker is missing.
    """
    if len(data) < 12 or data[:4] != MAGIC:
        raise SchlError("missing SCHl magic")
    (header_size,) = struct.unpack_from("<I", data, 4)
    marker = data[8:12]
    if marker == PT_MARKER:
        variant, pos = "PT", 12
    elif marker == GSTR_MARKER:
        variant, pos = "GSTR", 16
    else:
        raise SchlError(f"unknown patch marker {marker!r}")
    end = min(header_size, len(data))
    if end < pos:
        raise SchlError(f"header size {header_size} too small for {variant} block")
    tags = _read_items(data, pos, end)

    def first(tag: int) -> int | None:
        values = tags.get(tag)
        return values[0] if values else None

    return SchlHeader(
        variant=variant,
        header_size=header_size,
        codec=first(TAG_CODEC),
        channels=first(TAG_CHANNELS),
        sample_rate=first(TAG_RATE),
        sample_count=first(TAG_SAMPLES),
        revision2=first(TAG_REVISION2),
        tags=tags,
    )


def is_schl_file(path: Path) -> bool:
    """True if the file starts with the ``SCHl`` magic."""
    try:
        with path.open("rb") as fh:
            return fh.read(4) == MAGIC
    except OSError:
        return False


def find_schl_files(src: Path) -> list[Path]:
    """Return ``SCHl`` files under ``src`` (or ``src`` itself), sorted."""
    if src.is_file():
        return [src] if is_schl_file(src) else []
    return sorted(p for p in src.rglob("*") if p.is_file() and is_schl_file(p))


@dataclass
class ConversionResult:
    """Outcome of converting one ``SCHl`` file."""

    source: str
    output: str | None
    ok: bool
    error: str | None
    header: dict[str, Any]
    duration: float | None = None
    channels: int | None = None
    rate: int | None = None
    output_bytes: int | None = None


def _ffmpeg_error(stderr: str) -> str:
    lines = [ln.strip() for ln in stderr.splitlines() if ln.strip()]
    return lines[-1] if lines else "ffmpeg failed with no diagnostic output"


def probe_ogg(path: Path) -> dict[str, Any]:
    """Read duration, channels and rate of an output file via ffprobe."""
    proc = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration:stream=codec_name,channels,sample_rate",
            "-of",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    doc = json.loads(proc.stdout)
    stream = doc["streams"][0]
    return {
        "duration": float(doc["format"]["duration"]),
        "channels": int(stream["channels"]),
        "rate": int(stream["sample_rate"]),
        "codec": stream["codec_name"],
    }


def convert_one(
    source: Path,
    src_root: Path,
    out_root: Path,
    quality: int = DEFAULT_QUALITY,
) -> ConversionResult:
    """Convert one ``SCHl`` file to OGG Vorbis under ``out_root``.

    The output mirrors the source path relative to ``src_root``. A partial
    output is removed if ffmpeg fails. The header is always parsed, even when
    conversion fails, so the index still records what the stream declares.
    """
    rel = source.relative_to(src_root) if source.is_relative_to(src_root) else Path(source.name)
    rel_str = rel.as_posix()
    try:
        head = parse_schl_header(source.read_bytes()[:4096])
        header: dict[str, Any] = head.as_dict()
    except (OSError, SchlError) as exc:
        return ConversionResult(rel_str, None, False, f"header: {exc}", {})

    out_path = (out_root / rel).with_suffix(".ogg")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-y",
        "-f",
        "ea",
        "-i",
        str(source),
        "-c:a",
        "libvorbis",
        "-q:a",
        str(quality),
        "-f",
        "ogg",
        str(out_path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        out_path.unlink(missing_ok=True)
        return ConversionResult(rel_str, None, False, _ffmpeg_error(proc.stderr), header)

    try:
        info = probe_ogg(out_path)
    except (subprocess.CalledProcessError, KeyError, IndexError, ValueError) as exc:
        return ConversionResult(rel_str, out_path.as_posix(), False, f"ffprobe: {exc}", header)
    return ConversionResult(
        source=rel_str,
        output=out_path.relative_to(out_root).as_posix(),
        ok=True,
        error=None,
        header=header,
        duration=info["duration"],
        channels=info["channels"],
        rate=info["rate"],
        output_bytes=out_path.stat().st_size,
    )


def convert_tree(
    src: Path,
    out: Path,
    workers: int = DEFAULT_WORKERS,
    quality: int = DEFAULT_QUALITY,
) -> dict[str, Any]:
    """Convert every ``SCHl`` file under ``src`` and write ``out/index.json``.

    Returns the index document (also written to disk). Non-``SCHl`` files are
    ignored, so ``SCORE_*.dat`` zero-filled members and ABKC/MOIR files are skipped.

    Raises:
        RuntimeError: if ffmpeg or ffprobe is not on PATH.
    """
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        raise RuntimeError("ffmpeg and ffprobe must be on PATH")
    src = src.resolve()
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    files = find_schl_files(src)
    root = src if src.is_dir() else src.parent
    started = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(lambda f: convert_one(f, root, out, quality), files))
    elapsed = time.monotonic() - started
    results.sort(key=lambda r: r.source)
    ok = [r for r in results if r.ok]
    summary: dict[str, Any] = {
        "total": len(results),
        "ok": len(ok),
        "failed": len(results) - len(ok),
        "total_duration_s": round(sum(r.duration or 0.0 for r in ok), 3),
        "output_bytes": sum(r.output_bytes or 0 for r in ok),
        "elapsed_s": round(elapsed, 2),
        "workers": workers,
        "quality": quality,
    }
    index: dict[str, Any] = {
        "source_root": str(src),
        "summary": summary,
        "entries": [asdict(r) for r in results],
    }
    tmp = out / "index.json.tmp"
    tmp.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, out / "index.json")
    return index


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="openrugby_tools.audio")
    sub = parser.add_subparsers(dest="cmd", required=True)
    conv = sub.add_parser("convert", help="convert SCHl streams to OGG Vorbis")
    conv.add_argument("src", type=Path, help="directory (walked recursively) or one file")
    conv.add_argument("out", type=Path, help="output directory (index.json is written here)")
    conv.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    conv.add_argument("-q", "--quality", type=int, default=DEFAULT_QUALITY)
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code."""
    args = _build_parser().parse_args(argv)
    if args.cmd == "convert":
        if not args.src.exists():
            print(f"error: {args.src} does not exist", file=sys.stderr)
            return 2
        index = convert_tree(args.src, args.out, workers=args.workers, quality=args.quality)
        print(json.dumps(index["summary"], indent=2))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
