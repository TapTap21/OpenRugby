"""Reader for EA ``BIGF`` archives (.big, .viv, .gob).

Layout (verified against Rugby 08): ``"BIGF"``, uint32 LE archive size,
uint32 BE entry count, uint32 BE header size, then ``count`` entries of
``{uint32 BE offset, uint32 BE size, NUL-terminated name}``. A trailing tag
(``L225`` etc.) may follow the index. Archive-size endianness is not trusted.
Entry offsets are validated against the real file size.
"""

from __future__ import annotations

import hashlib
import struct
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Self

MAGIC = b"BIGF"
CHUNK = 1 << 20


class BigfError(ValueError):
    """Raised for malformed archives."""


@dataclass(frozen=True)
class Entry:
    name: str
    offset: int
    size: int


class BigfArchive:
    """An open BIGF archive. Use as a context manager."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self._fh: BinaryIO = open(self.path, "rb")  # noqa: SIM115
        self.file_size = self.path.stat().st_size
        self.entries: list[Entry] = []
        self.header_size = 0
        self.index_end = 0
        self.trailer = b""
        try:
            self._parse()
        except Exception:
            self._fh.close()
            raise

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def close(self) -> None:
        self._fh.close()

    def _parse(self) -> None:
        fh = self._fh
        head = fh.read(16)
        if len(head) < 16 or head[:4] != MAGIC:
            raise BigfError(f"{self.path}: not a BIGF archive")
        (size_le,) = struct.unpack_from("<I", head, 4)
        count, self.header_size = struct.unpack_from(">II", head, 8)
        self.declared_size = size_le
        if count > 5_000_000:
            raise BigfError(f"implausible entry count {count}")
        # Read the index in a buffer large enough for header_size, grow if needed.
        want = max(self.header_size, 16) + 4096
        fh.seek(0)
        buf = fh.read(min(want, self.file_size))
        pos = 16
        entries: list[Entry] = []
        for _ in range(count):
            while True:
                end = buf.find(b"\0", pos + 8)
                if end != -1 and pos + 8 <= len(buf):
                    break
                more = fh.read(65536)
                if not more:
                    raise BigfError("index truncated")
                buf += more
            off, size = struct.unpack_from(">II", buf, pos)
            name = buf[pos + 8 : end].decode("latin-1")
            pos = end + 1
            if off + size > self.file_size:
                raise BigfError(f"entry {name!r} lies outside the file")
            entries.append(Entry(name, off, size))
        self.entries = entries
        self.index_end = pos
        self.trailer = buf[pos : pos + 4] if buf[pos : pos + 1] == b"L" else b""
        if entries and min(e.offset for e in entries) < pos:
            raise BigfError("first entry overlaps the index")

    def read(self, entry: Entry, limit: int | None = None) -> bytes:
        """Read (up to ``limit`` bytes of) a member."""
        self._fh.seek(entry.offset)
        n = entry.size if limit is None else min(limit, entry.size)
        return self._fh.read(n)

    def iter_chunks(self, entry: Entry) -> Iterator[bytes]:
        self._fh.seek(entry.offset)
        left = entry.size
        while left:
            data = self._fh.read(min(CHUNK, left))
            if not data:
                raise BigfError(f"short read for {entry.name!r}")
            left -= len(data)
            yield data


def safe_relpath(name: str, used: set[str]) -> PurePosixPath:
    """Map a member name to a safe, unique relative path (no escapes)."""
    parts = [p for p in name.replace("\\", "/").split("/") if p not in ("", ".", "..")]
    parts = [p.replace(":", "_") for p in parts] or ["_unnamed"]
    rel = PurePosixPath(*parts)
    cand, n = rel, 1
    while cand.as_posix().lower() in used:
        n += 1
        cand = rel.with_name(f"{rel.stem}~{n}{rel.suffix}")
    used.add(cand.as_posix().lower())
    return cand


def extract_all(
    archive: BigfArchive, out_dir: Path, *, decompress_refpack: bool = True
) -> list[dict[str, object]]:
    """Stream every member to ``out_dir``; return manifest records.

    RefPack members keep their raw bytes; the decoded payload is written beside
    them as ``<path>.unpacked``. Decode failures are recorded, not fatal.
    """
    from . import refpack

    out_dir.mkdir(parents=True, exist_ok=True)
    used: set[str] = set()
    manifest: list[dict[str, object]] = []
    for e in archive.entries:
        rel = safe_relpath(e.name, used)
        dest = out_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        sha = hashlib.sha256()
        first = b""
        with open(dest, "wb") as fh:
            for chunk in archive.iter_chunks(e):
                if not first:
                    first = chunk[:8]
                sha.update(chunk)
                fh.write(chunk)
        rec: dict[str, object] = {
            "name": e.name,
            "path": rel.as_posix(),
            "offset": e.offset,
            "size": e.size,
            "sha256": sha.hexdigest(),
            "first8": first.hex(),
            "refpack": False,
            "decompressed_size": None,
        }
        hdr = refpack.parse_header(first_bytes(dest))
        if hdr is not None and decompress_refpack:
            try:
                data = refpack.decompress(dest.read_bytes())
                Path(f"{dest}.unpacked").write_bytes(data)
                rec["refpack"] = True
                rec["decompressed_size"] = len(data)
            except (refpack.RefPackError, MemoryError) as exc:
                rec["refpack_error"] = str(exc)
        manifest.append(rec)
    return manifest


def first_bytes(path: Path, n: int = 16) -> bytes:
    with open(path, "rb") as fh:
        return fh.read(n)
