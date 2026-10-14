"""Synthetic-data tests for openrugby_tools.pbp (no real game file needed)."""

import json
import struct

import pytest

from openrugby_tools import pbp


def build(names=("C_ONE", "M_TWO"), extra_rule=True) -> bytes:
    n = len(names)
    # record 0: simple, 1 rule; record 1: 2 rules, one with preamble
    rec0 = struct.pack("<4H4B", 0, 200, 500, 1, 0, 100, 0, 0)
    rec0 += struct.pack("<HH", 4, 0)
    rec0 += struct.pack("<2BH4I", 0x39, 0x64, 4, 0, 3, 0, 0)
    rec1 = struct.pack("<4H4B", 1, 200, 501, 2, 16, 100, 0, 1)
    pre = bytes.fromhex("ff010400")
    r_a = struct.pack("<2BH4I", 0x39, 0x64, 4, 1, 4, 8, 30) + struct.pack("<I", 0)
    r_b = struct.pack("<2BH4I", 0x39, 0x64, 4, 1, 4, 1, 31)
    first = (12 + 4 + len(pre)) // 4
    rec1 += struct.pack("<HH", first, first + len(r_a) // 4) + pre + r_a + r_b
    tab_end = 0x18 + 2 * n
    tab_end += -tab_end % 4
    o0 = tab_end
    o1 = o0 + len(rec0)
    end = o1 + len(rec1)
    head = struct.pack("<III", 0x073C1203, end, 0) + struct.pack("<6H", 294, 0xDE04, n, 0, 100, 500)
    table = struct.pack(f"<{n}H", o0 // 4, o1 // 4)
    body = head + table
    body += b"\0" * (o0 - len(body)) + rec0 + rec1
    pool = b""
    ents = b""
    for nm in names:
        ents += struct.pack("<IHH", len(pool), 0x1E61, 0x1234) + b"\0" * 24
        pool += nm.encode() + b"\0"
    return body + ents + pool


def test_parse_basic():
    p = pbp.parse(build())
    assert p.event_count == 2
    assert p.size == p.covered_bytes
    e0, e1 = p.events
    assert (e0.name, e1.name) == ("C_ONE", "M_TWO")
    assert (e1.field_b, e1.flags, e1.y) == (501, 16, 1)
    assert e1.preamble == "ff010400"
    assert len(e1.rules) == 2
    assert e1.rules[0].words == [1, 4, 8, 30, 0]
    assert e1.rules[1].words == [1, 4, 1, 31]
    assert e0.rules[0].kind == 0x39 and e0.rules[0].percent == 100


def test_bad_tag():
    b = bytearray(build())
    end = struct.unpack_from("<I", b, 4)[0]
    struct.pack_into("<H", b, end + 4, 1)
    with pytest.raises(pbp.PbpError):
        pbp.parse(bytes(b))


def test_truncated():
    with pytest.raises(pbp.PbpError):
        pbp.parse(b"\0" * 8)


def test_cli_json(tmp_path):
    src = tmp_path / "x.evt"
    src.write_bytes(build())
    out = tmp_path / "o.json"
    assert pbp.main([str(src), "-o", str(out)]) == 0
    data = json.loads(out.read_text())
    assert data["event_count"] == 2
    assert data["events"][1]["rules"][0]["words"][3] == 30
