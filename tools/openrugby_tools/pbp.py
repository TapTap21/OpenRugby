"""Parser for Rugby 08 ``Audio/pbp.evt`` (play-by-play commentary event table).

Format (little endian; observed on the English file, 78375 bytes).  Field
meanings other than structure are inferred or unknown, see
``.omc/research/gamedata/pbp-notes.md``.

    0x00  u32  magic/version word  (03 12 3c 07)
    0x04  u32  end_of_records: file offset of the name-hash table
    0x08  u32  zero (unknown)
    0x0c  u16  unknown (0x0126 = 294)
    0x0e  u16  unknown (0xde04)
    0x10  u16  event_count (612)
    0x12  u16  unknown (0)
    0x14  u16  unknown (100)
    0x16  u16  unknown (500)
    0x18  u16[event_count]  record_table: record start offset / 4 (ascending)
    ...   records (variable length) starting at record_table[0]*4 and
          ending at end_of_records
    end_of_records: event_count * 32-byte name entries
          u32 name_offset (into string pool), u16 tag (0x1e61 = 7777),
          u16 hash16, 24 zero bytes
    then  string pool: NUL separated names, e.g. ``C_KNOCK_ON_DROP_CATCH``
          (``C_`` colour commentator, ``M_`` main/play-by-play: inferred)

Record (event), start = record_table[i]*4:
    u16 id          event id; sparse (5 unused ids in the English file).
                    Inferred: name index = id - (unused ids below id)
    u16 field_a     200 almost always (unknown; priority/weight?)
    u16 field_b     500 / 501 (unknown; cooldown ms?)
    u16 rule_count
    u8  flags, u8 percent(100), u8 x, u8 y   (unknown meaning)
    u16 rule_offsets[rule_count]  (record-relative offset / 4), padded to 4 B
    ... preamble bytes (optional, kept raw) up to first rule
    rules, each: u8 kind (0x39 usually), u8 percent (0x64 usually), u16 n
    (unknown; NOT a word count), then
    u32 words up to the next rule start (or record end).  Word semantics
    are unknown (some look like bitmasks and sound/clip ids).
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import asdict, dataclass, field

NAME_TAG = 0x1E61


class PbpError(ValueError):
    pass


@dataclass
class Rule:
    offset: int  # absolute file offset
    kind: int  # first byte, 0x39 on 94% of rules (unknown meaning)
    percent: int  # second byte, 0x64 = 100 on 94% of rules (inferred probability)
    count: int
    words: list[int]  # all u32 words after the 4-byte rule header


@dataclass
class Event:
    index: int
    offset: int
    size: int
    id: int
    name: str
    field_a: int
    field_b: int
    flags: int
    percent: int
    x: int
    y: int
    rule_offsets: list[int]
    preamble: str  # hex
    rules: list[Rule] = field(default_factory=list)


@dataclass
class PbpFile:
    magic: int
    end_of_records: int
    header_unknown: list[int]
    event_count: int
    events: list[Event]
    size: int
    covered_bytes: int


def _u16(d: bytes, o: int) -> int:
    return struct.unpack_from("<H", d, o)[0]


def _u32(d: bytes, o: int) -> int:
    return struct.unpack_from("<I", d, o)[0]


def parse_record(d: bytes, start: int, end: int, index: int, name: str) -> Event:
    if end - start < 12:
        raise PbpError(f"record {index} too short")
    rid, fa, fb, n = struct.unpack_from("<4H", d, start)
    flags, pct, x, y = struct.unpack_from("<4B", d, start + 8)
    offs = list(struct.unpack_from(f"<{n}H", d, start + 12)) if n else []
    p = start + 12 + 2 * n
    p = start + ((p - start + 3) & ~3)
    first = start + offs[0] * 4 if offs else end
    if first < p or first > end:
        raise PbpError(f"record {index}: bad first rule offset")
    ev = Event(
        index, start, end - start, rid, name, fa, fb, flags, pct, x, y, offs, d[p:first].hex()
    )
    bounds = [start + o * 4 for o in offs] + [end]
    for a, b in zip(bounds, bounds[1:], strict=False):
        if b < a + 4:
            raise PbpError(f"record {index}: bad rule bounds")
        kind, pct_, cnt = struct.unpack_from("<2BH", d, a)
        nw = (b - a - 4) // 4
        words = list(struct.unpack_from(f"<{nw}I", d, a + 4))
        ev.rules.append(Rule(a, kind, pct_, cnt, words))
    return ev


def parse(d: bytes) -> PbpFile:
    if len(d) < 0x18:
        raise PbpError("file too short")
    magic = _u32(d, 0)
    end_rec = _u32(d, 4)
    unk = [_u32(d, 8), _u16(d, 0x0C), _u16(d, 0x0E), _u16(d, 0x12), _u16(d, 0x14), _u16(d, 0x16)]
    count = _u16(d, 0x10)
    tab_end = 0x18 + 2 * count
    if tab_end > len(d) or end_rec + 32 * count > len(d):
        raise PbpError("table exceeds file")
    offs = [o * 4 for o in struct.unpack_from(f"<{count}H", d, 0x18)]
    pool = end_rec + 32 * count
    names = []
    for i in range(count):
        no, tag, _h = struct.unpack_from("<IHH", d, end_rec + 32 * i)
        if tag != NAME_TAG:
            raise PbpError(f"name entry {i}: unexpected tag {tag:#x}")
        e = d.index(b"\0", pool + no)
        names.append(d[pool + no : e].decode("latin-1"))
    bounds = offs + [end_rec]
    # Event ids are sparse (0..max with a few unused ids); the name table is
    # dense in id order, so name_index = id - (number of unused ids below it).
    ids = [_u16(d, o) for o in offs]
    if len(set(ids)) != count:
        raise PbpError("duplicate event ids")
    unused = [i for i in range(max(ids) + 1) if i not in set(ids)]
    events = []
    covered = tab_end
    for i in range(count):
        ev = parse_record(d, bounds[i], bounds[i + 1], i, "")
        ni = ev.id - sum(1 for u in unused if u < ev.id)
        if not 0 <= ni < count:
            raise PbpError(f"record {i}: id out of range")
        ev.name = names[ni]
        covered += ev.size
        events.append(ev)
    covered += 32 * count + (len(d) - pool)
    return PbpFile(magic, end_rec, unk, count, events, len(d), min(covered, len(d)))


def to_json(p: PbpFile) -> str:
    return json.dumps(asdict(p), indent=1)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m openrugby_tools.pbp", description="Parse Rugby 08 pbp.evt to JSON"
    )
    ap.add_argument("file")
    ap.add_argument("-o", "--out")
    a = ap.parse_args(argv)
    with open(a.file, "rb") as f:
        p = parse(f.read())
    s = to_json(p)
    if a.out:
        with open(a.out, "w") as f:
            f.write(s)
    else:
        sys.stdout.write(s + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
