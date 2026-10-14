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
* ``0xA0`` "revision2" in ffmpeg, "codec2" in vgmstream: 4 = EA MicroTalk
  (speech), 9 = signed 8-bit PCM. ffmpeg rejects both; vgmstream decodes them.
* ``0x06``, ``0x0B`` and others: recorded raw, meaning unverified.

Conversion shells out to ffmpeg using the ``ea`` demuxer. Streams that carry
``0xA0``, or that ffmpeg fails on, are decoded to WAV with ``vgmstream-cli``
(dev-time tool, never shipped) and then encoded to OGG with ffmpeg. ffmpeg is
never required for header parsing.
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
import tempfile
import time
import warnings
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

MAGIC = b"SCHl"
PT_MARKER = b"PT\x00\x00"
GSTR_MARKER = b"GSTR"
DEFAULT_WORKERS = 8
DEFAULT_QUALITY = 5
VGMSTREAM_ENV = "OPENRUGBY_VGMSTREAM"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VGMSTREAM = REPO_ROOT / ".omc" / "research" / "bin" / "vgmstream-cli"

TAG_CODEC = 0x80
TAG_CHANNELS = 0x82
TAG_RATE = 0x84
TAG_SAMPLES = 0x85
TAG_REVISION2 = 0xA0
SCEL_MAGIC = b"SCEl"
SCEL_SIZE = 8
STREAM_ALIGN = 256
HDR_BODY_START = 14
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


def find_vgmstream(explicit: Path | str | None = None) -> Path | None:
    """Locate ``vgmstream-cli``: explicit path, ``$OPENRUGBY_VGMSTREAM``, repo default, PATH.

    An explicit path or env value that does not exist yields ``None`` rather than
    falling through, so a typo is not silently masked by another binary.
    """
    chosen = explicit or os.environ.get(VGMSTREAM_ENV)
    if chosen:
        path = Path(chosen)
        return path if path.is_file() else None
    if DEFAULT_VGMSTREAM.is_file():
        return DEFAULT_VGMSTREAM
    found = shutil.which("vgmstream-cli")
    return Path(found) if found else None


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
    decoder: str | None = None
    container: str | None = None
    stream_index: int | None = None
    hdr_count: int | None = None
    hdr_offset_match: bool | None = None


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


def _encode_with_ffmpeg(source: Path, out_path: Path, quality: int) -> str | None:
    """Decode ``source`` and encode OGG with ffmpeg. Returns an error string or ``None``."""
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
    return None if proc.returncode == 0 else _ffmpeg_error(proc.stderr)


