import json
import struct

import pytest

from openrugby_tools import loch, rosterdb
from openrugby_tools.rosterdb import Player, TeamRecord


def _player(pid: int = 28321, name: str = "A.Test^") -> Player:
    attrs = {
        k: (i * 3) % 101
        for i, k in enumerate(rosterdb.ATTRIBUTE_OFFSETS)
        if not k.startswith("reserved")
    }
    return Player(
        id=pid,
        name=name,
        commentary_name_id=1179,
        positions=["Scrum Half", "Fly Half"],
        position_codes=[8, 9, 0],
        height_in=69,
        height_cm=175,
        weight_lb=171,
        weight_kg=78,
        nationalities=["Argentina", "Italy"],
        nationality_mask=(1 << 0) | (1 << 9),
        birth_year=1974,
        birth_month=8,
        birth_day=22,
        player_type="Passer",
        attributes=attrs,
        abilities=["Passer", "BallWinner", "Jumper"],
        injury_resistance=3,
        head_id=41047,
        unknown={"birth_day_hi3": 4},
        slot=0,
    )


def _team(tid: int, squad: list[int]) -> TeamRecord:
    return TeamRecord(
        team_id=tid,
        squad=squad,
        roles=dict.fromkeys(rosterdb.TEAM_ROLES, squad[0]),
        ratings={r: 50 + i for i, r in enumerate(rosterdb.TEAM_RATINGS)},
        tactics_raw=[8, 0, 0, 4, 4, 6, 1, 2],
        home_stadium=14,
        slot=tid,
    )


def test_player_record_offsets():
    rec = rosterdb.build_player_record(_player())
    assert len(rec) == rosterdb.PLAYER_SIZE
    assert struct.unpack_from("<HH", rec, 0) == (28321, 1179)
    assert rec[4:11] == b"A.Test^"
    assert rec[0x14] == 0x98 and rec[0x15] == 0  # pos1 SH (8) low nibble, pos2 FH (9) high
    assert struct.unpack_from("<H", rec, 0x16)[0] == 71  # 171 lb - 100
    assert struct.unpack_from("<I", rec, 0x18)[0] == 0x201
    assert rec[0x1C] == 9  # 69 in - 60
    assert (rec[0x1D], rec[0x1E], rec[0x1F] & 0x1F, rec[0x1F] >> 5) == (74, 8, 22, 4)
    assert rec[0x20] == rosterdb.PLAYER_TYPES.index("Passer")
    assert rec[0x29] == _player().attributes["kicking_power"]
    assert rec[0x33:0x36] == b"\0\0\0"
    ab = struct.unpack_from("<H", rec, 0x54)[0]
    assert ab & 0x1FFF == (1 << 1) | (1 << 9) | (1 << 12) and ab >> 13 == 3
    assert struct.unpack_from("<H", rec, 0x5A)[0] == 41047


def test_player_roundtrip():
    p = _player()
    q = rosterdb.parse_player(rosterdb.build_player_record(p))
    assert q is not None
    for f in ("id", "name", "positions", "weight_lb", "height_in", "nationalities", "birth_day"):
        assert getattr(q, f) == getattr(p, f)
    assert q.attributes == p.attributes
    assert q.abilities == ["Passer", "BallWinner", "Jumper"]
    assert q.injury_resistance == 3 and q.player_type == "Passer"
    assert q.height_cm == 175 and q.weight_kg == 78


def test_engine_stat_order_matches_getter():
    # getter 0x6558b0: idx 0..7 -> +0x21.., idx 8..16 -> +0x2a.., idx 17..24 -> +0x36..+0x3d
    offs = [rosterdb.ATTRIBUTE_OFFSETS[k] for k in rosterdb.ENGINE_STAT_ORDER]
    assert offs == list(range(0x21, 0x29)) + list(range(0x2A, 0x33)) + list(range(0x36, 0x3E))
    assert rosterdb.ENGINE_STAT_ORDER[20] == "creativity"


def test_empty_and_bad_records():
    assert rosterdb.parse_player(bytes(100)) is None
    assert rosterdb.parse_team_record(bytes(104)) is None
    with pytest.raises(rosterdb.RosterDbError):
        rosterdb.parse_player(bytes(99))


def test_rdf_roundtrip_and_order():
    players = [_player(100, "B.Low"), _player(30000, "A.High")]
    squad = [30000, 100] + [0] * 28
    blob = rosterdb.build_rdf(players, [_team(3, squad)])
    assert len(blob) == rosterdb.RDF_SIZE == 219196
    ps, ts = rosterdb.parse_rdf(blob)
    assert [p.id for p in ps] == [30000, 100]  # stored by id descending
    assert len(ts) == 1 and ts[0].team_id == 3 and ts[0].squad == squad
    assert ts[0].roles["captain"] == 30000 and ts[0].home_stadium == 14
    assert ts[0].ratings["overall"] == 59


def test_team_slot_mismatch_rejected():
    blob = bytearray(rosterdb.build_rdf([], [_team(2, [1] + [0] * 29)]))
    struct.pack_into("<I", blob, rosterdb.TEAM_TABLE_OFFSET + 2 * rosterdb.TEAM_SIZE + 60, 9)
    with pytest.raises(rosterdb.RosterDbError):
        rosterdb.parse_rdf(bytes(blob))


