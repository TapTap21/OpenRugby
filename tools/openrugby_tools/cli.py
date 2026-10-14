"""Command line interface: ``python -m openrugby_tools.cli {list,extract,inventory,report}``."""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

from . import pipeline, refpack
from .bigf import BigfArchive, BigfError, extract_all

REPO = Path(__file__).resolve().parents[2]
DEFAULT_EXTRACT_ROOT = REPO / "extracted"
DEFAULT_INV_DIR = REPO / ".omc" / "research" / "inventory"
DEFAULT_REPORT = REPO / "docs" / "re" / "01-archive-inventory.md"

# Hints keyed on magic only. These are *candidates*, not confirmed formats.
MAGIC_HINTS: dict[str, str] = {
    "SHPI": "texture (EA SHPI/FSH)",
    "FSH ": "texture (EA FSH)",
    "SCNE": "model/scene (SCNE)",
    "PSSG": "model/scene (PSSG)",
    "FLSH": "UI/flash (FLSH?)",
    "SCHl": "audio (EA SCHl stream)",
    "ABK ": "audio bank (ABK)",
    "BNK ": "audio bank (BNK)",
    "RIFF": "RIFF container (audio/other)",
    "OggS": "audio (Ogg)",
    "ID3": "audio (MP3 w/ ID3)",
    "DDS ": "texture (DDS)",
    "\x89PNG": "image (PNG)",
    "BIGF": "nested BIGF archive",
    "BIKi": "video (Bink)",
    "MZ": "Windows executable/DLL",
}
EXT_HINTS: dict[str, str] = {
    ".fsh": "texture",
    ".tga": "texture",
    ".dds": "texture",
    ".png": "texture",
    ".ttf": "font",
    ".fnt": "font",
    ".asf": "audio",
    ".mus": "audio",
    ".snr": "audio",
    ".lua": "script",
    ".txt": "text",
    ".csv": "text",
    ".xml": "text/data",
    ".str": "text/locale",
    ".dat": "data (unknown)",
    ".db": "database",
    ".swf": "UI/flash",
    ".vp6": "video",
}


def _magic_label(head: bytes) -> str:
    m = head[:4]
    if len(m) == 4 and all(32 <= b < 127 for b in m):
        return m.decode("ascii")
    if m[:3] == b"ID3":
        return "ID3"
    return m.hex() or "(empty)"


def _ext(name: str) -> str:
    base = name.replace("\\", "/").rsplit("/", 1)[-1]
    return ("." + base.rsplit(".", 1)[-1].lower()) if "." in base else "(none)"


def build_inventory(path: Path) -> dict[str, object]:
    members: list[dict[str, object]] = []
    with BigfArchive(path) as arc:
        for e in arc.entries:
            head = arc.read(e, 16)
            hdr = refpack.parse_header(head)
            inner: dict[str, object] = {}
            if hdr is not None:
                try:
                    data = refpack.decompress(arc.read(e))
                    inner = {
                        "refpack_ok": True,
                        "inner_size": len(data),
                        "inner_magic": _magic_label(data[:16]),
                        "inner_first16": data[:16].hex(),
                    }
                except refpack.RefPackError as exc:
                    inner = {"refpack_ok": False, "refpack_error": str(exc)}
            members.append(
                {
                    **inner,
                    "name": e.name,
                    "offset": e.offset,
                    "size": e.size,
                    "ext": _ext(e.name),
                    "magic": _magic_label(head),
                    "first16": head.hex(),
                    "refpack_sig": hdr is not None,
                    "refpack_size": hdr.uncompressed_size if hdr else None,
                }
            )
        return {
            "archive": path.name,
            "path": str(path),
            "file_size": arc.file_size,
            "declared_size_le": arc.declared_size,
            "header_size_field": arc.header_size,
            "index_end": arc.index_end,
            "trailer": arc.trailer.decode("latin-1"),
            "member_count": len(members),
            "members": members,
        }


def cmd_list(a: argparse.Namespace) -> int:
    with BigfArchive(a.archive) as arc:
        for e in arc.entries:
            print(f"{e.offset:>12} {e.size:>12} {e.name}")
        print(f"# {len(arc.entries)} members, index_end={arc.index_end}, trailer={arc.trailer!r}")
    return 0


def cmd_extract(a: argparse.Namespace) -> int:
    t0 = time.time()
    src = Path(a.archive)
    out = Path(a.out) if a.out else DEFAULT_EXTRACT_ROOT / src.name
    with BigfArchive(src) as arc:
        man = extract_all(arc, out, decompress_refpack=not a.no_refpack)
    (out / "manifest.json").write_text(json.dumps(man, indent=1))
    errs = sum(1 for m in man if "refpack_error" in m)
    rp = sum(1 for m in man if m["refpack"])
    print(
        f"{src.name}: {len(man)} members -> {out} (refpack ok={rp}, errors={errs}) "
        f"in {time.time() - t0:.1f}s"
    )
    return 0


def cmd_inventory(a: argparse.Namespace) -> int:
    outdir = Path(a.out) if a.out else DEFAULT_INV_DIR
    outdir.mkdir(parents=True, exist_ok=True)
    for p in a.archives:
        inv = build_inventory(Path(p))
        dest = outdir / f"{Path(p).name}.json"
        dest.write_text(json.dumps(inv))
        print(f"{inv['archive']}: {inv['member_count']} members -> {dest}")
    return 0


def _human(n: int) -> str:
    return f"{n / 1048576:.1f} MiB"


def _hint(magic: str, ext: str) -> str:
    magic = magic.removeprefix("RP>")
    return MAGIC_HINTS.get(magic) or MAGIC_HINTS.get(magic[:3]) or ""


