"""Reproducible asset pipeline: game install -> archives, textures, audio, models.

``python -m openrugby_tools.pipeline --game-dir DIR --out DIR [--stages ...]``

Stages (always run in this order):

``archives``
    Extract every top-level BIGF archive (``Data/*.gob|big|viv``, ``Data/motion/*``,
    ``Audio/*.big``) with RefPack decoding, then recurse into nested BIGF members of
    the game-data archives (up to :data:`MAX_NESTED_DEPTH` levels).
``textures``
    Decode every SHPI/FSH member to PNG (``<out>/textures``).
``audio``
    Convert SCHl streams to OGG (``<out>/ogg``). ``dat_*`` containers are split with
    their paired ``hdr_*`` archive automatically. Needs ffmpeg, ffprobe and vgmstream.
``models``
    Convert EAGL ELF objects to glTF (``<out>/models``); the player skeleton
    (``!skel.o``) is located by name and applied to skin-less objects.

Incremental: every stage records a signature (input sha256 values, tool source
hashes, parameters) in ``<out>/pipeline.json`` and is skipped when the signature is
unchanged and the previous run had no failures. ``--force`` rebuilds everything.

The game directory is only ever read. ``<out>/.gdignore`` is always written so Godot
never imports the raw output (see ``scripts/check-godot-safe.sh``).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import time
from collections.abc import Callable, Iterable, Sequence
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import audio, bigf, eagl, fsh, refpack

PIPELINE_VERSION = 1
STAGES = ("archives", "textures", "audio", "models")
MAX_NESTED_DEPTH = 8
GAME_EXE = "Rugby08.exe"
FFMPEG_ENV = "OPENRUGBY_FFMPEG"
ARCHIVE_SUFFIXES = (".gob", ".big", ".viv")
SKELETON_NAME = "!skel.o"
# Output trees that hold extracted archive members (scanned by textures/models).
NESTED_SUFFIX = ".nested"


class PipelineError(ValueError):
    """Configuration or environment problem that prevents the pipeline from running."""


# ---------------------------------------------------------------------------
# Result bookkeeping
# ---------------------------------------------------------------------------


@dataclass
class StageResult:
    name: str
    status: str = "ok"  # ok | unchanged | skipped | failed
    counts: dict[str, int] = field(default_factory=dict)
    failures: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    elapsed: float = 0.0

    @property
    def failed(self) -> bool:
        return self.status == "failed" or bool(self.failures)


def log(msg: str) -> None:
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while chunk := fh.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def sha256_text(*parts: object) -> str:
    return hashlib.sha256(json.dumps(parts, sort_keys=True, default=str).encode()).hexdigest()


def module_hash(*modules: Any) -> str:
    """Hash of the source of tool modules, so a code change invalidates a stage."""
    h = hashlib.sha256()
    for mod in modules:
        h.update(Path(mod.__file__).read_bytes())
    return h.hexdigest()


def fingerprint(path: Path, previous: dict[str, Any] | None) -> dict[str, Any]:
    """``{size, mtime_ns, sha256}``; the hash is reused when size and mtime are unchanged."""
    st = path.stat()
    if (
        previous
        and previous.get("size") == st.st_size
        and previous.get("mtime_ns") == st.st_mtime_ns
    ):
        if previous.get("sha256"):
            return {k: previous[k] for k in ("size", "mtime_ns", "sha256")}
    return {"size": st.st_size, "mtime_ns": st.st_mtime_ns, "sha256": sha256_file(path)}


def read_magic(path: Path, n: int = 4) -> bytes:
    try:
        with open(path, "rb") as fh:
            return fh.read(n)
    except OSError:
        return b""


def default_workers() -> int:
    return max(1, min(8, os.cpu_count() or 1))


def _ci_child(directory: Path, name: str) -> Path | None:
    """Case-insensitive child lookup (Windows installs vs. Linux copies)."""
    direct = directory / name
    if direct.exists() or direct.is_symlink():
        return direct
    try:
        for child in directory.iterdir():
            if child.name.lower() == name.lower():
                return child
    except OSError:
        return None
    return None


def _run_pool(
    func: Callable[[Any], Any],
    jobs: Sequence[Any],
    workers: int,
    label: str,
    chunksize: int = 1,
) -> Iterable[Any]:
    """Yield results in order, printing coarse progress."""
    total = len(jobs)
    step = max(1, total // 10)
    if total == 0:
        return
    if workers <= 1 or total < 4:
        for i, job in enumerate(jobs, 1):
            yield func(job)
            if i % step == 0 or i == total:
                log(f"  {label}: {i}/{total}")
        return
    with ProcessPoolExecutor(max_workers=workers) as pool:
        for i, res in enumerate(pool.map(func, jobs, chunksize=chunksize), 1):
            yield res
            if i % step == 0 or i == total:
                log(f"  {label}: {i}/{total}")


# ---------------------------------------------------------------------------
# Game directory
# ---------------------------------------------------------------------------


@dataclass
class Source:
    """One input file from the game install."""

    key: str  # game-relative POSIX path, e.g. ``Data/motion/script.big``
    path: Path  # path as given (may be a symlink)
    kind: str  # ``archive`` | ``audio-archive`` | ``standalone-audio``
    out_name: str  # directory (archives) or stem (standalone audio) under the output
    fp: dict[str, Any] = field(default_factory=dict)
    duplicate_of: str | None = None

    def out_name_dir(self) -> str:
        """Output directory of this archive relative to ``--out``."""
        return f"audio/{self.out_name}" if self.kind == "audio-archive" else self.out_name


def validate_game_dir(game_dir: Path) -> tuple[Path, Path, Path | None]:
    """Return ``(game, data_dir, audio_dir)``; raise if this is not a Rugby 08 install."""
    if not game_dir.is_dir():
        raise PipelineError(f"--game-dir {game_dir} is not a directory")
    exe = _ci_child(game_dir, GAME_EXE)
    if exe is None:
        raise PipelineError(f"{game_dir} does not look like a Rugby 08 install: no {GAME_EXE}")
    if not exe.is_file():
        raise PipelineError(f"{exe} is not readable (dangling symlink?)")
    data = _ci_child(game_dir, "Data")
    if data is None or not data.is_dir():
        raise PipelineError(f"{game_dir} does not look like a Rugby 08 install: no Data/ directory")
    audio_dir = _ci_child(game_dir, "Audio")
    return game_dir, data, audio_dir if audio_dir is not None and audio_dir.is_dir() else None


def guard_output(out: Path, roots: Iterable[Path]) -> None:
    """Refuse an output directory inside the (symlink-resolved) game install."""
    out_res = out.resolve()
    for root in roots:
        res = root.resolve()
        if out_res == res or res in out_res.parents:
            raise PipelineError(
                f"--out {out} resolves inside the game install ({res}); "
                "the pipeline never writes to the game directory"
            )


def discover_sources(game: Path, data: Path, audio_dir: Path | None) -> list[Source]:
    """Find BIGF archives and standalone SCHl files; symlinks are followed for reading."""
    sources: list[Source] = []
    used: set[str] = set()

    def add_archive(path: Path, rel: str, kind: str) -> None:
        if read_magic(path) != bigf.MAGIC:
            return
        name = path.name
        if name.lower() in used:
            name = f"{path.parent.name}.{path.name}"
        used.add(name.lower())
        sources.append(Source(rel, path, kind, name))

    for directory, rel_dir in ((data, "Data"), (data / "motion", "Data/motion")):
        if directory.is_dir():
            for p in sorted(directory.iterdir()):
                if p.is_file() and p.suffix.lower() in ARCHIVE_SUFFIXES:
                    add_archive(p, f"{rel_dir}/{p.name}", "archive")
    if audio_dir is not None:
        for p in sorted(audio_dir.iterdir()):
            if not p.is_file():
                continue
            if p.suffix.lower() == ".big":
                add_archive(p, f"Audio/{p.name}", "audio-archive")
            elif read_magic(p) == audio.MAGIC:
                sources.append(Source(f"Audio/{p.name}", p, "standalone-audio", p.stem))
    return sources


# ---------------------------------------------------------------------------
# Pipeline manifest
# ---------------------------------------------------------------------------


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return doc if isinstance(doc, dict) and doc.get("version") == PIPELINE_VERSION else {}


def save_manifest(path: Path, doc: dict[str, Any]) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(doc, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, path)


@dataclass
class Context:
    game: Path
    out: Path
    workers: int
    force: bool
    sources: list[Source]
    manifest: dict[str, Any]
    manifest_path: Path

    def stage_doc(self, name: str) -> dict[str, Any]:
        return self.manifest.setdefault("stages", {}).setdefault(name, {})

    def save(self) -> None:
        save_manifest(self.manifest_path, self.manifest)

    def archive_shas(self, kinds: tuple[str, ...]) -> list[str]:
        return sorted(
            f"{s.key}:{s.fp.get('sha256')}"
            for s in self.sources
            if s.kind in kinds and s.duplicate_of is None
        )

    def unchanged(self, name: str, signature: str, output: Path) -> bool:
        doc = self.manifest.get("stages", {}).get(name, {})
        return (
            not self.force
            and doc.get("signature") == signature
            and doc.get("failures", 1) == 0
            and output.exists()
        )

    def record(self, name: str, signature: str, res: StageResult) -> None:
        self.stage_doc(name).update(
            {
                "signature": signature,
                "failures": len(res.failures),
                "counts": res.counts,
                "elapsed_s": round(res.elapsed, 2),
                "finished": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            }
        )
        self.save()


def archive_roots(out: Path) -> list[Path]:
    """Existing output trees of game-data archives (not audio), top-level and nested."""
    roots = []
    for child in sorted(out.iterdir()) if out.is_dir() else []:
        if not child.is_dir():
            continue
        if child.name in {"audio", "ogg", "ogg-standalone", "textures", "models"}:
            continue
        roots.append(child)
    return roots


# ---------------------------------------------------------------------------
# Stage: archives
# ---------------------------------------------------------------------------


def extract_one(job: tuple[str, str, bool]) -> tuple[bool, str, int, int]:
    """Extract one BIGF archive. Returns ``(ok, message, members, refpack_errors)``."""
    archive, outdir, reuse = job
    out = Path(outdir)
    manifest = out / "manifest.json"
    if reuse and manifest.is_file():
        try:
            man = json.loads(manifest.read_text())
            return True, "cached", len(man), sum(1 for m in man if "refpack_error" in m)
        except ValueError:
            pass
    if out.exists():
        shutil.rmtree(out)
    try:
        with bigf.BigfArchive(archive) as arc:
            man = bigf.extract_all(arc, out)
        manifest.write_text(json.dumps(man, indent=1), encoding="utf-8")
    except (bigf.BigfError, refpack.RefPackError, OSError, ValueError, MemoryError) as exc:
        return False, f"{type(exc).__name__}: {exc}", 0, 0
    return True, "", len(man), sum(1 for m in man if "refpack_error" in m)


def bigf_members(directory: Path) -> list[tuple[str, Path]]:
    """``(member-relpath, payload)`` for every BIGF member of an extracted archive.

    The RefPack-decoded ``.unpacked`` payload is used when the manifest recorded one.
    """
    try:
        man = json.loads((directory / "manifest.json").read_text())
    except (OSError, ValueError):
        return []
    found = []
    for rec in man:
        rel = rec["path"]
        raw = directory / rel
        payload = (
            raw.with_name(raw.name + ".unpacked")
            if rec.get("refpack") and "refpack_error" not in rec
            else raw
        )
        if payload.is_file() and read_magic(payload) == bigf.MAGIC:
            found.append((rel, payload))
    return found


def nested_dir(nested_root: Path, depth: int, chain: tuple[str, ...]) -> Path:
    base = nested_root if depth == 1 else nested_root / f"_level{depth}"
    return base.joinpath(*chain) if chain else base


def stage_archives(ctx: Context) -> StageResult:
    res = StageResult("archives")
    recs = ctx.stage_doc("archives").setdefault("sources", {})
    arcs = [s for s in ctx.sources if s.kind in ("archive", "audio-archive")]
    if not arcs:
        res.status = "failed"
        res.failures.append("no BIGF archives found in the game directory")
        return res
    log(f"[archives] fingerprinting {len(arcs)} archives (sha256)")
    seen: dict[str, Source] = {}
    for s in arcs:
        s.fp = fingerprint(s.path, recs.get(s.key))
        twin = seen.get(s.fp["sha256"])
        if twin is not None:
            s.duplicate_of = twin.key
            log(f"[archives] {s.key} is byte-identical to {twin.key}: skipped")
        else:
            seen[s.fp["sha256"]] = s

    todo_full: list[Source] = []
    todo_nested: list[Source] = []
    complete: list[Source] = []
    for s in arcs:
        if s.duplicate_of:
            recs[s.key] = {**s.fp, "state": "duplicate", "duplicate_of": s.duplicate_of}
            continue
        prev = recs.get(s.key, {})
        same = all(prev.get(k) == s.fp[k] for k in ("size", "sha256"))
        top_ok = (ctx.out / s.out_name_dir() / "manifest.json").is_file()
        if not ctx.force and same and top_ok and prev.get("state") == "complete":
            if not prev.get("failures"):
                complete.append(s)
                continue
        if not ctx.force and same and top_ok and prev.get("state") in ("extracted", "complete"):
            todo_nested.append(s)
        else:
            todo_full.append(s)

    for s in complete:
        log(f"[archives] {s.key}: unchanged")

    top_info: dict[str, dict[str, Any]] = {}
    # Top level.
    jobs = []
    for s in todo_full:
        out_top = ctx.out / s.out_name_dir()
        nested_root = ctx.out / (s.out_name + NESTED_SUFFIX)
        if nested_root.exists():
            shutil.rmtree(nested_root)
        jobs.append((str(s.path), str(out_top), False))
    if jobs:
        log(f"[archives] extracting {len(jobs)} top-level archives")
    for s, (ok, msg, members, rp_err) in zip(
        todo_full,
        _run_pool(extract_one, jobs, min(ctx.workers, len(jobs)) or 1, "top-level"),
        strict=True,
    ):
        if not ok:
            res.failures.append(f"{s.key}: {msg}")
            recs[s.key] = {**s.fp, "state": "failed", "failures": [msg]}
            continue
        log(f"[archives] {s.key}: {members} members")
        recs[s.key] = {
            **s.fp,
            "state": "extracted",
            "members": members,
            "nested_archives": 0,
            "nested_members": 0,
            "refpack_errors": rp_err,
            "failures": [],
        }
        top_info[s.key] = recs[s.key]
        if s.kind == "audio-archive":
            recs[s.key]["state"] = "complete"
    ctx.save()

    # Nested levels (game-data archives only; audio containers hold no BIGF members).
    live = [s for s in todo_full + todo_nested if recs[s.key].get("state") == "extracted"]
    for s in todo_nested:
        recs[s.key].update({"nested_archives": 0, "nested_members": 0, "failures": []})
    frontier: dict[str, list[tuple[Path, tuple[str, ...]]]] = {
        s.key: [(ctx.out / s.out_name_dir(), ())] for s in live
    }
    by_key = {s.key: s for s in live}
    for depth in range(1, MAX_NESTED_DEPTH + 1):
        level_jobs: list[tuple[str, str, bool]] = []
        owners: list[tuple[str, tuple[str, ...], Path]] = []
        for key, items in frontier.items():
            nroot = ctx.out / (by_key[key].out_name + NESTED_SUFFIX)
            for parent, chain in items:
                for rel, payload in bigf_members(parent):
                    sub = chain + (rel,)
                    dest = nested_dir(nroot, depth, sub)
                    level_jobs.append((str(payload), str(dest), True))
                    owners.append((key, sub, dest))
        if not level_jobs:
            break
        log(f"[archives] nested level {depth}: {len(level_jobs)} archives")
        frontier = {}
        results = _run_pool(extract_one, level_jobs, ctx.workers, f"nested level {depth}", 4)
        for (key, sub, dest), (ok, msg, members, rp_err) in zip(owners, results, strict=True):
            rec = recs[key]
            if not ok:
                rec["failures"].append(f"{'/'.join(sub)}: {msg}")
                res.failures.append(f"{by_key[key].key} -> {'/'.join(sub)}: {msg}")
                continue
            rec["nested_archives"] += 1
            rec["nested_members"] += members
            rec["refpack_errors"] = rec.get("refpack_errors", 0) + rp_err
            frontier.setdefault(key, []).append((dest, sub))
        ctx.save()
    else:
        left = sum(len(bigf_members(d)) for items in frontier.values() for d, _ in items)
        if left:
            res.notes.append(f"{left} BIGF members beyond depth {MAX_NESTED_DEPTH} not extracted")

    for s in live:
        rec = recs[s.key]
        rec["state"] = "complete"
    # Previously-failed sources keep their failure so the stage stays failed until fixed.
    ctx.save()

    top = nested = members = rp = 0
    for s in arcs:
        rec = recs.get(s.key, {})
        if s.duplicate_of or rec.get("state") == "failed":
            continue
        top += 1
        nested += rec.get("nested_archives", 0)
        members += rec.get("members", 0) + rec.get("nested_members", 0)
        rp += rec.get("refpack_errors", 0)
        for f in rec.get("failures", []):
            if f not in res.failures and not any(f in x for x in res.failures):
                res.failures.append(f"{s.key}: {f}")
    res.counts = {"archives": top, "nested archives": nested, "members": members}
    if rp:
        res.notes.append(f"{rp} members had RefPack decode errors (raw bytes kept)")
    skipped = len(complete)
    res.status = "unchanged" if skipped == len(seen) and not todo_full and not todo_nested else "ok"
    return res


# ---------------------------------------------------------------------------
# Stage: textures
# ---------------------------------------------------------------------------


def stage_textures(ctx: Context) -> StageResult:
    res = StageResult("textures")
    try:
        import PIL  # noqa: F401
    except ImportError:
        res.status = "skipped"
        res.notes.append("Pillow is not installed: pip install pillow (or '.[tools]')")
        return res
    roots = archive_roots(ctx.out)
    if not roots:
        res.status = "failed"
        res.failures.append("no extracted archives under the output; run the archives stage first")
        return res
    out_tex = ctx.out / "textures"
    signature = sha256_text(
        ctx.archive_shas(("archive",)), module_hash(fsh, bigf, refpack), PIPELINE_VERSION
    )
    if ctx.unchanged("textures", signature, out_tex / "index.json"):
        prior = ctx.stage_doc("textures")
        res.status = "unchanged"
        res.counts = prior.get("counts", {})
        return res
    if out_tex.exists():
        shutil.rmtree(out_tex)
    out_tex.mkdir(parents=True)
    jobs = []
    for root in roots:
        for p, payload in fsh.find_fsh_sources(root):
            logical = f"{root.name}/{p.relative_to(root).as_posix()}"
            jobs.append((logical, str(payload), str(out_tex), False))
    log(f"[textures] {len(jobs)} SHPI sources")
    results = list(_run_pool(fsh._convert_one, jobs, ctx.workers, "textures", 32))
    pngs = bad = 0
    for r in results:
        if r["error"]:
            bad += 1
            res.failures.append(f"{r['source']}: {r['error']}")
        for b in r["bitmaps"]:
            if b["error"]:
                bad += 1
                res.failures.append(f"{r['source']} [{b['tag']}] {b['format']}: {b['error']}")
            else:
                pngs += len(b["files"])
    (out_tex / "index.json").write_text(
        json.dumps({"textures": results}, indent=1, sort_keys=True), encoding="utf-8"
    )
    res.counts = {"sources": len(results), "png": pngs}
    ctx.record("textures", signature, res)
    return res


# ---------------------------------------------------------------------------
# Stage: audio
# ---------------------------------------------------------------------------


def locate_audio_tools() -> tuple[Path | None, list[str]]:
    """Return ``(vgmstream, problems)``. ``problems`` is empty when audio can run."""
    problems = []
    env = os.environ.get(FFMPEG_ENV)
    if env:
        exe = Path(env)
        if not exe.is_file():
            problems.append(f"${FFMPEG_ENV}={env} does not exist")
        else:
            os.environ["PATH"] = str(exe.parent) + os.pathsep + os.environ.get("PATH", "")
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            problems.append(
                f"{tool} not found: install ffmpeg (https://ffmpeg.org) or set ${FFMPEG_ENV} "
                "to the ffmpeg executable (ffprobe must sit beside it)"
            )
    vgm = audio.find_vgmstream()
    if vgm is None:
        problems.append(
            "vgmstream-cli not found: install vgmstream (https://github.com/vgmstream/vgmstream) "
            f"and put vgmstream-cli on PATH or set ${audio.VGMSTREAM_ENV} to its path"
        )
    return vgm, problems


def stage_audio(ctx: Context) -> StageResult:
    res = StageResult("audio")
    vgm, problems = locate_audio_tools()
    if problems:
        res.status = "skipped"
        res.notes.extend(problems)
        return res
    todo = [s for s in ctx.sources if s.kind in ("audio-archive", "standalone-audio")]
    if not todo:
        res.status = "skipped"
        res.notes.append("no audio archives found")
        return res
    for s in todo:
        if not s.fp:
            s.fp = fingerprint(s.path, ctx.stage_doc("archives").get("sources", {}).get(s.key))
    ogg = ctx.out / "ogg"
    tool = module_hash(audio, bigf, refpack)
    items = ctx.stage_doc("audio").setdefault("items", {})
    sha_by_name = {s.out_name: s.fp["sha256"] for s in todo if s.kind == "audio-archive"}
    totals = {"ok": 0, "failed": 0}
    ran = 0
    for s in todo:
        if s.duplicate_of:
            continue
        if s.kind == "audio-archive":
            src_dir = ctx.out / "audio" / s.out_name
            dest = ogg / s.out_name
            name = s.out_name
            if name.lower().startswith("hdr_"):
                continue  # companion index, not playable
            hdr_name = "hdr_" + name[4:] if name.lower().startswith("dat_") else None
            hdr_dir = ctx.out / "audio" / hdr_name if hdr_name else None
            if hdr_dir is not None and not hdr_dir.is_dir():
                hdr_dir = None
            extra = sha_by_name.get(hdr_name) if hdr_name else None
            if not src_dir.is_dir():
                res.failures.append(f"{s.key}: not extracted; run the archives stage first")
                continue
        else:
            src_dir, hdr_dir, extra = s.path, None, None
            dest = ogg.parent / "ogg-standalone"
        sig = sha256_text(s.fp["sha256"], extra, tool, audio.DEFAULT_QUALITY, str(vgm))
        index = dest / "index.json"
        prior = items.get(s.key, {})
        if (
            not ctx.force
            and prior.get("signature") == sig
            and prior.get("failed") == 0
            and index.exists()
        ):
            log(f"[audio] {s.key}: unchanged")
            totals["ok"] += prior.get("ok", 0)
            continue
        if s.kind == "audio-archive" and dest.exists():
            shutil.rmtree(dest)
        log(f"[audio] converting {s.key}" + (" (container mode, hdr-split)" if hdr_dir else ""))
        try:
            doc = audio.convert_tree(
                src_dir, dest, workers=ctx.workers, vgmstream=vgm, hdr_dir=hdr_dir
            )
        except (RuntimeError, OSError) as exc:
            res.failures.append(f"{s.key}: {exc}")
            continue
        summary = doc["summary"]
        ran += 1
        totals["ok"] += summary["ok"]
        totals["failed"] += summary["failed"]
        for e in doc["entries"]:
            if not e.get("ok"):
                res.failures.append(f"{e.get('source')}: {e.get('error')}")
        items[s.key] = {
            "signature": sig,
            "ok": summary["ok"],
            "failed": summary["failed"],
            "duration_s": summary.get("total_duration_s"),
        }
        ctx.save()
    res.counts = {"ogg": totals["ok"], "convert failures": totals["failed"]}
    if ran == 0 and not res.failures:
        res.status = "unchanged"
    return res


# ---------------------------------------------------------------------------
# Stage: models
# ---------------------------------------------------------------------------

_SKEL_CACHE: dict[str, Any] = {}


def find_skeleton(out: Path) -> Path | None:
    """Locate the player skeleton ``!skel.o`` by name (prefers the decoded ``.unpacked``)."""
    hits: list[Path] = []
    for root in archive_roots(out):
        for dirpath, _dirs, files in os.walk(root):
            for f in files:
                if f in (SKELETON_NAME, SKELETON_NAME + ".unpacked"):
                    hits.append(Path(dirpath) / f)
    if not hits:
        return None
    unpacked = [h for h in hits if h.suffix == ".unpacked"]
    return sorted(unpacked or hits)[0]


def export_model(job: tuple[str, str, str, str | None]) -> dict[str, Any]:
    path_s, out_s, models_s, skel_path = job
    p, out = Path(path_s), Path(out_s)
    rec: dict[str, Any] = {"source": p.relative_to(out).as_posix(), "error": None}
    try:
        skel = None
        if skel_path:
            if skel_path not in _SKEL_CACHE:
                sk_asset = eagl.load_asset(Path(skel_path))
                _SKEL_CACHE[skel_path] = sk_asset.skeletons[0] if sk_asset.skeletons else None
            skel = _SKEL_CACHE[skel_path]
        asset = eagl.load_asset(p)
        gltf = Path(models_s) / (eagl._out_name(p, out) + ".gltf")
        tex = eagl.texture_dirs_for(p, out, out / "textures")
        rec["summary"] = eagl.export_gltf(asset, gltf, tex, skel, False)
        rec["gltf"] = gltf.name
    except Exception as exc:  # noqa: BLE001 - one bad object must not abort the stage
        rec["error"] = f"{type(exc).__name__}: {exc}"
    return rec


def stage_models(ctx: Context) -> StageResult:
    res = StageResult("models")
    roots = archive_roots(ctx.out)
    if not roots:
        res.status = "failed"
        res.failures.append("no extracted archives under the output; run the archives stage first")
        return res
    skel = find_skeleton(ctx.out)
    if skel is None:
        res.notes.append(f"{SKELETON_NAME} not found: skin-less objects are exported unskinned")
    else:
        log(f"[models] skeleton: {skel.relative_to(ctx.out).as_posix()}")
    out_models = ctx.out / "models"
    tex_sig = ctx.manifest.get("stages", {}).get("textures", {}).get("signature")
    signature = sha256_text(
        ctx.archive_shas(("archive",)), tex_sig, module_hash(eagl, bigf, refpack), PIPELINE_VERSION
    )
    if ctx.unchanged("models", signature, out_models / "index.json"):
        res.status = "unchanged"
        res.counts = ctx.stage_doc("models").get("counts", {})
        return res
    if out_models.exists():
        shutil.rmtree(out_models)
    out_models.mkdir(parents=True)
    files = [p for root in roots for p in eagl.find_elf_members(root)]
    jobs = [(str(p), str(ctx.out), str(out_models), str(skel) if skel else None) for p in files]
    log(f"[models] {len(jobs)} EAGL objects")
    results = list(_run_pool(export_model, jobs, ctx.workers, "models", 8))
    skinned = 0
    for r in results:
        if r["error"]:
            res.failures.append(f"{r['source']}: {r['error']}")
        elif r["summary"].get("skinned"):
            skinned += 1
    (out_models / "index.json").write_text(
        json.dumps({"models": results}, indent=1, sort_keys=True), encoding="utf-8"
    )
    res.counts = {
        "objects": len(results),
        "gltf": sum(1 for r in results if not r["error"]),
        "skinned": skinned,
    }
    ctx.record("models", signature, res)
    return res


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

STAGE_FUNCS: dict[str, Callable[[Context], StageResult]] = {
    "archives": stage_archives,
    "textures": stage_textures,
    "audio": stage_audio,
    "models": stage_models,
}


def parse_stages(value: str) -> list[str]:
    wanted = [s.strip().lower() for s in value.split(",") if s.strip()]
    bad = [s for s in wanted if s not in STAGES]
    if bad or not wanted:
        raise PipelineError(f"unknown stage(s) {bad or value!r}; choose from {', '.join(STAGES)}")
    return [s for s in STAGES if s in wanted]


def format_summary(results: list[StageResult], total: float) -> str:
    rows = [("stage", "status", "result", "failures", "seconds")]
    for r in results:
        counts = ", ".join(f"{v} {k}" for k, v in r.counts.items()) or "-"
        rows.append((r.name, r.status, counts, str(len(r.failures)), f"{r.elapsed:.1f}"))
    widths = [max(len(row[i]) for row in rows) for i in range(5)]
    lines = []
    for n, row in enumerate(rows):
        lines.append("  ".join(c.ljust(widths[i]) for i, c in enumerate(row)).rstrip())
        if n == 0:
            lines.append("  ".join("-" * w for w in widths))
    lines.append(f"total: {total:.1f}s")
    return "\n".join(lines)


def run_pipeline(
    game_dir: Path,
    out: Path,
    stages: Sequence[str] = STAGES,
    workers: int | None = None,
    force: bool = False,
) -> tuple[int, list[StageResult]]:
    """Run the pipeline; return ``(exit_code, results)``."""
    game, data, audio_dir = validate_game_dir(game_dir)
    guard_output(out, [game, data] + ([audio_dir] if audio_dir else []))
    out.mkdir(parents=True, exist_ok=True)
    (out / ".gdignore").touch()
    manifest_path = out / "pipeline.json"
    manifest = load_manifest(manifest_path)
    manifest.update({"version": PIPELINE_VERSION, "game_dir": str(game)})
    ctx = Context(
        game=game,
        out=out,
        workers=workers or default_workers(),
        force=force,
        sources=discover_sources(game, data, audio_dir),
        manifest=manifest,
        manifest_path=manifest_path,
    )
    log(f"game: {game}  out: {out}  workers: {ctx.workers}  stages: {','.join(stages)}")
    results: list[StageResult] = []
    t_all = time.monotonic()
    for name in stages:
        log(f"== {name} ==")
        t0 = time.monotonic()
        try:
            res = STAGE_FUNCS[name](ctx)
        except Exception as exc:  # noqa: BLE001 - report and continue with other stages
            res = StageResult(name, "failed", failures=[f"{type(exc).__name__}: {exc}"])
        res.elapsed = time.monotonic() - t0
        results.append(res)
        for note in res.notes:
            log(f"  note: {note}")
        for f in res.failures[:10]:
            log(f"  FAIL {f}")
        if len(res.failures) > 10:
            log(f"  ... and {len(res.failures) - 10} more failures")
        ctx.save()
    log("")
    log(format_summary(results, time.monotonic() - t_all))
    code = 1 if any(r.failed for r in results) else 0
    return code, results


def add_arguments(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--game-dir", type=Path, required=True, help="Rugby 08 install (read-only)")
    ap.add_argument("--out", type=Path, required=True, help="output directory (Godot-ignored)")
    ap.add_argument(
        "--stages",
        default=",".join(STAGES),
        help=f"comma-separated subset of {','.join(STAGES)} (default: all)",
    )
    ap.add_argument(
        "--workers", type=int, default=None, help="parallel workers (default: min(8, CPUs))"
    )
    ap.add_argument("--force", action="store_true", help="ignore the manifest and rebuild")


def run_from_args(a: argparse.Namespace) -> int:
    try:
        stages = parse_stages(a.stages)
        code, _ = run_pipeline(a.game_dir, a.out, stages, a.workers, a.force)
    except PipelineError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return code


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m openrugby_tools.pipeline", description=__doc__.split("\n")[0]
    )
    add_arguments(ap)
    return run_from_args(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
