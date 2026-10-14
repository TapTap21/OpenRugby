"""Tests for the EAGL model reader using synthetic in-memory ELF objects."""

from __future__ import annotations

import json
import struct
from pathlib import Path

import pytest

from openrugby_tools import eagl

RM_SYM = "__RenderMethod:::__GPRenderMethod_test_0"
GPS_SYM = "__EAGL::GeoPrimState:::RUNTIME_ALLOC::UID=7;;SetPrimitiveType=EAGL::PT_TRIANGLESTRIP;"
TAR_SYM = (
    "__EAGL::TAR:::RUNTIME_ALLOC::UID=7;SHAPENAME=bala,1;"
    "PCEXTOBJ_SetClampU=EAGL::PCCM_WRAP;PCEXTOBJ_SetClampV=EAGL::PCCM_CLAMP"
)


def build_elf(
    data: bytes,
    symbols: list[tuple[str, int, bool]],
    relocs: list[tuple[int, int]],
) -> bytes:
    """Build an ELF32 LSB REL object with .data/.shstrtab/.strtab/.symtab/.rel.data.

    ``symbols``: (name, value, defined_in_data); index 1 is always the .data
    section symbol. ``relocs``: (offset in .data, symbol index) as R_MIPS_32.
    """
    shstr = b"\0.data\0.shstrtab\0.strtab\0.symtab\0.rel.data\0"

    def shname(n: str) -> int:
        return shstr.index(n.encode() + b"\0")

    strtab = bytearray(b"\0")
    sym = bytearray(16)  # null symbol
    sym += struct.pack("<IIIBBH", 0, 0, 0, 3, 0, 1)  # .data section symbol
    for name, value, defined in symbols:
        off = len(strtab)
        strtab += name.encode() + b"\0"
        sym += struct.pack("<IIIBBH", off, value, 4 if defined else 0, 0x11, 0, 1 if defined else 0)
    rel = b"".join(struct.pack("<II", o, (s << 8) | eagl.R_MIPS_32) for o, s in relocs)

    body = bytearray(b"\0" * 0x40)
    layout = {}
    for name, blob in (
        (".data", data),
        (".shstrtab", shstr),
        (".strtab", bytes(strtab)),
        (".symtab", bytes(sym)),
        (".rel.data", rel),
    ):
        while len(body) % 4:
            body.append(0)
        layout[name] = (len(body), len(blob))
        body += blob
    while len(body) % 4:
        body.append(0)
    shoff = len(body)
    sh = bytearray(40)
    specs = [
        (".data", 1, 0, 0),
        (".shstrtab", 3, 0, 0),
        (".strtab", 3, 0, 0),
        (".symtab", 2, 3, 2),
        (".rel.data", 9, 4, 1),
    ]
    for name, typ, link, info in specs:
        off, size = layout[name]
        entsize = {2: 16, 9: 8}.get(typ, 0)
        sh += struct.pack("<10I", shname(name), typ, 0, 0, off, size, link, info, 4, entsize)
    ident = b"\x7fELF\x01\x01\x01" + b"\0" * 9
    hdr = ident + struct.pack(
        "<HHIIIIIHHHHHH", 1, 8, 1, 0, 0, shoff, 0x20924000, 52, 0, 0, 40, 6, 2
    )
    body[: len(hdr)] = hdr
    return bytes(body) + bytes(sh)


def w(*vals: int) -> bytes:
    return struct.pack(f"<{len(vals)}I", *vals)


def make_quad_object() -> bytes:
    """One RenderMethod drawing a 4-vertex strip (FVF 0x142, stride 24)."""
    data = bytearray()
    geoinfo = len(data)
    data += w(4, 4, 2)  # index count, vertex count, primitive count
    vb = len(data)
    for x, y, u, v in ((0, 0, 0, 1), (1, 0, 1, 1), (0, 1, 0, 0), (1, 1, 1, 0)):
        data += struct.pack("<3fI2f", x, y, 0.0, 0xFF102030, u, v)
    ib = len(data)
    data += struct.pack("<6H", 0, 1, 2, 3, 0x2220, 0)  # count 6 in command, 4 real
    stream = len(data)
    data += w((0x30 << 16) | 3, 0, 0xFFFFFFFF)
    vb_cmd = len(data)
    data += w((0x4B << 16) | 12, 0, 24, 0x142, ~0 & 0xFFFFFFFF, 0xFFFFFFFF, vb, 4)
    data += w(0xFFFFFFFF, 0, 0xFFFFFFFF, 0xFFFFFFFF)
    ib_cmd = len(data)
    data += w((0x07 << 16) | 6, 2, 0xFFFFFFFF, 0xFFFFFFFF, ib, 6)
    data += w(0, 0)  # end of stream
    rm = len(data)
    data += w(stream, 0, 0, 0, 0, 0, 0, 0xFFFFFFFF, 0, stream, 0xFFFFFFFF, 0, 0, eagl.RM_MAGIC)
    binding = len(data)
    data += w(rm, 1, geoinfo, 1, 0, 1, 0, 4, vb, 4, ib)
    syms = [(RM_SYM, rm, True), (GPS_SYM, 0, False), (TAR_SYM, 0, False)]
    relocs = [
        (vb_cmd + 24, 1),
        (ib_cmd + 16, 1),
        (rm, 1),
        (rm + 0x24, 1),
        (binding, 1),
        (binding + 8, 1),
        (binding + 16, 3),  # GeoPrimState (symbol index 3)
        (binding + 24, 4),  # TAR (symbol index 4)
        (binding + 32, 1),
        (binding + 40, 1),
    ]
    return build_elf(bytes(data), syms, relocs)