def cmd_report(a: argparse.Namespace) -> int:
    invdir = Path(a.inventory_dir) if a.inventory_dir else DEFAULT_INV_DIR
    invs = [json.loads(p.read_text()) for p in sorted(invdir.glob("*.json"))]
    intro = (
        "Generated by `tools/openrugby_tools/cli.py report`. Format hints are from magic "
        "bytes / extensions only; anything not matched is **unknown**."
    )
    L: list[str] = ["# 01 - Archive inventory (Rugby 08)", "", intro, ""]
    total_magic: Counter[str] = Counter()
    unk: dict[str, list[dict[str, object]]] = defaultdict(list)
    for inv in invs:
        ms = inv["members"]
        for m in ms:
            m["raw_magic"] = m["magic"]
            if m.get("refpack_ok"):
                m["magic"] = "RP>" + m["inner_magic"]
        L += [
            f"## {inv['archive']}",
            "",
            f"- members: {inv['member_count']}",
            (
                f"- file size: {_human(inv['file_size'])}; member bytes total: "
                f"{_human(sum(m['size'] for m in ms))}"
            ),
            (
                f"- header size field {inv['header_size_field']}, index end "
                f"{inv['index_end']}, trailer tag {inv['trailer']!r}"
            ),
        ]
        rp = [m for m in ms if m["refpack_sig"]]
        ok = sum(1 for m in rp if m.get("refpack_ok"))
        L.append(
            f"- RefPack-signature members: {len(rp)}; decoded OK: {ok}; "
            f"decode failed: {len(rp) - ok}. Magic `RP>xxxx` below = first 4 bytes "
            "after decompression (raw members keep their own bytes)."
        )
        pref: Counter[str] = Counter()
        for m in ms:
            parts = m["name"].replace("\\", "/").split("/")
            pref["/".join(parts[:-1][:2]) or "(root)"] += 1
        L += [
            "- directory-like prefixes: "
            + (", ".join(f"`{k}` ({v})" for k, v in pref.most_common(15))),
            "",
        ]
        ext = Counter(m["ext"] for m in ms)
        mag = Counter(m["magic"] for m in ms)
        L += ["Extension histogram:", "", "| ext | count | bytes |", "|---|---|---|"]
        for k, v in ext.most_common(25):
            L.append(f"| `{k}` | {v} | {sum(m['size'] for m in ms if m['ext'] == k)} |")
        L += [
            "",
            "First-4-bytes histogram:",
            "",
            "| magic | count | hint | examples |",
            "|---|---|---|---|",
        ]
        for k, v in mag.most_common(25):
            ex = [m["name"] for m in ms if m["magic"] == k][:10]
            L.append(f"| `{k}` | {v} | {_hint(k, '') or 'unknown'} | {'; '.join(ex[:10])} |")
        L.append("")
        total_magic.update(mag)
        for m in ms:
            if not _hint(m["magic"], m["ext"]):
                unk[m["magic"]].append({**m, "archive": inv["archive"]})
        L += ["Ten example names per extension (top 8 extensions):", ""]
        for k, _ in ext.most_common(8):
            ex = [m["name"] for m in ms if m["ext"] == k][:10]
            L.append(f"- `{k}`: " + "; ".join(ex))
        L.append("")
    L += ["## Combined top magics", "", "| magic | count |", "|---|---|"]
    L += [f"| `{k}` | {v} |" for k, v in total_magic.most_common(15)]
    L += [
        "",
        "## Candidate formats to reverse",
        "",
        "Magics with no known hint (unknown until proven). Count, archive(s), example member.",
        "",
        "| magic | count | archives | example | size |",
        "|---|---|---|---|---|",
    ]
    for k, v in sorted(unk.items(), key=lambda kv: -len(kv[1]))[:60]:
        arcs = sorted({x["archive"] for x in v})
        L.append(f"| `{k}` | {len(v)} | {', '.join(arcs)} | {v[0]['name']} | {v[0]['size']} |")
    L += ["", "## Recognised-by-magic categories", ""]
    hinted: dict[str, Counter[str]] = defaultdict(Counter)
    for inv in invs:
        for m in inv["members"]:
            h = _hint(m["magic"], m["ext"])
            if h:
                hinted[h][inv["archive"]] += 1
    for h, c in sorted(hinted.items()):
        L.append(f"- {h}: " + ", ".join(f"{a} x{n}" for a, n in c.items()))
    Path(a.out or DEFAULT_REPORT).write_text("\n".join(L) + "\n")
    print(f"wrote {a.out or DEFAULT_REPORT}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="openrugby_tools")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("list", help="list members of a BIGF archive")
    p.add_argument("archive")
    p.set_defaults(fn=cmd_list)
    p = sub.add_parser("extract", help="extract members + manifest.json")
    p.add_argument("archive")
    p.add_argument(
        "-o", "--out", help=f"output dir (default {DEFAULT_EXTRACT_ROOT}/<archive-name>)"
    )
    p.add_argument("--no-refpack", action="store_true", help="skip RefPack decoding")
    p.set_defaults(fn=cmd_extract)
    p = sub.add_parser("inventory", help="write member inventory JSON per archive")
    p.add_argument("archives", nargs="+")
    p.add_argument("-o", "--out", help="output dir for <archive>.json")
    p.set_defaults(fn=cmd_inventory)
    p = sub.add_parser("report", help="render markdown summary from inventory JSON")
    p.add_argument("--inventory-dir")
    p.add_argument("-o", "--out")
    p.set_defaults(fn=cmd_report)
    p = sub.add_parser("pipeline", help="run the full extract/convert pipeline into one directory")
    pipeline.add_arguments(p)
    p.set_defaults(fn=pipeline.run_from_args)
    a = ap.parse_args(argv)
    try:
        return int(a.fn(a))
    except (BigfError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
