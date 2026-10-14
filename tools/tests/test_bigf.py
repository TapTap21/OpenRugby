from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

import pytest

from openrugby_tools import bigf, cli
from tests.test_refpack import literal_stream


def build_big(members: list[tuple[str, bytes]], trailer: bytes = b"L225") -> bytes:
    idx = b"".join(b"\0" * 8 + n.encode() + b"\0" for n, _ in members) + trailer
    data_start = 16 + len(idx)
    entries = b""
    blob = b""
    for n, d in members:
        entries += struct.pack(">II", data_start + len(blob), len(d)) + n.encode() + b"\0"
        blob += d
    entries += trailer
    total = 16 + len(entries) + len(blob)
    head = b"BIGF" + struct.pack("<I", total) + struct.pack(">II", len(members), data_start)
    return head + entries + blob


@pytest.fixture
def archive(tmp_path: Path) -> Path:
    payload = bytes(range(250)) * 2
    members = [
        ("dir\\a.txt", b"hello world"),
        ("dir/sub/b.bin", b"\x01\x02\x03\x04\x05\x06\x07\x08\x09"),
        ("packed.dat", literal_stream(payload)),
        ("../evil.txt", b"x"),
        ("dir/a.txt", b"dup"),
    ]
    p = tmp_path / "t.big"
    p.write_bytes(build_big(members))
    return p


def test_parse(archive: Path) -> None:
    with bigf.BigfArchive(archive) as a:
        assert [e.name for e in a.entries][:2] == ["dir\\a.txt", "dir/sub/b.bin"]
        assert a.trailer == b"L225"
        assert a.read(a.entries[0]) == b"hello world"


def test_not_bigf(tmp_path: Path) -> None:
    p = tmp_path / "x"
    p.write_bytes(b"NOPE" + b"\0" * 32)
    with pytest.raises(bigf.BigfError):
        bigf.BigfArchive(p)


def test_out_of_range(tmp_path: Path) -> None:
    raw = bytearray(build_big([("a", b"abc")], trailer=b""))
    raw = raw[:-2]  # truncate payload
    p = tmp_path / "t.big"
    p.write_bytes(bytes(raw))
    with pytest.raises(bigf.BigfError):
        bigf.BigfArchive(p)


def test_extract(archive: Path, tmp_path: Path) -> None:
    out = tmp_path / "out"
    with bigf.BigfArchive(archive) as a:
        man = bigf.extract_all(a, out)
    (out / "manifest.json").write_text(json.dumps(man))
    by = {m["name"]: m for m in man}
    assert (out / "dir" / "a.txt").read_bytes() == b"hello world"
    assert (out / "dir" / "a~2.txt").read_bytes() == b"dup"
    assert (out / "evil.txt").exists() and not (tmp_path / "evil.txt").exists()
    assert by["dir\\a.txt"]["sha256"] == hashlib.sha256(b"hello world").hexdigest()
    assert by["dir\\a.txt"]["first8"] == b"hello wo".hex()
    p = by["packed.dat"]
    assert p["refpack"] is True and p["decompressed_size"] == 500
    assert (out / "packed.dat.unpacked").read_bytes() == bytes(range(250)) * 2


def test_cli_list_and_inventory(
    archive: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert cli.main(["list", str(archive)]) == 0
    assert "packed.dat" in capsys.readouterr().out
    inv = tmp_path / "inv"
    assert cli.main(["inventory", str(archive), "-o", str(inv)]) == 0
    data = json.loads((inv / "t.big.json").read_text())
    assert data["member_count"] == 5
    assert any(m["refpack_sig"] for m in data["members"])
    rep = tmp_path / "r.md"
    assert cli.main(["report", "--inventory-dir", str(inv), "-o", str(rep)]) == 0
    assert "Candidate formats" in rep.read_text()


REAL = Path("/home/wernich/Code/games/rugby08/Rugby-08_Win_EN_Full-Rip/Data/motion/moai.viv")


@pytest.mark.skipif(not REAL.exists(), reason="game files not present")
def test_real_moai() -> None:
    with bigf.BigfArchive(REAL) as a:
        assert len(a.entries) == 537
        assert min(e.offset for e in a.entries) == a.index_end + 1
        assert max(e.offset + e.size for e in a.entries) <= a.file_size


def test_extract_file_dir_and_unpacked_collisions(tmp_path: Path) -> None:
    packed = literal_stream(b"abcd")
    members = [
        ("foo", b"file"),
        ("foo/bar", b"nested"),  # parent is already a file
        ("baz/qux", b"q"),
        ("baz", b"after"),  # name already used as a directory
        ("p.dat", packed),
        ("p.dat.unpacked", b"mine"),  # would clobber the decoded sibling
    ]
    arc = tmp_path / "c.big"
    arc.write_bytes(build_big(members))
    out = tmp_path / "out"
    with bigf.BigfArchive(arc) as a:
        man = bigf.extract_all(a, out)
    assert len({m["path"] for m in man}) == len(man)
    by = {m["name"]: (out / str(m["path"])).read_bytes() for m in man}
    assert by["foo"] == b"file" and by["foo/bar"] == b"nested"
    assert by["baz"] == b"after" and by["p.dat.unpacked"] == b"mine"
    assert (out / "p.dat.unpacked").read_bytes() == b"abcd"


def test_cli_reports_errors_without_traceback(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert cli.main(["list", str(tmp_path / "missing.big")]) == 1
    bad = tmp_path / "bad.big"
    bad.write_bytes(b"NOPE" + b"\0" * 32)
    assert cli.main(["extract", str(bad), "-o", str(tmp_path / "o")]) == 1
    assert "error:" in capsys.readouterr().err
