import json
import struct

import pytest

from openrugby_tools import fntf


def make_font(w=4, h=4):
    glyphs = [fntf.GLYPH.pack(65, 2, 3, 1, 0, 3, -1, 5), fntf.GLYPH.pack(66, 2, 2, 2, 2, 3, 0, 5)]
    head = bytearray(0x80)
    head[0:4] = b"FntF"
    struct.pack_into("<IHH", head, 4, 0, 414, len(glyphs))
    struct.pack_into("<2I", head, 0x14, 0x80, 0x80 + 12 * len(glyphs))
    struct.pack_into("<2f", head, 0x40, 1 / w, 1 / h)
    pix = bytes(range(w * h * 4))
    return bytes(head) + b"".join(glyphs) + pix, pix


def test_parse():
    data, pix = make_font()
    m = fntf.parse_fntf(data)
    assert (m["atlas_width"], m["atlas_height"]) == (4, 4)
    assert m["glyphs"][0]["char"] == "A" and m["glyphs"][0]["y_offset"] == -1
    assert fntf.atlas_rgba(data, m) == pix


def test_bad():
    with pytest.raises(fntf.FntfError):
        fntf.parse_fntf(b"nope" * 40)


def test_cli(tmp_path, capsys):
    pytest.importorskip("PIL")
    data, _ = make_font()
    p = tmp_path / "x.ffn.unpacked"
    p.write_bytes(data)
    assert fntf.main([str(p), "-o", str(tmp_path / "o")]) == 0
    assert (tmp_path / "o" / "x.png").exists()
    assert json.loads((tmp_path / "o" / "x.json").read_text())["glyph_count"] == 2
