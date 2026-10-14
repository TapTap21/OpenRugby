"""Pipeline tests on a tiny synthetic Rugby 08 install (no game files needed)."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

import pytest

from openrugby_tools import cli, eagl, motion, pipeline
from tests.test_bigf import build_big
from tests.test_eagl import build_elf
from tests.test_fsh import _bitmap, _shpi
from tests.test_motion import make_frames
from tests.test_refpack import literal_stream

pytest.importorskip("PIL.Image")


def _shpi_blob(name: str) -> bytes:
    return _shpi([("tex1", _bitmap(0x7D, 1, 1, b"\x10\x20\x30\xff", name=name))])


@pytest.fixture
def game(tmp_path: Path) -> Path:
    root = tmp_path / "game"
    (root / "Data" / "motion").mkdir(parents=True)
    (root / "Rugby08.exe").write_bytes(b"MZ fake")
    inner = build_big([("inner/leaf.fsh", _shpi_blob("leafname")), ("note.txt", b"hi")])
    data_gob = build_big(
        [
            ("tex/a.fsh", literal_stream(_shpi_blob("packedname"))),  # RefPack'd SHPI
            ("nested.big", inner),
            ("readme.txt", b"hello"),
        ]
    )
    (root / "Data" / "data.gob").write_bytes(data_gob)
    (root / "Data" / "motion" / "data.gob").write_bytes(data_gob)  # byte-identical copy
    (root / "Data" / "motion" / "script.big").write_bytes(build_big([("s.lua", b"x=1")]))
    return root


@pytest.fixture(autouse=True)
def no_audio_tools(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(pipeline, "locate_audio_tools", lambda: (None, ["ffmpeg not found"]))


def run(game: Path, out: Path, *extra: str) -> tuple[int, list[pipeline.StageResult]]:
    stages = ",".join(pipeline.STAGES)
    for a in extra:
        if a.startswith("--stages="):
            stages = a.split("=", 1)[1]
    return pipeline.run_pipeline(
        game, out, pipeline.parse_stages(stages), workers=1, force="--force" in extra
    )


def by_name(results: list[pipeline.StageResult]) -> dict[str, pipeline.StageResult]:
    return {r.name: r for r in results}


def test_full_run_and_incremental(game: Path, tmp_path: Path) -> None:
    out = tmp_path / "out"
    code, results = run(game, out)
    r = by_name(results)
    assert code == 0, [x.failures for x in results]
    assert (out / ".gdignore").is_file()
    assert (out / "pipeline.json").is_file()
    # archives: top-level, duplicate copy skipped, nested BIGF recursed
    assert r["archives"].status == "ok"
    assert r["archives"].counts["archives"] == 2
    assert r["archives"].counts["nested archives"] == 1
    assert (out / "data.gob" / "manifest.json").is_file()
    assert (out / "data.gob" / "tex" / "a.fsh.unpacked").is_file()
    assert (out / "data.gob.nested" / "nested.big" / "inner" / "leaf.fsh").is_file()
    assert (out / "script.big" / "s.lua").read_bytes() == b"x=1"
    # textures: RefPack'd SHPI and the nested SHPI both decoded
    assert r["textures"].counts == {"sources": 2, "png": 2}
    pngs = sorted(p.name for p in (out / "textures").rglob("*.png"))
    assert pngs == ["leafname.png", "packedname.png"]
    # audio skipped (not crashed) without tools; models run with nothing to convert
    assert r["audio"].status == "skipped" and r["audio"].notes
    assert r["models"].status == "ok" and r["models"].counts["objects"] == 0
    assert (out / "models" / "index.json").is_file()

    # second run: everything incremental
    code2, results2 = run(game, out)
    r2 = by_name(results2)
    assert code2 == 0
    assert r2["archives"].status == "unchanged"
    assert r2["textures"].status == "unchanged"
    assert r2["models"].status == "unchanged"
    assert r2["textures"].counts == r["textures"].counts

    # a changed input re-runs the dependent stages
    (game / "Data" / "motion" / "script.big").write_bytes(build_big([("s.lua", b"x=2")]))
    _, results3 = run(game, out)
    r3 = by_name(results3)
    assert r3["archives"].status == "ok"
    assert (out / "script.big" / "s.lua").read_bytes() == b"x=2"
    assert r3["textures"].status == "ok"

    # --force rebuilds everything
    _, results4 = run(game, out, "--force")
    assert by_name(results4)["textures"].status == "ok"
    assert by_name(results4)["archives"].status == "ok"


def test_stage_subset_and_missing_prereq(game: Path, tmp_path: Path) -> None:
    out = tmp_path / "out"
    code, results = run(game, out, "--stages=textures")
    assert code == 1
    assert results[0].failed and "archives stage" in results[0].failures[0]
    assert (out / ".gdignore").is_file()
    code, _ = run(game, out, "--stages=archives")
    assert code == 0
    manifest = json.loads((out / "pipeline.json").read_text())
    rec = manifest["stages"]["archives"]["sources"]["Data/data.gob"]
    assert rec["state"] == "complete" and len(rec["sha256"]) == 64 and rec["nested_archives"] == 1


def test_rejects_non_install_and_game_dir_output(game: Path, tmp_path: Path) -> None:
    empty = tmp_path / "empty"
    empty.mkdir()
    with pytest.raises(pipeline.PipelineError, match="Rugby08.exe"):
        pipeline.run_pipeline(empty, tmp_path / "o1")
    (empty / "Rugby08.exe").write_bytes(b"MZ")
    with pytest.raises(pipeline.PipelineError, match="Data"):
        pipeline.run_pipeline(empty, tmp_path / "o2")
    with pytest.raises(pipeline.PipelineError, match="inside the game install"):
        pipeline.run_pipeline(game, game / "Data" / "out")
    assert not (game / "Data" / "out").exists()


def test_symlinked_install(game: Path, tmp_path: Path) -> None:
    link = tmp_path / "original"
    link.mkdir()
    (link / "Rugby08.exe").symlink_to(game / "Rugby08.exe")
    (link / "Data").symlink_to(game / "Data")
    out = tmp_path / "out"
    code, results = pipeline.run_pipeline(link, out, ["archives"], workers=1)
    assert code == 0 and by_name(results)["archives"].counts["archives"] == 2
    # output that resolves into the real install through the link is refused
    with pytest.raises(pipeline.PipelineError):
        pipeline.run_pipeline(link, link / "Data" / "x")


def test_cli_subcommand_and_exit_codes(game: Path, tmp_path: Path, capsys) -> None:
    out = tmp_path / "out"
    rc = cli.main(
        ["pipeline", "--game-dir", str(game), "--out", str(out), "--stages", "archives,textures"]
    )
    assert rc == 0
    text = capsys.readouterr().out
    assert "stage" in text and "archives" in text and "total:" in text
    assert cli.main(["pipeline", "--game-dir", str(tmp_path), "--out", str(out)]) == 2
    assert (
        cli.main(["pipeline", "--game-dir", str(game), "--out", str(out), "--stages", "bad"]) == 2
    )


# ---------------------------------------------------------------------------
# animations stage
# ---------------------------------------------------------------------------


def _clip(frames: int, shift: int = 0) -> bytes:
    rows = make_frames(frames)
    for row in rows:
        row[12] += shift  # first rotation channel; makes the content distinct
    return motion.encode_clip(rows)


def _skeleton_elf(bones: int = 26) -> bytes:
    """Synthetic ``!skel.o``: a chain of identity bones named ``bone0``..``boneN``."""
    data = bytearray(0x10 + 112 * bones)
    struct.pack_into("<I", data, 0, eagl.SKELETON_MAGIC)
    struct.pack_into("<I", data, 8, bones)
    for i in range(bones):
        r = 0x10 + 112 * i
        struct.pack_into("<3f", data, r, 1.0, 1.0, 1.0)
        struct.pack_into("<i", data, r + 12, i - 1)  # bone 0 is the root (parent -1)
        struct.pack_into("<4f", data, r + 16, 0.0, 0.0, 0.0, 1.0)
        struct.pack_into("<16f", data, r + 48, *[1.0 if j % 5 == 0 else 0.0 for j in range(16)])
    return build_elf(bytes(data), [("__Skeleton:::SK", 0, True)], [])


def _anim_game(root: Path, members: list[tuple[str, bytes]]) -> Path:
    (root / "Data").mkdir(parents=True, exist_ok=True)
    (root / "Rugby08.exe").write_bytes(b"MZ fake")
    (root / "Data" / "data.gob").write_bytes(build_big(members))
    return root


@pytest.fixture
def anim_members() -> list[tuple[str, bytes]]:
    return [
        ("anim/HFOAAA2", _clip(12)),
        ("anim/copy/HFOAAA2", _clip(12)),  # byte-identical copy: deduplicated
        ("anim/alt/HFOAAA2", _clip(9, shift=5)),  # same name, other content: suffixed
        ("anim/OTHER01", _clip(20)),
        ("anim/notclip.bin", b"hello"),
        ("!skel.o", _skeleton_elf()),
    ]


def test_animations_dedup_index_and_incremental(
    tmp_path: Path, anim_members: list[tuple[str, bytes]]
) -> None:
    game = _anim_game(tmp_path / "game", anim_members)
    out = tmp_path / "out"
    code, results = pipeline.run_pipeline(game, out, ["archives", "animations"], workers=1)
    r = by_name(results)
    assert code == 0, [x.failures for x in results]
    assert r["animations"].status == "ok"
    assert r["animations"].counts == {"clips": 3, "duplicates": 1, "frames": 12 + 9 + 20}

    index = json.loads((out / "animations" / "index.json").read_text())["animations"]
    assert len(index) == 3
    sha = {n: hashlib.sha256(b).hexdigest() for n, b in (("a", _clip(12)), ("c", _clip(9, 5)))}
    by_sha = {e["sha256"]: e for e in index}
    a = by_sha[sha["a"]]
    assert a["name"] == "HFOAAA2"
    assert a["sources"] == ["data.gob/anim/HFOAAA2", "data.gob/anim/copy/HFOAAA2"]
    assert a["frames"] == 12 and a["bones_animated"] == 26 and a["error"] is None
    assert a["duration_s"] == pytest.approx(11 / 15, abs=1e-6)
    assert a["has_root_motion"] is True
    c = by_sha[sha["c"]]
    assert c["name"] == "HFOAAA2" and c["frames"] == 9
    # the bare name goes to the collision that sorts first by sha; the other gets a suffix
    first, other = sorted([sha["a"], sha["c"]])
    assert by_sha[first]["gltf"] == "HFOAAA2.gltf"
    assert by_sha[other]["gltf"] == f"HFOAAA2-{other[:8]}.gltf"
    assert by_sha[other]["gltf"] != by_sha[first]["gltf"]
    assert sorted(e["gltf"] for e in index) == sorted(
        ["HFOAAA2.gltf", f"HFOAAA2-{other[:8]}.gltf", "OTHER01.gltf"]
    )
    for e in index:
        assert (out / "animations" / e["gltf"]).is_file()
        assert (out / "animations" / e["gltf"].replace(".gltf", ".bin")).is_file()

    gltf = json.loads((out / "animations" / a["gltf"]).read_text())
    assert [x["name"] for x in gltf["animations"]] == ["HFOAAA2"]
    assert len(gltf["animations"][0]["channels"]) == 26 + 1  # 26 rotations + hips translation

    # second run is incremental; --force rebuilds
    _, again = pipeline.run_pipeline(game, out, ["archives", "animations"], workers=1)
    assert by_name(again)["animations"].status == "unchanged"
    assert by_name(again)["animations"].counts == r["animations"].counts
    _, forced = pipeline.run_pipeline(game, out, ["archives", "animations"], workers=1, force=True)
    assert by_name(forced)["animations"].status == "ok"


def test_animations_failures_are_counted_and_retried(
    tmp_path: Path, anim_members: list[tuple[str, bytes]]
) -> None:
    game = tmp_path / "game"
    _anim_game(game, anim_members + [("anim/BADCLIP", b"\x01\x0b" + b"\0" * 40)])
    out = tmp_path / "out"
    code, results = pipeline.run_pipeline(game, out, ["archives", "animations"], workers=1)
    r = by_name(results)
    assert code == 1 and r["animations"].failed
    assert any("BADCLIP" in f for f in r["animations"].failures)
    index = json.loads((out / "animations" / "index.json").read_text())["animations"]
    bad = [e for e in index if e["name"] == "BADCLIP"]
    assert len(bad) == 1 and bad[0]["error"] and bad[0]["gltf"] is None
    assert r["animations"].counts["clips"] == 3  # the good clips still convert

    # a failed stage is never "unchanged": fixing the input re-runs it to success
    _anim_game(game, anim_members)
    code, results = pipeline.run_pipeline(game, out, ["archives", "animations"], workers=1)
    assert code == 0 and by_name(results)["animations"].status == "ok"


def test_animations_without_skeleton_fails(tmp_path: Path) -> None:
    game = _anim_game(tmp_path / "game", [("anim/HFOAAA2", _clip(5))])
    code, results = pipeline.run_pipeline(
        game, tmp_path / "out", ["archives", "animations"], workers=1
    )
    r = by_name(results)
    assert code == 1 and r["animations"].status == "failed"
    assert "!skel.o not found" in r["animations"].failures[0]


def test_animations_noop_without_clips(game: Path, tmp_path: Path) -> None:
    code, results = run(game, tmp_path / "out", "--stages=archives,animations")
    r = by_name(results)
    assert code == 0 and r["animations"].status == "ok" and r["animations"].counts["clips"] == 0
