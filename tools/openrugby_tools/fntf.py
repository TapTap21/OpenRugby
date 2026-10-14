"""Parser for Rugby 08 ``FntF`` bitmap fonts (``.ffn``).

Layout (little-endian, observed on all 9 shipped fonts):

    0x00 "FntF"  u32 file_size  u16 =414 (unknown)  u16 glyph_count  u32 =0
    0x10 u32 packed (4 bytes of unknown per-font values)
    0x14 u32 glyph_table_offset (=0x80)   0x18 u32 glyph_table_end
    0x1C u32 other_offset   0x20 u32 =0xFFFFFFFF   0x24 u32 line height-like value
    0x30 u32 ...  0x38/0x3C f32 =1.0   0x40/0x44 f32 1/tex_width, 1/tex_height
    glyph_table: glyph_count * 12 bytes:
        u16 code, u8 width, u8 height, u16 x, u16 y (atlas pixels),
        u8 advance, i8 y_offset, u16 extra (low byte usually 5; meaning unknown)
    atlas: RGBA8 (w*h*4 bytes) occupying the END of the file.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

GLYPH = struct.Struct("<HBBHHBbH")


class FntfError(ValueError):
    pass


def parse_fntf(data: bytes) -> dict:
    if data[:4] != b"FntF":
        raise FntfError("missing FntF magic")
    _size, _u414, count = struct.unpack_from("<IHH", data, 4)
    gt_off, gt_end = struct.unpack_from("<2I", data, 0x14)
    inv_w, inv_h = struct.unpack_from("<2f", data, 0x40)
    if inv_w <= 0 or inv_h <= 0:
        raise FntfError("bad texel size")
    w, h = round(1 / inv_w), round(1 / inv_h)
    if gt_off + GLYPH.size * count > len(data) or w * h * 4 > len(data):
        raise FntfError("truncated")
    glyphs = []
    for i in range(count):
        c, gw, gh, x, y, adv, yoff, extra = GLYPH.unpack_from(data, gt_off + i * GLYPH.size)
        glyphs.append(
            {
                "code": c,
                "char": chr(c),
                "w": gw,
                "h": gh,
                "x": x,
                "y": y,
                "advance": adv,
                "y_offset": yoff,
                "extra": extra,
            }
        )
    return {
        "atlas_width": w,
        "atlas_height": h,
        "glyph_count": count,
        "glyph_table_end": gt_end,
        "header": list(struct.unpack_from("<16I", data, 0x10)),
        "glyphs": glyphs,
    }


def atlas_rgba(data: bytes, meta: dict) -> bytes:
    n = meta["atlas_width"] * meta["atlas_height"] * 4
    return data[len(data) - n :]


def convert(path: Path, out_dir: Path) -> dict:
    from PIL import Image  # optional dependency, only needed for PNG output

    data = path.read_bytes()
    meta = parse_fntf(data)
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = path.name.split(".")[0]
    size = (meta["atlas_width"], meta["atlas_height"])
    Image.frombytes("RGBA", size, atlas_rgba(data, meta)).save(out_dir / f"{stem}.png")
    (out_dir / f"{stem}.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    return meta


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m openrugby_tools.fntf", description="FntF font to PNG + JSON"
    )
    ap.add_argument("input", type=Path)
    ap.add_argument("-o", "--out-dir", type=Path, default=Path("."))
    a = ap.parse_args(argv)
    m = convert(a.input, a.out_dir)
    sys.stdout.write(f"{m['glyph_count']} glyphs, atlas {m['atlas_width']}x{m['atlas_height']}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