def test_bad_version_and_size():
    blob = bytearray(rosterdb.build_rdf([], []))
    struct.pack_into("<I", blob, 0, 0x0E00)
    with pytest.raises(rosterdb.RosterDbError):
        rosterdb.parse_rdf(bytes(blob))
    with pytest.raises(rosterdb.RosterDbError):
        rosterdb.parse_rdf(bytes(blob[:-1]))


def test_kits_and_heads_tolerates_glued_attributes():
    xml = (
        b'<config><teams><team name="Argentina" location="argentina" id="1">'
        b'<kit name="Main" location="homekit" collar="A"/></team></teams><players>'
        b'<player medhairstyle="1_15"lowhairstyle="1_15"location="41006"name="Res 1 "skin="4"'
        b'eartape="False"scrumCap="True"gloves="FALSE"/></players></config>'
    )
    kits, heads = rosterdb.parse_kits_and_heads(xml)
    assert kits == {1: [{"name": "Main", "location": "homekit", "collar": "A"}]}
    assert heads == [
        {
            "head_id": 41006,
            "name": "Res 1",
            "skin": 4,
            "hair_med": "1_15",
            "hair_low": "1_15",
            "ear_tape": False,
            "scrum_cap": True,
            "gloves": False,
        }
    ]


def test_rsg():
    xml = (
        b'<?xml version="1.0"?><hbtool><tournament name="Six Nations" rounds="1">'
        b'<locations><location id="0" alias="Twickenham" Index="14"/></locations>'
        b'<teams><team id="0" alias="England" Index="5"/></teams>'
        b'<round id="0"><pool games="1" id="0"><game id="0" location="0" hometeam="0" awayteam="0"'
        b' year="2006" month="2" day="4" environment="2"/></pool></round></tournament></hbtool>'
    )
    r = rosterdb.parse_rsg(xml)
    assert r["name"] == "Six Nations"
    assert r["teams"] == [{"id": 0, "alias": "England", "Index": 5}]
    assert r["rounds"][0]["pools"][0]["games"][0]["month"] == 2


def test_export_cli(tmp_path, capsys):
    src = tmp_path / "gob"
    src.mkdir()
    squad = [500] + [0] * 29
    (src / f"{rosterdb.RDF_MEMBER}.unpacked").write_bytes(
        rosterdb.build_rdf([_player(500)], [_team(5, squad)])
    )
    (src / f"{rosterdb.TEAMS_MEMBER}.unpacked").write_bytes(
        b'<?xml version="1.0"?><hbstool><Project><team Index="5" Active="yes" Type="international" '
        b'CodeId="ID_ENGLAND" FeGroup="international" StringTableId="1050" TeamName="England" '
        b'Abbreviation="ENG" HomeColour="1,2,3,255" AwayColour="4,5,6,255" Logo="eng" />'
        b"</Project></hbstool>"
    )
    (src / f"{rosterdb.KITS_HEADS_MEMBER}.unpacked").write_bytes(
        b'<config><teams><team name="England" location="england" id="5">'
        b'<kit name="Home" location="homekit"/>'
        b"</team></teams></config>"
    )
    (src / f"{rosterdb.STADIUMS_MEMBER}.unpacked").write_bytes(
        b'<hbstool><Project><stadium Index="14" Active="yes" CodeId="STA_ENG_TWICKENHAM" '
        b'StadiumName="Twickenham" '
        b'City="2234" Country="1050"><environment type="day"/></stadium></Project></hbstool>'
    )
    (src / f"{rosterdb.STRINGS_MEMBER}.unpacked").write_bytes(
        loch.build_strtab({1050: "England", 2234: "Twickenham, England"})
    )
    out = tmp_path / "db"
    assert rosterdb.main(["--src", str(src), "--out", str(out)]) == 0
    assert json.loads(capsys.readouterr().out)["players"] == 1
    teams = json.loads((out / "teams.json").read_text())
    assert teams[0]["name"] == "England" and teams[0]["starting_xv"][0] == 500
    assert teams[0]["kits"] == [{"name": "Home", "location": "homekit"}]
    players = json.loads((out / "players.json").read_text())
    assert players[0]["teams"] == [5]
    st = json.loads((out / "stadiums.json").read_text())["stadiums"][0]
    assert st["city"] == "Twickenham, England" and st["country"] == "England"
    for name in ("heads", "competitions", "schema"):
        assert (out / f"{name}.json").is_file()


def test_cli_missing_src(tmp_path):
    assert rosterdb.main(["--src", str(tmp_path / "nope")]) == 2


def test_market_value_bands():
    mv = rosterdb.market_value
    got = [mv(r) for r in (0, 15, 16, 19, 22, 25, 27, 30, 32, 33, 34, 35, 96, 97, 150)]
    assert got == [1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 40, 41, 41]


def test_market_rating_scrum_half():
    p = _player()
    p.position_codes = [8, 0, 0]
    p.abilities = ["Passer"]
    p.attributes = dict.fromkeys(p.attributes, 0)
    p.attributes["passing"] = 91  # > 90 -> key multiplier 2.0
    # (0.33 * 91 + 15 bonus) * K 0.4 * 2.0 = 36.02 -> 36
    assert rosterdb.market_rating(p) == 36
    p.attributes["passing"] = 75  # table index 4 -> 1.3
    assert rosterdb.market_rating(p) == int((0.33 * 75 + 15) * 0.4 * 1.3)
    p.position_codes = [0, 0, 0]
    assert rosterdb.market_rating(p) == 0