def _encode_with_vgmstream(
    source: Path, out_path: Path, quality: int, vgmstream: Path
) -> str | None:
    """Decode with ``vgmstream-cli`` to WAV, then encode OGG with ffmpeg.

    vgmstream picks its parser by file extension and rejects ``.dat``, so the
    source is symlinked as ``.snd`` inside a private temp directory.
    """
    with tempfile.TemporaryDirectory(prefix="openrugby-vgm-") as tmp:
        link = Path(tmp) / "in.snd"
        wav = Path(tmp) / "out.wav"
        try:
            link.symlink_to(source.resolve())
        except OSError:
            shutil.copyfile(source, link)
        proc = subprocess.run(
            [str(vgmstream), "-o", str(wav), str(link)],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0 or not wav.exists():
            lines = [ln.strip() for ln in (proc.stderr or proc.stdout).splitlines() if ln.strip()]
            return f"vgmstream: {lines[-1] if lines else 'failed with no diagnostic output'}"
        proc = subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-nostdin",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(wav),
                "-c:a",
                "libvorbis",
                "-q:a",
                str(quality),
                "-f",
                "ogg",
                str(out_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        return None if proc.returncode == 0 else _ffmpeg_error(proc.stderr)


def _encode_source(
    source: Path, out_path: Path, head: SchlHeader, quality: int, vgmstream: Path | None
) -> tuple[str, str | None]:
    """Encode one ``SCHl`` file to OGG.

    Returns ``(decoder, error)``; ``error`` is None on success.
    """
    decoder = "ffmpeg"
    error: str | None = None
    # 0xA0 streams are known to fail in ffmpeg, so skip straight to vgmstream.
    if head.revision2 is None or vgmstream is None:
        error = _encode_with_ffmpeg(source, out_path, quality)
    else:
        error = "skipped ffmpeg: header carries 0xA0"
    if error is not None and vgmstream is not None:
        decoder = "vgmstream"
        error = _encode_with_vgmstream(source, out_path, quality, vgmstream)
    return decoder, error


def _finish_ogg(
    out_path: Path, decoder: str, header: dict[str, Any], rel_str: str, out_root: Path
) -> ConversionResult:
    """Probe a freshly written OGG and build its result record."""
    try:
        info = probe_ogg(out_path)
    except (subprocess.CalledProcessError, KeyError, IndexError, ValueError) as exc:
        return ConversionResult(
            rel_str, out_path.as_posix(), False, f"ffprobe: {exc}", header, decoder=decoder
        )
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
        decoder=decoder,
    )


def convert_one(
    source: Path,
    src_root: Path,
    out_root: Path,
    quality: int = DEFAULT_QUALITY,
    vgmstream: Path | None = None,
) -> ConversionResult:
    """Convert one ``SCHl`` file to OGG Vorbis under ``out_root``.

    ``vgmstream`` is the path to ``vgmstream-cli`` (``None`` disables the
    fallback; see :func:`find_vgmstream`). The output mirrors the source path
    relative to ``src_root``. A partial output is removed on failure. The header is
    always parsed, even when conversion fails, so the index still records what the
    stream declares.
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
    decoder, error = _encode_source(source, out_path, head, quality, vgmstream)
    if error is not None:
        out_path.unlink(missing_ok=True)
        return ConversionResult(rel_str, None, False, error, header, decoder=decoder)
    return _finish_ogg(out_path, decoder, header, rel_str, out_root)


def find_stream_starts(data: bytes) -> list[int]:
    """Byte offsets of every ``SCHl`` magic that sits on a 256-byte boundary.

    Primary split method for ``dat_eng`` containers. Zero padding before the first
    stream (``SCORE_*``) is skipped because only aligned magics are returned.
    """
    starts: list[int] = []
    pos = data.find(MAGIC)
    while pos >= 0:
        if pos % STREAM_ALIGN == 0:
            starts.append(pos)
        pos = data.find(MAGIC, pos + 1)
    return starts


def _stream_end(data: bytes, start: int, next_start: int | None) -> int:
    """End of the stream beginning at ``start``.

    The stream ends after its ``SCEl`` end chunk (8 bytes) when one lies before the
    next stream; otherwise it runs to the next start with trailing zeros removed.
    """
    limit = next_start if next_start is not None else len(data)
    scel = data.rfind(SCEL_MAGIC, start, limit)
    if scel >= 0 and limit - scel >= SCEL_SIZE:
        (size,) = struct.unpack_from("<I", data, scel + 4)
        if size == SCEL_SIZE:
            return scel + SCEL_SIZE
    return start + len(data[start:limit].rstrip(b"\0"))


def hdr_offsets_match(starts: list[int], hdr: bytes) -> bool:
    """Cross-check scanned stream starts against a ``hdr_eng`` record.

    The record's byte 5 must equal the number of scanned streams, and the low byte
    of each start offset (in 256-byte units) for streams 2..N must occur in the
    record body in the same order. The high byte of each offset is not decoded
    (see docs/re/03-audio.md), so this is a partial check, not a full one.
    """
    if len(hdr) < 6 or hdr[5] != len(starts):
        return False
    pos = HDR_BODY_START
    for start in starts[1:]:
        low = bytes([(start // STREAM_ALIGN) & 0xFF])
        found = hdr.find(low, pos)
        if found < 0:
            return False
        pos = found + 1
    return True


def split_schl_container(data: bytes, hdr: bytes | None) -> list[tuple[int, bytes]]:
    """Split a concatenated ``SCHl`` container into ``(index, stream_bytes)`` pairs.

    Stream starts come from :func:`find_stream_starts`. When ``hdr`` is given it is
    checked with :func:`hdr_offsets_match`; a disagreement emits a ``UserWarning``
    but the scanned streams are still returned, because the scan is the authority
    (see the KNOCK_ON_DROP_PUNT note in docs/re/03-audio.md). Index 0 is the first
    stream in the container.
    """
    starts = find_stream_starts(data)
    if hdr is not None and not hdr_offsets_match(starts, hdr):
        warnings.warn(
            f"hdr disagrees with scanned starts (hdr count {hdr[5] if len(hdr) > 5 else '?'},"
            f" scanned {len(starts)})",
            UserWarning,
            stacklevel=2,
        )
    streams: list[tuple[int, bytes]] = []
    for idx, start in enumerate(starts):
        next_start = starts[idx + 1] if idx + 1 < len(starts) else None
        end = _stream_end(data, start, next_start)
        streams.append((idx, data[start:end]))
    return streams


def convert_container(
    path: Path,
    src_root: Path,
    out_root: Path,
    hdr_path: Path | None,
    quality: int = DEFAULT_QUALITY,
    vgmstream: Path | None = None,
) -> list[ConversionResult]:
    """Split one container member and convert each stream to ``<out>/<stem>/<NN>.ogg``.

    Any single-stream ``<stem>.ogg`` left from an earlier run is removed, since the
    per-stream directory replaces it. Returns one result per scanned stream, or one
    failed result when the container holds no aligned ``SCHl`` at all.
    """
    rel = path.relative_to(src_root)
    container = rel.as_posix()
    stem_dir = out_root / rel.with_suffix("")
    (out_root / rel).with_suffix(".ogg").unlink(missing_ok=True)
    data = path.read_bytes()
    hdr = hdr_path.read_bytes() if hdr_path is not None and hdr_path.is_file() else None
    starts = find_stream_starts(data)
    hdr_count = hdr[5] if hdr is not None and len(hdr) > 5 else None
    if not starts:
        return [
            ConversionResult(
                container,
                None,
                False,
                "no SCHl at a 256-byte offset",
                {},
                container=container,
                stream_index=None,
                hdr_count=hdr_count,
                hdr_offset_match=None,
            )
        ]
    match = hdr_offsets_match(starts, hdr) if hdr is not None else None
    stem_dir.mkdir(parents=True, exist_ok=True)
    results: list[ConversionResult] = []
    for idx, stream in split_schl_container(data, hdr):
        stream_rel = f"{rel.with_suffix('').as_posix()}/{idx:02d}"
        out_path = out_root / f"{stream_rel}.ogg"
        try:
            head = parse_schl_header(stream[:4096])
            header: dict[str, Any] = head.as_dict()
        except SchlError as exc:
            results.append(
                ConversionResult(
                    stream_rel,
                    None,
                    False,
                    f"header: {exc}",
                    {},
                    container=container,
                    stream_index=idx,
                    hdr_count=hdr_count,
                    hdr_offset_match=match,
                )
            )
            continue
        with tempfile.TemporaryDirectory(prefix="openrugby-stream-") as tmp:
            tmp_src = Path(tmp) / "stream.snd"
            tmp_src.write_bytes(stream)
            decoder, error = _encode_source(tmp_src, out_path, head, quality, vgmstream)
            if error is not None:
                out_path.unlink(missing_ok=True)
                result = ConversionResult(stream_rel, None, False, error, header, decoder=decoder)
            else:
                result = _finish_ogg(out_path, decoder, header, stream_rel, out_root)
        result.source = f"{container}#{idx:02d}"
        result.container = container
        result.stream_index = idx
        result.hdr_count = hdr_count
        result.hdr_offset_match = match
        results.append(result)
    return results


def _entry(result: ConversionResult) -> dict[str, Any]:
    """Index record. Container fields are emitted only for container-mode results."""
    data = asdict(result)
    if result.container is None:
        for key in ("container", "stream_index", "hdr_count", "hdr_offset_match"):
            data.pop(key)
    return data


def convert_tree(
    src: Path,
    out: Path,
    workers: int = DEFAULT_WORKERS,
    quality: int = DEFAULT_QUALITY,
    vgmstream: Path | None = None,
    hdr_dir: Path | None = None,
) -> dict[str, Any]:
    """Convert every ``SCHl`` file under ``src`` and write ``out/index.json``.

    Returns the index document (also written to disk). Non-``SCHl`` files are
    ignored, so ``SCORE_*.dat`` zero-filled members and ABKC/MOIR files are skipped.

    With ``hdr_dir`` set, ``src`` is treated as a directory of ``dat`` containers:
    each ``<stem>.dat`` is split into its ``SCHl`` streams (see
    :func:`convert_container`) and the paired ``<hdr_dir>/<stem>.hdr`` is used as the
    cross-check. Each stream becomes ``<out>/<stem>/<NN>.ogg``.

    Raises:
        RuntimeError: if ffmpeg or ffprobe is not on PATH.
    """
    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        raise RuntimeError("ffmpeg and ffprobe must be on PATH")
    src = src.resolve()
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    root = src if src.is_dir() else src.parent
    started = time.monotonic()
    if hdr_dir is not None:
        hdr_dir = hdr_dir.resolve()
        containers = sorted(p for p in src.rglob("*.dat") if p.is_file())
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            per_container = list(
                pool.map(
                    lambda f: convert_container(
                        f, root, out, hdr_dir / (f.stem + ".hdr"), quality, vgmstream
                    ),
                    containers,
                )
            )
        results = [r for group in per_container for r in group]
    else:
        files = find_schl_files(src)
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            results = list(pool.map(lambda f: convert_one(f, root, out, quality, vgmstream), files))
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
        "vgmstream": str(vgmstream) if vgmstream else None,
        "by_decoder": {d: sum(1 for r in ok if r.decoder == d) for d in ("ffmpeg", "vgmstream")},
    }
    if hdr_dir is not None:
        containers = {r.container for r in results if r.container}
        summary.update(
            {
                "mode": "containers",
                "hdr_dir": str(hdr_dir),
                "containers": len(containers),
                "containers_no_stream": sum(
                    1 for r in results if r.container and r.stream_index is None
                ),
                "hdr_count_total": sum(
                    {r.container: r.hdr_count or 0 for r in results if r.container}.values()
                ),
                "hdr_offset_match_true": sum(
                    1 for r in results if r.stream_index == 0 and r.hdr_offset_match
                ),
                "hdr_offset_mismatch": sorted(
                    {
                        r.container
                        for r in results
                        if r.stream_index == 0 and r.hdr_offset_match is False
                    }
                ),
            }
        )
    index: dict[str, Any] = {
        "source_root": str(src),
        "summary": summary,
        "entries": [_entry(r) for r in results],
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
    conv.add_argument(
        "--hdr-dir",
        type=Path,
        default=None,
        help="container mode: split each <stem>.dat in src, check against <dir>/<stem>.hdr",
    )
    conv.add_argument(
        "--vgmstream",
        type=Path,
        default=None,
        help=f"vgmstream-cli path (default: ${VGMSTREAM_ENV}, .omc/research/bin, PATH)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns a process exit code."""
    args = _build_parser().parse_args(argv)
    if args.cmd == "convert":
        if not args.src.exists():
            print(f"error: {args.src} does not exist", file=sys.stderr)
            return 2
        vgm = find_vgmstream(args.vgmstream)
        index = convert_tree(
            args.src,
            args.out,
            workers=args.workers,
            quality=args.quality,
            vgmstream=vgm,
            hdr_dir=args.hdr_dir,
        )
        print(json.dumps(index["summary"], indent=2))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