def test_relocations_internal_and_external() -> None:
    data = w(0x10, 0x4, 0xAA, 0)
    raw = build_elf(data, [("ext_sym", 0, False), ("__X:::y", 8, True)], [(0, 1), (4, 2), (12, 3)])
    obj = eagl.ElfObject(raw)
    assert obj.ptr(0) == eagl.Pointer(None, 0x10)
    assert obj.ptr(4) == eagl.Pointer("ext_sym", 4)
    assert obj.ptr(12) == eagl.Pointer(None, 8)  # defined symbol value + addend 0
    assert obj.ptr(8) is None
    out = obj.relocated_data({"ext_sym": 0x1000}, base=0x200)
    assert struct.unpack("<4I", out) == (0x210, 0x1004, 0xAA, 0x208)


def test_rejects_non_elf_and_bad_reloc_type() -> None:
    with pytest.raises(eagl.EaglError):
        eagl.ElfObject(b"BIGF" + b"\0" * 60)
    raw = bytearray(build_elf(w(0), [], [(0, 1)]))
    rel_type_at = raw.rindex(struct.pack("<II", 0, (1 << 8) | 2)) + 4
    raw[rel_type_at] = 5
    with pytest.raises(eagl.EaglError):
        eagl.ElfObject(bytes(raw))


@pytest.mark.parametrize(
    ("fvf", "stride"),
    [(0x256, 48), (0x142, 24), (0x42, 16), (0x156, 40), (0x152, 36), (0x52, 28), (0x46, 20)],
)
def test_fvf_strides_match_observed(fvf: int, stride: int) -> None:
    assert eagl.fvf_layout(fvf).stride == stride


def test_render_method_geometry_parse() -> None:
    asset = eagl.decode(eagl.ElfObject(make_quad_object()))
    assert not asset.errors
    (geo,) = asset.geometry.values()
    assert geo.primitive == "TRIANGLESTRIP"
    assert (geo.vertex_count, geo.index_count) == (4, 4)  # padded command count trimmed
    assert [t.shape for t in geo.textures] == ["bala"]
    assert geo.textures[0].attributes["PCEXTOBJ_SetClampV"] == "EAGL::PCCM_CLAMP"
    verts = geo.read_vertices(asset.obj)
    assert verts["position"][3] == (1.0, 1.0, 0.0)
    assert verts["uv0"][0] == (0.0, 1.0)
    assert verts["color"][0] == pytest.approx((0x10 / 255, 0x20 / 255, 0x30 / 255, 1.0))
    assert geo.triangles(asset.obj) == [(0, 1, 2), (2, 1, 3)]


def test_compound_weights_carry_bone_in_mantissa() -> None:
    def packed(weight: float, bone: int) -> int:
        bits = struct.unpack("<I", struct.pack("<f", weight))[0]
        return (bits & 0xFFFFFF00) | bone

    data = w(packed(0.55, 21), packed(0.45, 20), 0, 0, packed(1.0, 5), 0, 0, 0)
    obj = eagl.ElfObject(build_elf(data, [], []))
    comps = eagl._decode_compounds(obj, 0, 2)
    assert comps is not None
    assert comps[0].bones == (21, 20)
    assert comps[0].weights == pytest.approx((0.55, 0.45), abs=1e-4)
    assert comps[1].bones == (5,) and comps[1].weights == (1.0,)


def test_gltf_export_roundtrip(tmp_path: Path) -> None:
    asset = eagl.decode(eagl.ElfObject(make_quad_object()))
    out = tmp_path / "quad.gltf"
    summary = eagl.export_gltf(asset, out)
    assert summary["triangles"] == 2
    doc = json.loads(out.read_text())
    prim = doc["meshes"][0]["primitives"][0]
    assert {"POSITION", "TEXCOORD_0", "COLOR_0"} <= set(prim["attributes"])
    blob = (tmp_path / "quad.bin").read_bytes()
    assert len(blob) == doc["buffers"][0]["byteLength"]
    acc = doc["accessors"][prim["indices"]]
    view = doc["bufferViews"][acc["bufferView"]]
    idx = struct.unpack_from(f"<{acc['count']}I", blob, view["byteOffset"])
    assert idx == (0, 2, 1, 2, 3, 1)  # source winding flipped to counter-clockwise


def test_parse_tar_and_normalise() -> None:
    tar = eagl.parse_tar(TAR_SYM)
    assert tar is not None and (tar.shape, tar.group) == ("bala", 1)
    assert eagl.parse_tar(GPS_SYM) is None
    assert eagl.normalise_symbol("__geoprimdatabuffer_2_968_model") == (
        "__geoprimdatabuffer_#_#_<model>"
    )
    assert eagl.normalise_symbol("__Model:::PlayerHigh.variation3") == (
        "__Model:::<model>.variation#"
    )
