import json

import pytest

from openrugby_tools import loch


def test_roundtrip():
    blob = loch.build_loch(["Yes", "No", "Do you?"])
    r = loch.parse_loch(blob)
    assert r["strings"] == ["Yes", "No", "Do you?"]
    assert r["ids"] == {"1": "Yes", "2": "No", "3": "Do you?"}


def test_unicode_and_id_mapping():
    blob = loch.build_loch(["Écraser"], ids=[(7, 0)])
    assert loch.parse_loch(blob)["ids"] == {"7": "Écraser"}


def test_bad_magic():
    with pytest.raises(loch.LochError):
        loch.parse_loch(b"XXXX" + bytes(40))


def test_cli(tmp_path, capsys):
    p = tmp_path / "a.loc"
    p.write_bytes(loch.build_loch(["A"]))
    assert loch.main([str(p)]) == 0
    assert json.loads(capsys.readouterr().out)["strings"] == ["A"]


def test_strtab_roundtrip():
    blob = loch.build_strtab({0: "EA", 5: "Caf\u00e9"})
    r = loch.parse_any(blob)
    assert r["ids"] == {"0": "EA", "5": "Caf\u00e9"} and r["max_id"] == 5


def test_strtab_bad_size():
    with pytest.raises(loch.LochError):
        loch.parse_strtab(bytes(12) + b"x")
