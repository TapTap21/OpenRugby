"""Rugby 08 roster / team / stadium / competition database extractor.

Sources (RefPack-decoded ``data.gob`` members; see ``docs/re/09-players-teams-db.md``):

* ``73cb47d1...rdf`` - binary roster database (observed layout)::

      u32 version   bytes 3,2 must be 0 and byte 1 must be 0x0D (loader 0x4d3070)
      Player[2000]  100-byte records (-> 0x9fb2d0), sorted by id descending, unused zero
      Team[143]     104-byte records (-> 0xa2d0f0), slot index == team id, slot 0 unused
      Created[90]   48-byte created-player slots (-> 0xa2c010), all zero when shipped

  The 100-byte player record is byte-identical to the engine's in-memory player
  stat block (stat getter offsets +0x21..+0x3d), so field offsets below are the
  engine's own.
* ``be2970b0...xml`` - team table (names, abbreviations, colours, string ids).
* ``730eef3f...xml`` - team kit list and per-head appearance table.
* ``119ba3f3...xml`` / ``.csv`` - stadium table (+ legacy CSV with capacities).
* ``*.rsg`` - tournament schedules ("Rugby Schedule Generation" XML).
* ``dc371d84...english`` - HBS string table (team / city / country names).

CLI: ``python -m openrugby_tools.rosterdb [--src extracted/data.gob] [--out extracted/db]``
writes ``players.json``, ``teams.json``, ``stadiums.json``, ``heads.json``,
``competitions.json`` and ``schema.json``.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .loch import parse_strtab

# --------------------------------------------------------------------------- members

RDF_MEMBER = "73cb47d1d69c90f28fd1cc4186ac1926.rdf"
TEAMS_MEMBER = "be2970b0ada8e42cf891ce60ffe69575.xml"
KITS_HEADS_MEMBER = "730eef3fd7726e43de955f21083ab000.xml"
STADIUMS_MEMBER = "119ba3f37fe7a31c2b2ee45ceeafa091.xml"
STADIUMS_CSV_MEMBER = "119ba3f37fe7a31c2b2ee45ceeafa091.csv"
STRINGS_MEMBER = "dc371d84ed78d4cf88a641a8d8abc38a.english"
STADIUM_CONFIG_MEMBER = "20f6cf7cd49d42dd0fe5f86519a0cd95.xml"

# --------------------------------------------------------------------------- layout

RDF_HEADER_SIZE = 4
RDF_VERSION_BYTE1 = 0x0D
PLAYER_SLOTS = 2000
PLAYER_SIZE = 100
TEAM_TABLE_OFFSET = RDF_HEADER_SIZE + PLAYER_SLOTS * PLAYER_SIZE  # 200004
TEAM_SLOTS = 143
TEAM_SIZE = 104
CREATED_TABLE_OFFSET = TEAM_TABLE_OFFSET + TEAM_SLOTS * TEAM_SIZE  # 214876
CREATED_SLOTS = 90
CREATED_SIZE = 48
RDF_SIZE = CREATED_TABLE_OFFSET + CREATED_SLOTS * CREATED_SIZE  # 219196
TACTIC_INVERTED_INDEX = 3  # loader stores 6 - x for team byte +0x5b
SQUAD_SIZE = 30
STARTERS = 15

# Byte offsets inside a player record.
P_ID = 0x00  # u16 player id
P_COMMENTARY_ID = 0x02  # u16 commentary surname id (dat_eng NNNN_<Surname>), 0 = none
P_NAME = 0x04  # char[16] cp1252, NUL padded
P_POS12 = 0x14  # u8: low nibble = primary position, high nibble = secondary
P_POS3 = 0x15  # u8: alternate position
P_WEIGHT = 0x16  # u16: weight in lb minus 100
P_NATION = 0x18  # u32: nationality bitmask (NATION_BITS)
P_HEIGHT = 0x1C  # u8: height in inches minus 60
P_BIRTH_YEAR = 0x1D  # u8: year - 1900
P_BIRTH_MONTH = 0x1E  # u8: 1..12
P_BIRTH_DAY = 0x1F  # u8: bits 0-4 day, bits 5-7 unknown (4 in 99 % of records)
P_PLAYER_TYPE = 0x20  # u8: PLAYER_TYPES index
P_ATTR = 0x21  # 0x21..0x3d attribute bytes (see ATTRIBUTE_OFFSETS)
P_ABILITIES = 0x54  # u16: bits 0..12 SKILLS, bits 13..15 injury-resistance level
P_HEAD = 0x5A  # u16 head (face model) id

# Attribute name -> record offset. Engine stat index (getter 0x6558b0) is the
# position in ENGINE_STAT_ORDER; KickingPower (+0x29) is read directly.
ATTRIBUTE_OFFSETS: dict[str, int] = {
    "attack": 0x21,
    "defense": 0x22,
    "speed": 0x23,
    "acceleration": 0x24,
    "agility": 0x25,
    "handling": 0x26,
    "passing": 0x27,
    "kicking": 0x28,
    "kicking_power": 0x29,
    "goal_kicking": 0x2A,
    "tackling": 0x2B,
    "strength": 0x2C,
    "rucking": 0x2D,
    "scrummaging": 0x2E,
    "hooking": 0x2F,
    "lineouts": 0x30,
    "discipline": 0x31,
    "aggression": 0x32,
    "reserved_33": 0x33,
    "reserved_34": 0x34,
    "reserved_35": 0x35,
    "stamina": 0x36,
    "consistency": 0x37,
    "temperament": 0x38,
    "creativity": 0x39,
    "bravery": 0x3A,
    "fitness": 0x3B,
    "fitness_2": 0x3C,
    "fitness_3": 0x3D,
}
ENGINE_STAT_ORDER: tuple[str, ...] = tuple(
    k for k in ATTRIBUTE_OFFSETS if k != "kicking_power" and not k.startswith("reserved")
)

POSITIONS: tuple[str, ...] = (
    "None",
    "Loosehead Prop",
    "Hooker",
    "Tighthead Prop",
    "Second Row",
    "Blindside Flanker",
    "Openside Flanker",
    "Number Eight",
    "Scrum Half",
    "Fly Half",
    "Wing",
    "Centre",
    "Full Back",
)
SKILLS: tuple[str, ...] = (
    "Command",
    "Passer",
    "Playmaker",
    "Scoring",
    "GoalKicker",
    "TacticalKicking",
    "CrashBall",
    "TackleBreaker",
    "Tackling",
    "BallWinner",
    "DefensiveOrganisation",
    "Scrummager",
    "Jumper",
)
PLAYER_TYPES: tuple[str, ...] = (
    "Default",
    "Scrums",
    "Lineouts",
    "Tackler",
    "Runner",
    "Passer",
    "Kicker",
    "Crasher",
    "Rucks",
    "Goalkicker",
    "Playmaker",
)
# Bit index -> nation (alphabetical original list; Portugal appended at bit 24).
NATION_BITS: tuple[str, ...] = (
    "Argentina",
    "Australia",
    "Canada",
    "Chile",
    "England",
    "Fiji",
    "France",
    "Georgia",
    "Ireland",
    "Italy",
    "Japan",
    "Namibia",
    "New Zealand",
    "Romania",
    "Russia",
    "Samoa",
    "Scotland",
    "South Africa",
    "Spain",
    "Tonga",
    "Tunisia",
    "Uruguay",
    "USA",
    "Wales",
    "Portugal",
)
# Team-record role slots (slot 0 observed = real captains; others inferred).
TEAM_ROLES: tuple[str, ...] = (
    "captain",
    "vice_captain",
    "long_goal_kicker",
    "short_goal_kicker",
    "long_punter",
    "short_punter",
    "kickoff_taker",
)
# Team rating bytes, labels from UI strings 112..121 (order inferred).
TEAM_RATINGS: tuple[str, ...] = (
    "attacking",
    "defending",
    "scrummaging",
    "lineouts",
    "loose",
    "kicking",
    "technique",
    "stamina",
    "flair",
    "overall",
)


class RosterDbError(ValueError):
    pass


# --------------------------------------------------------------------------- records


@dataclass
class Player:
    id: int
    name: str
    commentary_name_id: int
    positions: list[str]
    position_codes: list[int]
    height_in: int
    height_cm: int
    weight_lb: int
    weight_kg: int
    nationalities: list[str]
    nationality_mask: int
    birth_year: int
    birth_month: int
    birth_day: int
    player_type: str
    attributes: dict[str, int]
    abilities: list[str]
    injury_resistance: int
    head_id: int
    unknown: dict[str, int]
    slot: int


@dataclass
class TeamRecord:
    team_id: int
    squad: list[int]
    roles: dict[str, int]
    ratings: dict[str, int]
    tactics_raw: list[int]
    home_stadium: int
    slot: int


@dataclass
class Team:
    id: int
    name: str
    short_name: str
    abbreviation: str
    code_id: str
    type: str
    fe_group: str
    active: bool
    string_id: int | None
    logo: str
    home_colour: list[int]
    away_colour: list[int]
    kits: list[dict[str, str]] = field(default_factory=list)
    starting_xv: list[int] = field(default_factory=list)
    reserves: list[int] = field(default_factory=list)
    roles: dict[str, int] = field(default_factory=dict)
    ratings: dict[str, int] = field(default_factory=dict)
    tactics_raw: list[int] = field(default_factory=list)
    home_stadium: int | None = None


# --------------------------------------------------------------------------- rdf


def _cstr(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("cp1252", "replace")


def parse_player(rec: bytes, slot: int = 0) -> Player | None:
    """Decode one 100-byte player record; returns None for an empty slot."""
    if len(rec) != PLAYER_SIZE:
        raise RosterDbError(f"player record must be {PLAYER_SIZE} bytes")
    if rec[P_NAME] == 0:
        return None
    pos12, pos3 = rec[P_POS12], rec[P_POS3]
    codes = [pos12 & 0x0F, pos12 >> 4, pos3 & 0x0F]  # pos3 high nibble: runtime flag
    nat = struct.unpack_from("<I", rec, P_NATION)[0]
    weight_lb = struct.unpack_from("<H", rec, P_WEIGHT)[0] + 100
    height_in = rec[P_HEIGHT] + 60
    ab = struct.unpack_from("<H", rec, P_ABILITIES)[0]
    ptype = rec[P_PLAYER_TYPE]
    return Player(
        id=struct.unpack_from("<H", rec, P_ID)[0],
        name=_cstr(rec[P_NAME : P_NAME + 16]).rstrip(),
        commentary_name_id=struct.unpack_from("<H", rec, P_COMMENTARY_ID)[0],
        positions=[POSITIONS[c] for c in codes if 0 < c < len(POSITIONS)],
        position_codes=codes,
        height_in=height_in,
        height_cm=height_in * 254 // 100,  # truncated, as the developer dump shows
        weight_lb=weight_lb,
        weight_kg=int(weight_lb * 0.454545),  # dump factor (lb / 2.2, float32), truncated
        nationalities=[n for i, n in enumerate(NATION_BITS) if nat >> i & 1],
        nationality_mask=nat,
        birth_year=1900 + rec[P_BIRTH_YEAR],
        birth_month=rec[P_BIRTH_MONTH],
        birth_day=rec[P_BIRTH_DAY] & 0x1F,
        player_type=PLAYER_TYPES[ptype] if ptype < len(PLAYER_TYPES) else str(ptype),
        attributes={
            k: rec[o] for k, o in ATTRIBUTE_OFFSETS.items() if not k.startswith("reserved")
        },
        abilities=[s for i, s in enumerate(SKILLS) if ab >> i & 1],
        injury_resistance=ab >> 13,
        head_id=struct.unpack_from("<H", rec, P_HEAD)[0],
        unknown={
            "birth_day_hi3": rec[P_BIRTH_DAY] >> 5,
            "b56": rec[0x56],
            "b57": rec[0x57],
            "b58": rec[0x58],
            "b59": rec[0x59],
            "b5c": rec[0x5C],
            "b5d": rec[0x5D],
            "b5e": rec[0x5E],
            "b5f": rec[0x5F],
            "reserved_33_35": rec[0x33] | rec[0x34] << 8 | rec[0x35] << 16,
            # Raw 16-byte name field: the shipped data keeps stale bytes after the NUL
            # and some names end in a space, neither of which survive decoding.
            "name_raw": int.from_bytes(rec[P_NAME : P_NAME + 16], "little"),
        },
        slot=slot,
    )


def parse_team_record(rec: bytes, slot: int = 0) -> TeamRecord | None:
    """Decode one 104-byte team record; returns None for an empty slot."""
    if len(rec) != TEAM_SIZE:
        raise RosterDbError(f"team record must be {TEAM_SIZE} bytes")
    if not any(rec):
        return None
    squad = list(struct.unpack_from(f"<{SQUAD_SIZE}H", rec, 0))
    team_id = struct.unpack_from("<I", rec, 60)[0]
    roles = struct.unpack_from(f"<{len(TEAM_ROLES)}H", rec, 64)
    return TeamRecord(
        team_id=team_id,
        squad=squad,
        roles=dict(zip(TEAM_ROLES, roles, strict=True)),
        ratings=dict(zip(TEAM_RATINGS, rec[78:88], strict=True)),
        tactics_raw=list(rec[88:96]),
        home_stadium=rec[96],
        slot=slot,
    )


def parse_rdf(data: bytes) -> tuple[list[Player], list[TeamRecord]]:
    """Parse the roster database. Returns (players, team records), empty slots skipped."""
    if len(data) != RDF_SIZE:
        raise RosterDbError(f"rdf must be {RDF_SIZE} bytes, got {len(data)}")
    version = struct.unpack_from("<I", data, 0)[0]
    if version >> 16 or (version >> 8) & 0xFF != RDF_VERSION_BYTE1:
        raise RosterDbError(f"bad rdf version 0x{version:08x} (loader requires 0x00000Dxx)")
    players: list[Player] = []
    for i in range(PLAYER_SLOTS):
        off = RDF_HEADER_SIZE + i * PLAYER_SIZE
        p = parse_player(data[off : off + PLAYER_SIZE], i)
        if p is not None:
            players.append(p)
    teams: list[TeamRecord] = []
    for k in range(TEAM_SLOTS):
        off = TEAM_TABLE_OFFSET + k * TEAM_SIZE
        t = parse_team_record(data[off : off + TEAM_SIZE], k)
        if t is None:
            continue
        if t.team_id != k:
            raise RosterDbError(f"team slot {k} holds id {t.team_id}")
        teams.append(t)
    return players, teams


def build_player_record(p: Player) -> bytes:
    """Inverse of parse_player for the decoded fields (unknown bytes from p.unknown)."""
    rec = bytearray(PLAYER_SIZE)
    struct.pack_into("<HH", rec, 0, p.id, p.commentary_name_id)
    raw = p.unknown.get("name_raw")
    raw_name = raw.to_bytes(16, "little") if raw is not None else None
    if raw_name is not None and _cstr(raw_name).rstrip() == p.name:
        rec[P_NAME : P_NAME + 16] = raw_name  # unchanged name: keep the original padding
    else:
        name = p.name.encode("cp1252")[:15]
        rec[P_NAME : P_NAME + len(name)] = name
    c = (p.position_codes + [0, 0, 0])[:3]
    rec[P_POS12] = (c[0] & 0x0F) | (c[1] & 0x0F) << 4
    rec[P_POS3] = c[2]
    struct.pack_into("<H", rec, P_WEIGHT, p.weight_lb - 100)
    struct.pack_into("<I", rec, P_NATION, p.nationality_mask)
    rec[P_HEIGHT] = p.height_in - 60
    rec[P_BIRTH_YEAR] = p.birth_year - 1900
    rec[P_BIRTH_MONTH] = p.birth_month
    rec[P_BIRTH_DAY] = (p.birth_day & 0x1F) | (p.unknown.get("birth_day_hi3", 4) & 7) << 5
    rec[P_PLAYER_TYPE] = PLAYER_TYPES.index(p.player_type) if p.player_type in PLAYER_TYPES else 0
    for k, o in ATTRIBUTE_OFFSETS.items():
        if not k.startswith("reserved"):
            rec[o] = p.attributes.get(k, 0)
    ab = sum(1 << SKILLS.index(s) for s in p.abilities) | (p.injury_resistance & 7) << 13
    struct.pack_into("<H", rec, P_ABILITIES, ab)
    struct.pack_into("<H", rec, P_HEAD, p.head_id)
    for k, o in (("b56", 0x56), ("b57", 0x57), ("b58", 0x58), ("b59", 0x59)):
        rec[o] = p.unknown.get(k, 0)
    res = p.unknown.get("reserved_33_35", 0)
    rec[0x33:0x36] = (res & 0xFFFFFF).to_bytes(3, "little")
    for k, o in (("b5c", 0x5C), ("b5d", 0x5D), ("b5e", 0x5E), ("b5f", 0x5F)):
        rec[o] = p.unknown.get(k, 0)
    return bytes(rec)


def build_team_record(t: TeamRecord) -> bytes:
    rec = bytearray(TEAM_SIZE)
    squad = (t.squad + [0] * SQUAD_SIZE)[:SQUAD_SIZE]
    struct.pack_into(f"<{SQUAD_SIZE}H", rec, 0, *squad)
    struct.pack_into("<I", rec, 60, t.team_id)
    struct.pack_into(f"<{len(TEAM_ROLES)}H", rec, 64, *(t.roles.get(r, 0) for r in TEAM_ROLES))
    rec[78:88] = bytes(t.ratings.get(r, 0) for r in TEAM_RATINGS)
    rec[88:96] = bytes((t.tactics_raw + [0] * 8)[:8])
    rec[96] = t.home_stadium
    return bytes(rec)


def build_rdf(players: list[Player], teams: list[TeamRecord]) -> bytes:
    """Assemble an rdf image (players sorted by id descending, team slot = team id)."""
    out = bytearray(struct.pack("<I", 0x0D00))
    ordered = sorted(players, key=lambda p: -p.id)[:PLAYER_SLOTS]
    for p in ordered:
        out += build_player_record(p)
    out += bytes(PLAYER_SIZE * (PLAYER_SLOTS - len(ordered)))
    slots = [bytes(TEAM_SIZE)] * TEAM_SLOTS
    for t in teams:
        if not 0 < t.team_id < TEAM_SLOTS:
            raise RosterDbError(f"team id {t.team_id} out of range")
        slots[t.team_id] = build_team_record(t)
    return bytes(out) + b"".join(slots) + bytes(CREATED_SLOTS * CREATED_SIZE)


# --------------------------------------------------------------------------- market rating
# Engine players_CalcMarketRating 0x5b0b70 / players_CalcMarketValue 0x5b2640 (observed).
# Group by primary position: weights over stats, plus "w" = (weight_lb - 100) and
# "h" = (height_in - 60) terms already folded into per-unit coefficients.
RATING_WEIGHTS: dict[str, dict[str, float]] = {
    "prop": {
        "w": 0.06,
        "speed": 0.05,
        "handling": 0.03,
        "passing": 0.02,
        "tackling": 0.05,
        "strength": 0.2,
        "rucking": 0.04,
        "scrummaging": 0.35,
        "lineouts": 0.03,
        "stamina": 0.05,
        "consistency": 0.05,
        "temperament": 0.05,
    },
    "hooker": {
        "w": 0.02,
        "speed": 0.05,
        "handling": 0.05,
        "passing": 0.02,
        "tackling": 0.05,
        "strength": 0.07,
        "rucking": 0.1,
        "scrummaging": 0.15,
        "hooking": 0.35,
        "lineouts": 0.03,
        "stamina": 0.05,
        "consistency": 0.02,
        "temperament": 0.01,
    },
    "lock": {
        "h": 0.125,
        "w": 0.008,
        "speed": 0.05,
        "handling": 0.05,
        "passing": 0.02,
        "tackling": 0.03,
        "strength": 0.07,
        "rucking": 0.05,
        "scrummaging": 0.12,
        "lineouts": 0.35,
        "stamina": 0.05,
        "consistency": 0.02,
        "temperament": 0.01,
    },
    "flanker": {
        "w": 0.004,
        "speed": 0.1,
        "acceleration": 0.03,
        "agility": 0.02,
        "handling": 0.04,
        "passing": 0.03,
        "tackling": 0.2,
        "strength": 0.1,
        "rucking": 0.2,
        "scrummaging": 0.03,
        "lineouts": 0.01,
        "stamina": 0.2,
        "consistency": 0.02,
        "temperament": 0.01,
    },
    "number_eight": {
        "h": 0.125,
        "w": 0.008,
        "speed": 0.08,
        "acceleration": 0.02,
        "agility": 0.01,
        "handling": 0.03,
        "passing": 0.04,
        "tackling": 0.15,
        "strength": 0.12,
        "rucking": 0.15,
        "scrummaging": 0.07,
        "lineouts": 0.08,
        "stamina": 0.17,
        "consistency": 0.02,
        "temperament": 0.01,
    },
    "scrum_half": {
        "speed": 0.07,
        "acceleration": 0.1,
        "agility": 0.1,
        "handling": 0.05,
        "passing": 0.33,
        "kicking": 0.1,
        "goal_kicking": 0.07,
        "tackling": 0.03,
        "strength": 0.02,
        "stamina": 0.05,
        "consistency": 0.02,
        "temperament": 0.01,
        "creativity": 0.05,
    },
    "fly_half": {
        "speed": 0.02,
        "acceleration": 0.03,
        "agility": 0.05,
        "handling": 0.1,
        "passing": 0.1,
        "kicking": 0.2,
        "goal_kicking": 0.15,
        "tackling": 0.08,
        "strength": 0.02,
        "stamina": 0.02,
        "consistency": 0.07,
        "temperament": 0.01,
        "creativity": 0.15,
    },
    "wing": {
        "speed": 0.35,
        "acceleration": 0.15,
        "agility": 0.12,
        "handling": 0.05,
        "passing": 0.03,
        "kicking": 0.02,
        "goal_kicking": 0.07,
        "tackling": 0.08,
        "strength": 0.05,
        "stamina": 0.02,
        "consistency": 0.02,
        "temperament": 0.01,
        "creativity": 0.03,
    },
    "centre": {
        "w": 0.02,
        "speed": 0.23,
        "acceleration": 0.03,
        "agility": 0.02,
        "handling": 0.08,
        "passing": 0.09,
        "kicking": 0.07,
        "goal_kicking": 0.07,
        "tackling": 0.13,
        "strength": 0.07,
        "stamina": 0.05,
        "consistency": 0.02,
        "temperament": 0.01,
        "creativity": 0.1,
    },
    "full_back": {
        "w": 0.008,
        "speed": 0.23,
        "acceleration": 0.05,
        "agility": 0.03,
        "handling": 0.1,
        "passing": 0.03,
        "kicking": 0.08,
        "goal_kicking": 0.07,
        "tackling": 0.15,
        "strength": 0.08,
        "stamina": 0.03,
        "consistency": 0.05,
        "temperament": 0.03,
        "creativity": 0.05,
    },
}
RATING_GROUP = {
    1: "prop",
    2: "hooker",
    3: "prop",
    4: "lock",
    5: "flanker",
    6: "flanker",
    7: "number_eight",
    8: "scrum_half",
    9: "fly_half",
    10: "wing",
    11: "centre",
    12: "full_back",
}
RATING_SCALE = {
    "prop": 0.3,
    "hooker": 0.35,
    "lock": 0.4,
    "flanker": 0.45,
    "number_eight": 0.4,
    "scrum_half": 0.4,
    "fly_half": 0.5,
    "wing": 0.5,
    "centre": 0.4,
    "full_back": 0.4,
}
RATING_ABILITY_BONUS = {
    "BallWinner": 20,
    "Command": 20,  # LOCAL:0x5b22f4 adds 20 for byte 0x54 bit 0
    "CrashBall": 10,
    "DefensiveOrganisation": 10,
    "GoalKicker": 35,
    "Jumper": 10,
    "Passer": 15,
    "Playmaker": 20,
    "Scoring": 25,
    "Scrummager": 5,
    "TackleBreaker": 5,
    "Tackling": 10,
    "TacticalKicking": 10,
}
# Static 30-entry player-id list at 0x993508 (.data of the unpacked exe). Listed players skip
# the key-stat multiplier in players_CalcMarketRating and always get market value 1 from
# players_CalcMarketValue (both check the list unconditionally, before anything else).
UNRATED_PLAYER_IDS: frozenset[int] = frozenset(
    {
        26809,
        22361,
        5602,
        7864,
        20528,
        19964,
        8826,
        12290,
        31923,
        29087,
        3925,
        27663,
        23146,
        29309,
        11662,
        475,
        26946,
        16336,
        30524,
        18392,
        20448,
        14333,
        10910,
        229,
        28962,
        12570,
        24515,
        9464,
        1278,
        17469,
    }
)
# (key stat, first value, table, value above table or None, threshold above which it applies)
_KEY_TABLES: dict[str, tuple[str, int, tuple[float, ...], float | None, int]] = {
    "scrum_half": (
        "passing",
        71,
        (
            1.0,
            1.1,
            1.1,
            1.1,
            1.3,
            1.3,
            1.3,
            1.4,
            1.4,
            1.5,
            1.5,
            1.5,
            1.5,
            1.5,
            1.7,
            1.7,
            1.8,
            1.8,
            1.8,
            1.9,
        ),
        2.0,
        90,
    ),
    "fly_half": (
        "kicking",
        74,
        (1.0, 1.2, 1.2, 1.2, 1.2, 1.2, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0),
        2.0,
        85,
    ),
    "wing": (
        "speed",
        85,
        (1.0, 1.0, 1.1, 1.2, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0, 2.1, 2.2, 2.3),
        None,
        255,
    ),
    "centre": (
        "speed",
        85,
        (1.0, 1.0, 1.0, 1.1, 1.1, 1.15, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0, 2.0),
        None,
        255,
    ),
    "full_back": (
        "kick_speed_avg",
        71,
        (1.0, 1.1, 1.1, 1.1, 1.2, 1.2, 1.2, 1.3, 1.4, 1.5, 1.5, 1.6, 1.6, 1.6, 1.7),
        1.7,
        85,
    ),
}


def market_rating(p: Player) -> int:
    """Engine market rating (players_CalcMarketRating), ignoring career overrides."""
    group = RATING_GROUP.get(p.position_codes[0] if p.position_codes else 0)
    a = p.attributes
    if group is None:  # default branch: mean of 23 stats - 30, then x 0 (engine returns 0)
        return 0
    total = 0.0
    for k, wgt in RATING_WEIGHTS[group].items():
        v = p.weight_lb - 100 if k == "w" else p.height_in - 60 if k == "h" else a.get(k, 0)
        total += wgt * v
    total += sum(RATING_ABILITY_BONUS.get(s, 0) for s in p.abilities)
    if p.id in UNRATED_PLAYER_IDS:
        return int(total * RATING_SCALE[group])
    mult = 1.0
    key = _KEY_TABLES.get(group)
    if key is not None:
        stat, first, table, above, thr = key
        x = (a["kicking"] + a["speed"]) // 2 if stat == "kick_speed_avg" else a[stat]
        if above is not None and x > thr:
            mult = above
        elif 0 <= x - first < len(table):
            mult = table[x - first]
    return int(total * RATING_SCALE[group] * mult)


def market_value(rating: int, player_id: int | None = None) -> int:
    """players_CalcMarketValue band (1..41) for a market rating."""
    if player_id in UNRATED_PLAYER_IDS:
        return 1
    for limit, value in ((16, 1), (18, 2), (20, 3), (23, 4), (26, 5), (28, 6), (31, 7), (33, 8)):
        if rating < limit:
            return value
    return min(41, 9 + (rating - 33) // 2)


# --------------------------------------------------------------------------- xml / csv


def _xml(data: bytes) -> ET.Element:
    text = data.decode("cp1252", "replace")
    if text.startswith("<?xml"):
        text = text[text.index("?>") + 2 :]
    return ET.fromstring(text)


def _colour(s: str) -> list[int]:
    try:
        return [int(v) for v in s.split(",")]
    except ValueError:
        return []


def _int_or_none(s: str | None) -> int | None:
    try:
        return int(s) if s not in (None, "") else None
    except ValueError:
        return None


def parse_team_table(data: bytes) -> list[Team]:
    teams: list[Team] = []
    for el in _xml(data).iter("team"):
        a = el.attrib
        teams.append(
            Team(
                id=int(a["Index"]),
                name=a.get("TeamName", ""),
                short_name=a.get("TeamNameShort", a.get("TeamName", "")),
                abbreviation=a.get("Abbreviation", ""),
                code_id=a.get("CodeId", ""),
                type=a.get("Type", ""),
                fe_group=a.get("FeGroup", ""),
                active=a.get("Active", "").lower() == "yes",
                string_id=_int_or_none(a.get("StringTableId")),
                logo=a.get("Logo", ""),
                home_colour=_colour(a.get("HomeColour", "")),
                away_colour=_colour(a.get("AwayColour", "")),
            )
        )
    return teams


_TAG_RE = re.compile(r"<(team|kit|player)\b([^>]*?)/?>", re.S)
_ATTR_RE = re.compile(r'([A-Za-z_][\w]*)\s*=\s*"([^"]*)"')


def parse_kits_and_heads(
    data: bytes,
) -> tuple[dict[int, list[dict[str, str]]], list[dict[str, Any]]]:
    """``730eef3f`` viewer config: team kits by team id, and the head appearance list.

    The shipped file is not well-formed XML (attributes without separating spaces),
    so it is scanned tag by tag.
    """
    text = data.decode("cp1252", "replace")
    kits: dict[int, list[dict[str, str]]] = {}
    heads: list[dict[str, Any]] = []
    current: int | None = None
    for m in _TAG_RE.finditer(text):
        tag, attrs = m.group(1), dict(_ATTR_RE.findall(m.group(2)))
        if tag == "team":
            current = _int_or_none(attrs.get("id"))
            if current is not None:
                kits[current] = []
        elif tag == "kit" and current is not None:
            kits[current].append(attrs)
        elif tag == "player":
            a = {k.lower(): v for k, v in attrs.items()}
            hid = _int_or_none(a.get("location"))
            if hid is None:
                continue
            heads.append(
                {
                    "head_id": hid,
                    "name": a.get("name", "").strip(),
                    "skin": _int_or_none(a.get("skin")),
                    "hair_med": a.get("medhairstyle", ""),
                    "hair_low": a.get("lowhairstyle", ""),
                    "ear_tape": a.get("eartape", "").lower() == "true",
                    "scrum_cap": a.get("scrumcap", "").lower() == "true",
                    "gloves": a.get("gloves", "").lower() == "true",
                }
            )
    return kits, heads


def parse_stadiums(data: bytes, strings: dict[str, str] | None = None) -> list[dict[str, Any]]:
    s = strings or {}
    out: list[dict[str, Any]] = []
    for el in _xml(data).iter("stadium"):
        a = el.attrib
        env = el.find("environment")
        city_id, country_id = _int_or_none(a.get("City")), _int_or_none(a.get("Country"))
        out.append(
            {
                "id": int(a["Index"]),
                "active": a.get("Active", "").lower() == "yes",
                "code_id": a.get("CodeId", ""),
                "name": a.get("StadiumName", ""),
                "string_id": _int_or_none(a.get("StringTableId")),
                "file_name": a.get("FileName", ""),
                "city_string_id": city_id,
                "city": s.get(str(city_id), "") if city_id is not None else "",
                "country_string_id": country_id,
                "country": s.get(str(country_id), "") if country_id is not None else "",
                "home_team": a.get("HomeTeam", ""),
                "fe_gfx_package": a.get("FeGfxPackage", ""),
                "intro_script_anthem": a.get("IntroScriptAnthem", ""),
                "intro_script_normal": a.get("IntroScriptNormal", ""),
                "cameras": [_int_or_none(c.get("Index")) for c in el.iter("camera")],
                "environment": dict(env.attrib) if env is not None else {},
            }
        )
    return out


def parse_stadium_csv(data: bytes) -> list[dict[str, str]]:
    rows = csv.DictReader(io.StringIO(data.decode("cp1252", "replace")))
    return [dict(r) for r in rows if r.get("StadiumName")]


def parse_stadium_config(data: bytes) -> list[dict[str, Any]]:
    """``20f6cf7c`` render config: stadium id -> asset folder (``location``) and enum."""
    out: list[dict[str, Any]] = []
    for m in re.finditer(r"<stadium\b([^>]*?)/?>", data.decode("cp1252", "replace")):
        a = dict(_ATTR_RE.findall(m.group(1)))
        sid = _int_or_none(a.get("id"))
        if sid is not None:
            out.append(
                {
                    "id": sid,
                    "name": a.get("name", ""),
                    "location": a.get("location", ""),
                    "enum": a.get("enum", ""),
                }
            )
    return out


def parse_rsg(data: bytes) -> dict[str, Any]:
    """Tournament schedule: team/location tables and round -> pool -> game fixtures."""
    root = _xml(data)
    t = root.find("tournament")
    if t is None:
        raise RosterDbError("no <tournament> element")

    def _ints(el: ET.Element) -> dict[str, Any]:
        return {k: (int(v) if v.lstrip("-").isdigit() else v) for k, v in el.attrib.items()}

    return {
        "name": t.get("name", ""),
        "teams": [_ints(e) for e in t.iter("team")],
        "locations": [_ints(e) for e in t.iter("location")],
        "rounds": [
            {
                "id": _int_or_none(r.get("id")),
                "pools": [
                    {"id": _int_or_none(p.get("id")), "games": [_ints(g) for g in p.iter("game")]}
                    for p in r.iter("pool")
                ],
            }
            for r in t.iter("round")
        ],
    }


# --------------------------------------------------------------------------- export


def _member(src: Path, name: str) -> bytes:
    for cand in (src / f"{name}.unpacked", src / name):
        if cand.is_file():
            return cand.read_bytes()
    raise FileNotFoundError(src / name)


def schema() -> dict[str, Any]:
    return {
        "positions": list(POSITIONS),
        "skills": list(SKILLS) + ["InjuryResistance (level 0-3, bits 13-15)"],
        "player_types": list(PLAYER_TYPES),
        "nation_bits": list(NATION_BITS),
        "attribute_offsets": {k: o for k, o in ATTRIBUTE_OFFSETS.items()},
        "engine_stat_order": list(ENGINE_STAT_ORDER),
        "team_roles": list(TEAM_ROLES),
        "team_ratings": list(TEAM_RATINGS),
    }


def build_database(src: Path) -> dict[str, Any]:
    """Read all sources from an extracted ``data.gob`` directory; return JSON-ready tables."""
    players, team_recs = parse_rdf(_member(src, RDF_MEMBER))
    try:
        strings = parse_strtab(_member(src, STRINGS_MEMBER))["ids"]
    except FileNotFoundError:
        strings = {}
    teams = {t.id: t for t in parse_team_table(_member(src, TEAMS_MEMBER))}
    kits, heads = parse_kits_and_heads(_member(src, KITS_HEADS_MEMBER))
    for tid, k in kits.items():
        if tid in teams:
            teams[tid].kits = k
    for r in team_recs:
        t = teams.get(r.team_id)
        if t is None:
            t = teams[r.team_id] = Team(
                r.team_id, f"team_{r.team_id}", "", "", "", "", "", False, None, "", [], []
            )
        t.starting_xv = r.squad[:STARTERS]
        t.reserves = r.squad[STARTERS:]
        t.roles, t.ratings, t.tactics_raw = r.roles, r.ratings, r.tactics_raw
        t.home_stadium = r.home_stadium
    member_of: dict[int, list[int]] = {}
    for r in team_recs:
        for pid in r.squad:
            if pid:
                member_of.setdefault(pid, []).append(r.team_id)
    pl = []
    for p in players:
        d = asdict(p)
        d["teams"] = member_of.get(p.id, [])
        d["market_rating"] = market_rating(p)
        d["market_value"] = market_value(d["market_rating"], p.id)
        pl.append(d)
    stadiums = parse_stadiums(_member(src, STADIUMS_MEMBER), strings)
    try:
        legacy = parse_stadium_csv(_member(src, STADIUMS_CSV_MEMBER))
    except FileNotFoundError:
        legacy = []
    try:
        render_cfg = parse_stadium_config(_member(src, STADIUM_CONFIG_MEMBER))
    except FileNotFoundError:
        render_cfg = []
    comps = []
    rsg_names = {f.name.removesuffix(".unpacked") for f in src.glob("*.rsg*")}
    for name in sorted(n for n in rsg_names if n.endswith(".rsg")):
        c = parse_rsg(_member(src, name))
        c["member"] = name
        comps.append(c)
    return {
        "players": pl,
        "teams": [asdict(teams[k]) for k in sorted(teams)],
        "stadiums": {"stadiums": stadiums, "render_config": render_cfg, "legacy_csv": legacy},
        "heads": heads,
        "competitions": comps,
        "schema": schema(),
    }


def export(src: Path, out: Path) -> dict[str, int]:
    db = build_database(src)
    out.mkdir(parents=True, exist_ok=True)
    counts: dict[str, int] = {}
    for key, value in db.items():
        tmp = out / f"{key}.json.tmp"
        tmp.write_text(json.dumps(value, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        os.replace(tmp, out / f"{key}.json")
        counts[key] = len(value)
    return counts


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="openrugby_tools.rosterdb", description=__doc__.split("\n")[0]
    )
    ap.add_argument(
        "--src", type=Path, default=Path("extracted/data.gob"), help="extracted data.gob dir"
    )
    ap.add_argument("--out", type=Path, default=Path("extracted/db"), help="output directory")
    a = ap.parse_args(argv)
    if not a.src.is_dir():
        print(f"error: {a.src} is not a directory", file=sys.stderr)
        return 2
    try:
        counts = export(a.src, a.out)
    except (FileNotFoundError, RosterDbError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(json.dumps(counts, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
