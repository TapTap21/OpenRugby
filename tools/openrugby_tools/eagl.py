"""Reader for EA EAGL model objects (Rugby 08 PC) with a glTF 2.0 exporter.

Container (observed): every model is an ELF32 little-endian relocatable object
(``e_machine`` MIPS, flags ``mips3``/``eabi64``) holding only ``.data``,
``.rel.data``, ``.symtab``, ``.strtab`` and ``.shstrtab``. All pointers inside
``.data`` are ``R_MIPS_32`` relocations: the stored word is the addend and the
symbol is either the ``.data`` section symbol (internal pointer, target offset =
addend) or an undefined runtime symbol (render-method library objects, engine
globals, texture handles). Applying a relocation is ``S + A`` with ``.data`` at
base 0, so the stored word *is* the internal offset.

Walk (see ``docs/re/04-models-eagl.md`` for offsets and evidence)::

    __Model:::<name>  -> part table (+0xCC) -> binding blocks -> RenderMethod
    RenderMethod +0x00 -> command stream; bindings carry (count, pointer) pairs
    command stream    -> vertex-buffer command (stride, D3D FVF, ptr, count)
                      -> index-buffer command (ptr, count)
    bindings          -> geometry info, textures (EAGL::TAR symbols),
                         primitive type (EAGL::GeoPrimState symbol),
                         skin "compound" table, vertex/index buffers
    __Skeleton:::<n>  -> bone records (scale, parent, rotation, translation,
                         inverse bind matrix)

CLI: ``python -m openrugby_tools.eagl {census,dump,gltf,preview}``.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
import sys
import zlib
from collections import Counter
from collections.abc import Iterator, Sequence
from dataclasses import dataclass, field
from pathlib import Path

ELF_MAGIC = b"\x7fELF"
SHT_SYMTAB = 2
SHT_REL = 9
STT_SECTION = 3
R_MIPS_32 = 2

RM_MAGIC = 0xABCDEFEA  # word at RenderMethod +0x34
SKELETON_MAGIC = 0x01FEC0DA

# D3D flexible-vertex-format bits (Direct3D 8/9 public ABI).
FVF_POSITION_MASK = 0x00E
FVF_XYZ = 0x002
FVF_XYZRHW = 0x004
FVF_NORMAL = 0x010
FVF_PSIZE = 0x020
FVF_DIFFUSE = 0x040
FVF_SPECULAR = 0x080
FVF_LASTBETA_UBYTE4 = 0x1000
FVF_LASTBETA_D3DCOLOR = 0x8000

REPO = Path(__file__).resolve().parents[2]
DEFAULT_EXTRACTED = REPO / "extracted"
DEFAULT_MODELS = DEFAULT_EXTRACTED / "models"
DEFAULT_TEXTURES = DEFAULT_EXTRACTED / "textures"
DEFAULT_CENSUS = REPO / ".omc" / "research" / "models" / "census.json"


class EaglError(ValueError):
    """Raised for malformed or unsupported EAGL objects."""


# ---------------------------------------------------------------------------
# ELF layer
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Section:
    index: int
    name: str
    type: int
    offset: int
    size: int
    link: int
    info: int


@dataclass(frozen=True)
class Symbol:
    index: int
    name: str
    value: int
    size: int
    bind: int
    type: int
    shndx: int

    @property
    def defined(self) -> bool:
        return self.shndx != 0


@dataclass(frozen=True)
class Reloc:
    offset: int
    sym: int
    type: int


@dataclass(frozen=True)
class Pointer:
    """A resolved relocation: ``symbol`` is None for internal ``.data`` pointers."""

    symbol: str | None
    target: int

    @property
    def internal(self) -> bool:
        return self.symbol is None


class ElfObject:
    """A data-only ELF32 LSB relocatable object (one EAGL asset)."""

    def __init__(self, raw: bytes) -> None:
        if len(raw) < 52 or raw[:4] != ELF_MAGIC:
            raise EaglError("not an ELF file")
        if raw[4] != 1 or raw[5] != 1:
            raise EaglError("only ELF32 little-endian objects are supported")
        self.raw = raw
        (shoff,) = struct.unpack_from("<I", raw, 0x20)
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", raw, 0x2E)
        if shentsize != 40 or shoff + shnum * 40 > len(raw) or shstrndx >= shnum:
            raise EaglError("bad section header table")
        hdrs = [struct.unpack_from("<10I", raw, shoff + i * 40) for i in range(shnum)]
        names_off = hdrs[shstrndx][4]
        self.sections = [
            Section(i, self._cstr(names_off + h[0]), h[1], h[4], h[5], h[6], h[7])
            for i, h in enumerate(hdrs)
        ]
        for s in self.sections:
            if s.type != 8 and s.offset + s.size > len(raw):
                raise EaglError(f"section {s.name!r} out of bounds")
        self.symbols: list[Symbol] = []
        self.relocs: dict[int, list[Reloc]] = {}
        for s in self.sections:
            if s.type == SHT_SYMTAB:
                strtab = self.sections[s.link].offset
                for i in range(s.size // 16):
                    nm, val, size, info, _other, ndx = struct.unpack_from(
                        "<IIIBBH", raw, s.offset + i * 16
                    )
                    self.symbols.append(
                        Symbol(i, self._cstr(strtab + nm), val, size, info >> 4, info & 15, ndx)
                    )
            elif s.type == SHT_REL:
                body = raw[s.offset : s.offset + s.size]
                self.relocs[s.info] = [
                    Reloc(off, info >> 8, info & 0xFF)
                    for off, info in struct.iter_unpack("<II", body)
                ]
        data_sec = self.section(".data")
        self.data_index = data_sec.index
        self.data = raw[data_sec.offset : data_sec.offset + data_sec.size]
        self._ptrs: dict[int, Pointer] = {}
        for r in self.relocs.get(self.data_index, []):
            if r.type != R_MIPS_32:
                raise EaglError(f"unsupported relocation type {r.type} at {r.offset:#x}")
            if r.offset + 4 > len(self.data) or r.sym >= len(self.symbols):
                raise EaglError(f"relocation at {r.offset:#x} out of range")
            sym = self.symbols[r.sym]
            addend = struct.unpack_from("<I", self.data, r.offset)[0]
            internal = sym.type == STT_SECTION and sym.shndx == self.data_index
            if internal or (sym.defined and sym.shndx == self.data_index):
                target = (sym.value if not internal else 0) + addend
                self._ptrs[r.offset] = Pointer(None, target)
            else:
                self._ptrs[r.offset] = Pointer(sym.name, addend)

    @classmethod
    def load(cls, path: str | Path) -> ElfObject:
        return cls(Path(path).read_bytes())

    def _cstr(self, off: int) -> str:
        end = self.raw.index(b"\0", off)
        return self.raw[off:end].decode("latin-1")

    def section(self, name: str) -> Section:
        for s in self.sections:
            if s.name == name:
                return s
        raise EaglError(f"missing section {name}")

    # -- typed access to .data ---------------------------------------------
    def u32(self, off: int) -> int:
        return struct.unpack_from("<I", self.data, off)[0]

    def i32(self, off: int) -> int:
        return struct.unpack_from("<i", self.data, off)[0]

    def f32(self, off: int, n: int = 1) -> tuple[float, ...]:
        return struct.unpack_from(f"<{n}f", self.data, off)

    def cstr(self, off: int) -> str:
        end = self.data.index(b"\0", off)
        return self.data[off:end].decode("latin-1")

    def ptr(self, off: int) -> Pointer | None:
        """The relocation at ``off`` in ``.data``, if any."""
        return self._ptrs.get(off)

    def iptr(self, off: int) -> int | None:
        """Target of an internal ``.data`` pointer stored at ``off``."""
        p = self._ptrs.get(off)
        return p.target if p is not None and p.internal else None

    def defined_symbols(self, prefix: str = "") -> list[Symbol]:
        return [
            s
            for s in self.symbols
            if s.shndx == self.data_index and s.type != STT_SECTION and s.name.startswith(prefix)
        ]

    def relocated_data(self, externals: dict[str, int] | None = None, base: int = 0) -> bytes:
        """Return ``.data`` with every ``R_MIPS_32`` applied (``S + A``).

        ``.data`` is placed at ``base``; undefined symbols resolve through
        ``externals`` (missing ones resolve to 0, i.e. the bare addend).
        """
        out = bytearray(self.data)
        ext = externals or {}
        for off, p in self._ptrs.items():
            value = base + p.target if p.internal else ext.get(p.symbol or "", 0) + p.target
            struct.pack_into("<I", out, off, value & 0xFFFFFFFF)
        return bytes(out)


# ---------------------------------------------------------------------------
# Command streams ("geoprim data buffers")
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Command:
    """One command: header word ``(opcode << 16) | word_count``, then arguments.

    Opcode numbers are microcode-specific (the same logical command has
    different numbers in different render methods); recognise commands by shape.
    """

    offset: int
    opcode: int
    args: tuple[int, ...]
    pointers: dict[int, Pointer]


def iter_commands(obj: ElfObject, start: int, limit: int = 100000) -> Iterator[Command | None]:
    """Yield commands from ``start``; ``None`` marks a zero block separator.

    The stream ends at two consecutive zero words, at a relocated word in header
    position, or at a header that is not plausible.
    """
    off = start
    end = len(obj.data)
    zero_run = 0
    for _ in range(limit):
        if off + 4 > end or obj.ptr(off) is not None:
            return
        word = obj.u32(off)
        if word == 0:
            zero_run += 1
            if zero_run >= 2:
                return
            yield None
            off += 4
            continue
        zero_run = 0
        op, n = word >> 16, word & 0xFFFF
        if op > 0xFF or n == 0 or off + 4 * n > end:
            return
        args = tuple(obj.u32(off + 4 * i) for i in range(1, n))
        ptrs = {i - 1: p for i in range(1, n) if (p := obj.ptr(off + 4 * i)) is not None}
        yield Command(off, op, args, ptrs)
        off += 4 * n


@dataclass(frozen=True)
class VertexBufferCmd:
    stream: int
    stride: int
    fvf: int
    data: int
    count: int
    buffer_id: int


@dataclass(frozen=True)
class IndexBufferCmd:
    index_size: int
    data: int
    count: int


def match_vertex_buffer(cmd: Command) -> VertexBufferCmd | None:
    """Shape: 11 args ``stream, stride, fvf, -1, -1, *data, count, -1, id, -1, -1``."""
    a = cmd.args
    if len(a) != 11 or 5 not in cmd.pointers or not cmd.pointers[5].internal:
        return None
    if a[3] != 0xFFFFFFFF or a[4] != 0xFFFFFFFF:
        return None
    return VertexBufferCmd(a[0], a[1], a[2], cmd.pointers[5].target, a[6], a[8])


def match_index_buffer(cmd: Command) -> IndexBufferCmd | None:
    """Shape: 5 args ``index_size(=2), -1, -1, *data, count``."""
    a = cmd.args
    if len(a) != 5 or 3 not in cmd.pointers or not cmd.pointers[3].internal:
        return None
    if a[1] != 0xFFFFFFFF or a[2] != 0xFFFFFFFF or a[0] not in (2, 4):
        return None
    return IndexBufferCmd(a[0], cmd.pointers[3].target, a[4])


# ---------------------------------------------------------------------------
# Vertex formats
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class VertexLayout:
    fvf: int
    stride: int
    position: int  # byte offset
    position_size: int  # 3 or 4 floats
    betas: int  # number of 32-bit blend values after xyz
    beta_offset: int
    normal: int | None
    psize: int | None
    diffuse: int | None
    specular: int | None
    texcoords: tuple[tuple[int, int], ...]  # (offset, components)


def fvf_layout(fvf: int) -> VertexLayout:
    """Decode a Direct3D FVF code into byte offsets."""
    pos_kind = fvf & FVF_POSITION_MASK
    off = 0
    betas = 0
    if pos_kind == FVF_XYZ:
        psize = 3
    elif pos_kind == FVF_XYZRHW:
        psize = 4
    elif pos_kind in (0x6, 0x8, 0xA, 0xC, 0xE):
        psize, betas = 3, (pos_kind - 0x4) // 2
    else:
        raise EaglError(f"unsupported FVF position type {fvf:#x}")
    position = off
    off += 4 * psize
    beta_offset = off
    off += 4 * betas
    normal = psize_off = diffuse = specular = None
    if fvf & FVF_NORMAL:
        normal, off = off, off + 12
    if fvf & FVF_PSIZE:
        psize_off, off = off, off + 4
    if fvf & FVF_DIFFUSE:
        diffuse, off = off, off + 4
    if fvf & FVF_SPECULAR:
        specular, off = off, off + 4
    tex: list[tuple[int, int]] = []
    for i in range((fvf >> 8) & 0xF):
        code = (fvf >> (16 + 2 * i)) & 3
        comps = {0: 2, 1: 3, 2: 4, 3: 1}[code]
        tex.append((off, comps))
        off += 4 * comps
    return VertexLayout(
        fvf=fvf,
        stride=off,
        position=position,
        position_size=psize,
        betas=betas,
        beta_offset=beta_offset,
        normal=normal,
        psize=psize_off,
        diffuse=diffuse,
        specular=specular,
        texcoords=tuple(tex),
    )


# ---------------------------------------------------------------------------
# Render methods, geometry and textures
# ---------------------------------------------------------------------------

_TAR_RE = re.compile(r"SHAPENAME=([^,;]*),(\d+)")
_PT_RE = re.compile(r"SetPrimitiveType=EAGL::PT_(\w+)")


@dataclass(frozen=True)
class TextureRef:
    shape: str
    group: int
    attributes: dict[str, str]


def parse_tar(symbol: str) -> TextureRef | None:
    """Parse ``__EAGL::TAR:::RUNTIME_ALLOC::UID=n;SHAPENAME=name,k;Key=Value...``."""
    if "::TAR:::" not in symbol:
        return None
    m = _TAR_RE.search(symbol)
    if not m:
        return None
    attrs: dict[str, str] = {}
    for part in symbol.split(":::", 1)[1].split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            attrs[k.split("::")[-1]] = v
    return TextureRef(m.group(1), int(m.group(2)), attrs)


@dataclass(frozen=True)
class Binding:
    count: int
    pointer: Pointer


@dataclass
class Compound:
    """A skinning compound: up to four (bone, weight) pairs."""

    bones: tuple[int, ...]
    weights: tuple[float, ...]


@dataclass
class Geometry:
    """One drawable chunk (one RenderMethod)."""

    name: str
    layout: VertexLayout
    vertex_offset: int
    vertex_count: int
    index_offset: int
    index_count: int
    primitive: str  # TRIANGLESTRIP, LINELIST, ...
    textures: list[TextureRef]
    compounds: list[Compound] | None
    microcode: str | None

    def read_vertices(self, obj: ElfObject) -> dict[str, list[tuple[float, ...]]]:
        lay = self.layout
        out: dict[str, list[tuple[float, ...]]] = {"position": []}
        if lay.normal is not None:
            out["normal"] = []
        if lay.diffuse is not None:
            out["color"] = []
        if lay.betas:
            out["beta"] = []
        for t in range(len(lay.texcoords)):
            out[f"uv{t}"] = []
        d = obj.data
        for i in range(self.vertex_count):
            b = self.vertex_offset + i * lay.stride
            out["position"].append(struct.unpack_from("<3f", d, b + lay.position))
            if lay.normal is not None:
                out["normal"].append(struct.unpack_from("<3f", d, b + lay.normal))
            if lay.diffuse is not None:
                bb, g, r, a = d[b + lay.diffuse : b + lay.diffuse + 4]
                out["color"].append((r / 255, g / 255, bb / 255, a / 255))
            if lay.betas:
                out["beta"].append(struct.unpack_from(f"<{lay.betas}I", d, b + lay.beta_offset))
            for t, (toff, comps) in enumerate(lay.texcoords):
                out[f"uv{t}"].append(struct.unpack_from(f"<{comps}f", d, b + toff))
        return out

    def read_indices(self, obj: ElfObject) -> list[int]:
        return list(struct.unpack_from(f"<{self.index_count}H", obj.data, self.index_offset))

    def triangles(self, obj: ElfObject) -> list[tuple[int, int, int]]:
        """Triangles in source winding (front faces clockwise); degenerates removed.

        Strip triangle ``i`` is ``(i, i+1, i+2)`` for even ``i`` and
        ``(i+1, i, i+2)`` for odd ``i``.
        """
        idx = self.read_indices(obj)
        tris: list[tuple[int, int, int]] = []
        if self.primitive == "TRIANGLESTRIP":
            for i in range(len(idx) - 2):
                a, b, c = idx[i], idx[i + 1], idx[i + 2]
                if a == b or b == c or a == c:
                    continue
                tris.append((a, b, c) if i % 2 == 0 else (b, a, c))
        elif self.primitive == "TRIANGLELIST":
            for i in range(0, len(idx) - 2, 3):
                tris.append((idx[i], idx[i + 1], idx[i + 2]))
        return [t for t in tris if max(t) < self.vertex_count]

    def lines(self, obj: ElfObject) -> list[tuple[int, int]]:
        idx = self.read_indices(obj)
        if self.primitive == "LINELIST":
            return [(idx[i], idx[i + 1]) for i in range(0, len(idx) - 1, 2)]
        if self.primitive == "LINESTRIP":
            return [(idx[i], idx[i + 1]) for i in range(len(idx) - 1)]
        return []


@dataclass
class RenderMethod:
    offset: int
    name: str
    stream: int | None
    microcode: str | None
    parent: str | None
    shader_name: str | None
    bindings: list[Binding]
    vertex_buffer: VertexBufferCmd | None
    index_buffer: IndexBufferCmd | None
    commands: int


def read_bindings(obj: ElfObject, block: int) -> list[Binding]:
    """Bindings after the self pointer: ``(u32 count, pointer)`` pairs.

    The pair count is defined by the parent render method; the list is read
    until the pointer slot is not relocated.
    """
    out: list[Binding] = []
    off = block + 4
    while off + 8 <= len(obj.data):
        p = obj.ptr(off + 4)
        if p is None or obj.ptr(off) is not None:
            break
        out.append(Binding(obj.u32(off), p))
        off += 8
    return out


def read_render_method(obj: ElfObject, off: int, name: str = "") -> RenderMethod:
    """Parse the RenderMethod struct at ``off`` (see spec for the field table)."""
    stream = obj.iptr(off)
    mc = obj.ptr(off + 0x08)
    parent = obj.ptr(off + 0x10)
    sname_ptr = obj.iptr(off + 0x2C)
    shader = obj.cstr(sname_ptr) if sname_ptr is not None else None
    bindings: list[Binding] = []
    if off + 0x3C <= len(obj.data) and obj.u32(off + 0x34) == RM_MAGIC:
        if obj.iptr(off + 0x38) == off:
            bindings = read_bindings(obj, off + 0x38)
    vb = ib = None
    ncmd = 0
    if stream is not None:
        for cmd in iter_commands(obj, stream):
            if cmd is None:
                if vb is not None and ib is not None:
                    break  # first pass block is enough
                continue
            ncmd += 1
            vb = vb or match_vertex_buffer(cmd)
            ib = ib or match_index_buffer(cmd)
    return RenderMethod(
        off,
        name,
        stream,
        mc.symbol if mc else None,
        parent.symbol if parent else None,
        shader,
        bindings,
        vb,
        ib,
        ncmd,
    )


def _decode_compounds(obj: ElfObject, off: int, count: int) -> list[Compound] | None:
    """Compound entries are float4 weights; the low 8 mantissa bits carry the bone."""
    if off + 16 * count > len(obj.data):
        return None
    out: list[Compound] = []
    for i in range(count):
        words = struct.unpack_from("<4I", obj.data, off + 16 * i)
        bones: list[int] = []
        weights: list[float] = []
        for w in words:
            weight = struct.unpack("<f", struct.pack("<I", w & 0xFFFFFF00))[0]
            if w == 0 or weight == 0.0:
                continue
            if not (0.0 < weight <= 1.001):
                return None
            bones.append(w & 0xFF)
            weights.append(weight)
        total = sum(weights)
        if not bones or abs(total - 1.0) > 0.02:
            return None
        out.append(Compound(tuple(bones), tuple(x / total for x in weights)))
    return out


def geometry_from_rm(obj: ElfObject, rm: RenderMethod) -> Geometry | None:
    vb, ib = rm.vertex_buffer, rm.index_buffer
    if vb is None or ib is None:
        return None
    layout = fvf_layout(vb.fvf)
    if layout.stride != vb.stride:
        raise EaglError(f"{rm.name}: FVF {vb.fvf:#x} stride {layout.stride} != {vb.stride}")
    index_count = ib.count
    textures: list[TextureRef] = []
    primitive = "TRIANGLESTRIP"
    for b in rm.bindings:
        p = b.pointer
        if p.internal and p.target == ib.data:
            index_count = min(index_count, b.count)  # true count; the command is padded
        elif p.symbol:
            tar = parse_tar(p.symbol)
            if tar:
                textures.append(tar)
            m = _PT_RE.search(p.symbol)
            if "GeoPrimState" in p.symbol and m:
                primitive = m.group(1)
    if vb.data + vb.count * vb.stride > len(obj.data):
        raise EaglError(f"{rm.name}: vertex buffer out of range")
    geo = Geometry(
        rm.name,
        layout,
        vb.data,
        vb.count,
        ib.data,
        index_count,
        primitive,
        textures,
        None,
        rm.microcode,
    )
    if layout.betas:
        betas = [b[0] for b in geo.read_vertices(obj)["beta"]]
        need = max(betas) + 1 if betas else 0
        anim_pos = len(rm.bindings)
        for i, b in enumerate(rm.bindings):
            if b.pointer.symbol and "AnimationBuffer" in b.pointer.symbol:
                anim_pos = i
                break
        cands = [
            (abs(i - (anim_pos - 1)), b)
            for i, b in enumerate(rm.bindings)
            if b.pointer.internal and b.count >= need and b.pointer.target not in (vb.data, ib.data)
        ]
        for _, b in sorted(cands, key=lambda c: c[0]):
            comp = _decode_compounds(obj, b.pointer.target, b.count)
            if comp is not None:
                geo.compounds = comp
                break
    return geo


# ---------------------------------------------------------------------------
# Models and skeletons
# ---------------------------------------------------------------------------


@dataclass
class Part:
    name: str
    render_methods: list[int]  # RenderMethod offsets


@dataclass
class Model:
    symbol: str
    offset: int
    name: str
    transform: tuple[float, ...]
    bbox_min: tuple[float, ...]
    bbox_max: tuple[float, ...]
    sphere: tuple[float, ...]
    parts: list[Part]
    variation: int
    texture_table: list[TextureRef]


def _ptr_table(obj: ElfObject, off: int, count: int) -> list[int]:
    out = []
    for i in range(count):
        t = obj.iptr(off + 4 * i)
        if t is None:
            raise EaglError(f"expected pointer at {off + 4 * i:#x}")
        out.append(t)
    return out


def read_texture_table(obj: ElfObject, off: int | None) -> list[TextureRef]:
    """Entries ``{char *name, u32 1, TAR *handle, u32 flags}`` until a non-pointer."""
    out: list[TextureRef] = []
    if off is None:
        return out
    while off + 16 <= len(obj.data):
        p = obj.ptr(off + 8)
        if obj.iptr(off) is None or p is None or p.symbol is None:
            break
        tar = parse_tar(p.symbol)
        if tar:
            out.append(tar)
        off += 16
    return out


def read_model(obj: ElfObject, sym: Symbol) -> Model:
    m = sym.value
    if m + 0xD0 > len(obj.data):
        raise EaglError(f"{sym.name}: truncated Model")
    names_n = obj.u32(m + 0x9C)
    names_ptr = obj.iptr(m + 0xA0)
    names = (
        [obj.cstr(p) for p in _ptr_table(obj, names_ptr, names_n)] if names_ptr is not None else []
    )
    name_ptr = obj.iptr(m + 0xB4)
    parts_ptr = obj.iptr(m + 0xCC)
    parts: list[Part] = []
    if parts_ptr is not None:
        cur = parts_ptr + 4  # leading u32 (observed 0)
        for pname in names:
            n = obj.u32(cur)
            blocks = _ptr_table(obj, cur + 4, n)
            rms = []
            for blk in blocks:
                rm = obj.iptr(blk)
                if rm is None:
                    raise EaglError(f"{sym.name}: binding block {blk:#x} without RenderMethod")
                rms.append(rm)
            parts.append(Part(pname, rms))
            cur += 4 + 4 * n
    return Model(
        sym.name,
        m,
        obj.cstr(name_ptr) if name_ptr is not None else sym.name.split(":::")[-1],
        obj.f32(m + 0x0C, 16),
        obj.f32(m + 0x6C, 3),
        obj.f32(m + 0x7C, 3),
        obj.f32(m + 0x8C, 4),
        parts,
        obj.u32(m + 0xC0),
        read_texture_table(obj, obj.iptr(m + 0xBC)),
    )


@dataclass
class Bone:
    index: int
    name: str
    parent: int
    scale: tuple[float, ...]
    rotation: tuple[float, ...]  # quaternion x, y, z, w (local)
    translation: tuple[float, ...]  # local
    inverse_bind: tuple[float, ...]  # 4x4, row-vector (D3D) order


@dataclass
class Skeleton:
    symbol: str
    bones: list[Bone]


BONE_RECORD = 112  # vec3 scale, i32 parent, quat, vec4 translation, mat4


def read_skeleton(obj: ElfObject, sym: Symbol) -> Skeleton:
    s = sym.value
    if obj.u32(s) != SKELETON_MAGIC:
        raise EaglError(f"{sym.name}: bad skeleton magic {obj.u32(s):#x}")
    count = obj.u32(s + 8)
    prefix = sym.name.split(":::", 1)[1] + "."
    names: dict[int, str] = {}
    for b in obj.defined_symbols("__Bone:::"):
        bname = b.name.split(":::", 1)[1]
        if bname.startswith(prefix):
            names[b.value] = bname[len(prefix) :]
    # Bone name symbols point at 16-byte slots of a table ending at the skeleton.
    base = s - 16 * count
    bones = []
    for i in range(count):
        r = s + 0x10 + i * BONE_RECORD
        if r + BONE_RECORD > len(obj.data):
            raise EaglError(f"{sym.name}: truncated bone table")
        bones.append(
            Bone(
                i,
                names.get(base + 16 * i, f"bone{i}"),
                obj.i32(r + 12),
                obj.f32(r, 3),
                obj.f32(r + 16, 4),
                obj.f32(r + 32, 3),
                obj.f32(r + 48, 16),
            )
        )
    return Skeleton(sym.name, bones)


@dataclass
class Asset:
    """Everything decoded from one object file."""

    obj: ElfObject
    models: list[Model] = field(default_factory=list)
    render_methods: dict[int, RenderMethod] = field(default_factory=dict)
    geometry: dict[int, Geometry] = field(default_factory=dict)
    skeletons: list[Skeleton] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def load_asset(path: str | Path) -> Asset:
    obj = ElfObject.load(path)
    return decode(obj)


def decode(obj: ElfObject) -> Asset:
    asset = Asset(obj)
    for s in obj.defined_symbols("__RenderMethod:::"):
        rm = read_render_method(obj, s.value, s.name.split(":::", 1)[1])
        asset.render_methods[s.value] = rm
        try:
            geo = geometry_from_rm(obj, rm)
        except (EaglError, struct.error) as exc:
            asset.errors.append(f"{s.name}: {exc}")
            continue
        if geo is not None:
            asset.geometry[s.value] = geo
    for s in obj.defined_symbols("__Model:::"):
        try:
            asset.models.append(read_model(obj, s))
        except (EaglError, struct.error, ValueError) as exc:
            asset.errors.append(f"{s.name}: {exc}")
    for s in obj.defined_symbols("__Skeleton:::"):
        try:
            asset.skeletons.append(read_skeleton(obj, s))
        except (EaglError, struct.error) as exc:
            asset.errors.append(f"{s.name}: {exc}")
    return asset


# ---------------------------------------------------------------------------
# glTF export
# ---------------------------------------------------------------------------


class _GltfBuilder:
    def __init__(self) -> None:
        self.bin = bytearray()
        self.doc: dict = {
            "asset": {"version": "2.0", "generator": "openrugby_tools.eagl"},
            "buffers": [],
            "bufferViews": [],
            "accessors": [],
            "meshes": [],
            "nodes": [],
            "materials": [],
            "scenes": [{"nodes": []}],
            "scene": 0,
        }
        self._materials: dict[tuple[str, ...], int] = {}

    def _view(self, payload: bytes, target: int | None) -> int:
        while len(self.bin) % 4:
            self.bin.append(0)
        view: dict = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(payload)}
        if target:
            view["target"] = target
        self.bin += payload
        self.doc["bufferViews"].append(view)
        return len(self.doc["bufferViews"]) - 1

    def accessor(
        self,
        values: Sequence[Sequence[float]] | Sequence[int],
        ctype: int,
        atype: str,
        target: int | None = None,
        normalized: bool = False,
        minmax: bool = False,
    ) -> int:
        fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[ctype]
        flat: list = []
        for v in values:
            if isinstance(v, (int, float)):
                flat.append(v)
            else:
                flat.extend(v)
        payload = struct.pack(f"<{len(flat)}{fmt}", *flat)
        acc: dict = {
            "bufferView": self._view(payload, target),
            "componentType": ctype,
            "count": len(values),
            "type": atype,
        }
        if normalized:
            acc["normalized"] = True
        if minmax and values:
            n = len(values[0])  # type: ignore[arg-type]
            cols = [[v[i] for v in values] for i in range(n)]  # type: ignore[index]
            acc["min"] = [min(c) for c in cols]
            acc["max"] = [max(c) for c in cols]
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def material(self, textures: list[TextureRef], tex_dirs: list[Path], out_dir: Path) -> int:
        key = tuple(t.shape for t in textures)
        if key in self._materials:
            return self._materials[key]
        mat: dict = {
            "name": "+".join(key) or "untextured",
            "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0},
            "extras": {"eagl_textures": [{"shape": t.shape, **t.attributes} for t in textures]},
        }
        if textures:
            img_idx = self._image(textures[0], tex_dirs, out_dir)
            if img_idx is not None:
                mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": img_idx}
        self.doc["materials"].append(mat)
        self._materials[key] = len(self.doc["materials"]) - 1
        return self._materials[key]

    def _image(self, tex: TextureRef, tex_dirs: list[Path], out_dir: Path) -> int | None:
        png = next(
            (d / f"{tex.shape}.png" for d in tex_dirs if (d / f"{tex.shape}.png").is_file()), None
        )
        if png is None:
            return None
        images = self.doc.setdefault("images", [])
        uri = Path(os.path.relpath(png, out_dir)).as_posix()
        for i, im in enumerate(images):
            if im["uri"] == uri:
                return i
        images.append({"uri": uri, "name": tex.shape})
        wrap = {"EAGL::PCCM_CLAMP": 33071, "EAGL::PCCM_WRAP": 10497}
        sampler = {
            "wrapS": wrap.get(tex.attributes.get("PCEXTOBJ_SetClampU", ""), 10497),
            "wrapT": wrap.get(tex.attributes.get("PCEXTOBJ_SetClampV", ""), 10497),
        }
        samplers = self.doc.setdefault("samplers", [])
        if sampler not in samplers:
            samplers.append(sampler)
        textures = self.doc.setdefault("textures", [])
        textures.append({"source": len(images) - 1, "sampler": samplers.index(sampler)})
        return len(textures) - 1


def _primitive(
    b: _GltfBuilder, obj: ElfObject, geo: Geometry, material: int, skinned: bool
) -> dict | None:
    v = geo.read_vertices(obj)
    attrs: dict[str, int] = {
        "POSITION": b.accessor(v["position"], 5126, "VEC3", 34962, minmax=True),
    }
    if "normal" in v:
        normals = []
        for n in v["normal"]:
            ln = math.sqrt(sum(c * c for c in n)) or 1.0
            normals.append((n[0] / ln, n[1] / ln, n[2] / ln))
        attrs["NORMAL"] = b.accessor(normals, 5126, "VEC3", 34962)
    for t in range(len(geo.layout.texcoords)):
        uv = [(c[0], c[1]) for c in v[f"uv{t}"]]
        attrs[f"TEXCOORD_{t}"] = b.accessor(uv, 5126, "VEC2", 34962)
    if "color" in v:
        attrs["COLOR_0"] = b.accessor(v["color"], 5126, "VEC4", 34962)
    if skinned and geo.compounds is not None and "beta" in v:
        joints, weights = [], []
        for (ci,) in v["beta"]:
            c = geo.compounds[ci]
            js = list(c.bones[:4]) + [0] * (4 - len(c.bones[:4]))
            ws = list(c.weights[:4]) + [0.0] * (4 - len(c.weights[:4]))
            joints.append(js)
            weights.append(ws)
        attrs["JOINTS_0"] = b.accessor(joints, 5123, "VEC4", 34962)
        attrs["WEIGHTS_0"] = b.accessor(weights, 5126, "VEC4", 34962)
    if geo.primitive in ("LINELIST", "LINESTRIP"):
        lines = geo.lines(obj)
        if not lines:
            return None
        flat = [i for ln in lines for i in ln]
        return {
            "attributes": attrs,
            "indices": b.accessor(flat, 5125, "SCALAR", 34963),
            "mode": 1,
            "material": material,
        }
    # EAGL front faces are clockwise (99.7% of strip triangles oppose the stored
    # normals under the right-hand rule); glTF wants counter-clockwise.
    tris = [(a, c, bb) for a, bb, c in geo.triangles(obj)]
    if not tris:
        return None
    flat = [i for t in tris for i in t]
    return {
        "attributes": attrs,
        "indices": b.accessor(flat, 5125, "SCALAR", 34963),
        "mode": 4,
        "material": material,
    }


def export_gltf(
    asset: Asset,
    out_path: Path,
    tex_dirs: list[Path] | None = None,
    skeleton: Skeleton | None = None,
    include_variations: bool = False,
) -> dict:
    """Write ``out_path`` (.gltf) and a sibling .bin; return a summary."""
    obj = asset.obj
    b = _GltfBuilder()
    out_dir = out_path.parent
    skel = asset.skeletons[0] if asset.skeletons else skeleton  # embedded wins
    summary: dict = {"meshes": 0, "primitives": 0, "triangles": 0, "lines": 0, "skinned": False}
    skin_index: int | None = None
    if skel is not None and any(g.compounds for g in asset.geometry.values()):
        skin_index = _add_skin(b, skel)
        summary["skinned"] = True
    models = [m for m in asset.models if include_variations or ".variation" not in m.symbol]
    if not models and asset.geometry:  # loose render methods without a Model
        models = [Model("", 0, "loose", (), (), (), (), [Part("all", list(asset.geometry))], 0, [])]
    root_children: list[int] = []
    for model in models:
        child_nodes: list[int] = []
        for part in model.parts:
            prims = []
            for rm_off in part.render_methods:
                geo = asset.geometry.get(rm_off)
                if geo is None:
                    continue
                mat = b.material(geo.textures, tex_dirs or [], out_dir)
                prim = _primitive(b, obj, geo, mat, skin_index is not None)
                if prim is None:
                    continue
                prims.append(prim)
                if prim["mode"] == 4:
                    summary["triangles"] += b.doc["accessors"][prim["indices"]]["count"] // 3
                else:
                    summary["lines"] += b.doc["accessors"][prim["indices"]]["count"] // 2
            if not prims:
                continue
            b.doc["meshes"].append({"name": f"{model.name}:{part.name}", "primitives": prims})
            node: dict = {"name": part.name, "mesh": len(b.doc["meshes"]) - 1}
            if skin_index is not None and any("JOINTS_0" in p["attributes"] for p in prims):
                node["skin"] = skin_index
            b.doc["nodes"].append(node)
            child_nodes.append(len(b.doc["nodes"]) - 1)
            summary["meshes"] += 1
            summary["primitives"] += len(prims)
        if child_nodes:
            mnode: dict = {"name": model.name, "children": child_nodes}
            if model.transform and model.transform != _IDENTITY:
                mnode["matrix"] = list(model.transform)
            b.doc["nodes"].append(mnode)
            root_children.append(len(b.doc["nodes"]) - 1)
    b.doc["scenes"][0]["nodes"] = root_children + (
        [b.doc["skins"][skin_index]["skeleton"]] if skin_index is not None else []
    )
    if not b.doc["materials"]:
        del b.doc["materials"]
    bin_path = out_path.with_suffix(".bin")
    b.doc["buffers"] = [{"uri": bin_path.name, "byteLength": len(b.bin)}]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bin_path.write_bytes(bytes(b.bin))
    out_path.write_text(json.dumps(b.doc, indent=1))
    return summary


_IDENTITY = (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)


def _add_skin(b: _GltfBuilder, skel: Skeleton) -> int:
    first = len(b.doc["nodes"])
    for bone in skel.bones:
        node: dict = {
            "name": bone.name,
            "translation": list(bone.translation),
            "rotation": list(bone.rotation),
        }
        if any(abs(s - 1.0) > 1e-6 for s in bone.scale):
            node["scale"] = list(bone.scale)
        b.doc["nodes"].append(node)
    for bone in skel.bones:
        if bone.parent >= 0:
            b.doc["nodes"][first + bone.parent].setdefault("children", []).append(
                first + bone.index
            )
    roots = [first + bone.index for bone in skel.bones if bone.parent < 0]
    # Row-vector D3D matrices stored row-major equal glTF column-major storage.
    ibm = b.accessor([bone.inverse_bind for bone in skel.bones], 5126, "MAT4")
    b.doc.setdefault("skins", []).append(
        {
            "name": skel.symbol.split(":::")[-1],
            "joints": [first + bone.index for bone in skel.bones],
            "inverseBindMatrices": ibm,
            "skeleton": roots[0],
        }
    )
    return len(b.doc["skins"]) - 1


# ---------------------------------------------------------------------------
# Software preview (orthographic, flat-shaded) -> PNG
# ---------------------------------------------------------------------------


def _png(width: int, height: int, rgb: bytearray) -> bytes:
    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\0" + bytes(rgb[y * width * 3 : (y + 1) * width * 3]) for y in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def render_preview(
    asset: Asset,
    out_png: Path,
    size: int = 512,
    yaw_deg: float = 30.0,
    pitch_deg: float = 15.0,
    skip_rms: set[str] | None = None,
) -> dict:
    """Rasterise every triangle chunk orthographically with a z-buffer."""
    obj = asset.obj
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)

    def view(p: tuple[float, ...]) -> tuple[float, float, float]:
        x, y, z = p[0], p[1], p[2]
        x, z = x * cy + z * sy, -x * sy + z * cy  # yaw about Y
        y, z = y * cp - z * sp, y * sp + z * cp  # pitch about X
        return x, y, z

    tris: list[tuple[tuple[float, float, float], ...]] = []
    colors: list[tuple[int, int, int]] = []
    palette = [(200, 120, 80), (90, 160, 210), (120, 200, 110), (220, 200, 90), (180, 110, 200)]
    for i, geo in enumerate(asset.geometry.values()):
        if skip_rms and geo.name in skip_rms:
            continue
        pos = [view(p) for p in geo.read_vertices(obj)["position"]]
        for t in geo.triangles(obj):
            tris.append((pos[t[0]], pos[t[1]], pos[t[2]]))
            colors.append(palette[i % len(palette)])
    if not tris:
        raise EaglError("nothing to render")
    xs = [v[0] for t in tris for v in t]
    ys = [v[1] for t in tris for v in t]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) or 1.0
    scale = (size - 16) / span
    ox, oy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    zbuf = [-math.inf] * (size * size)
    img = bytearray(b"\x20\x20\x28" * (size * size))
    for tri, col in zip(tris, colors, strict=True):
        pts = [((v[0] - ox) * scale + size / 2, size / 2 - (v[1] - oy) * scale, v[2]) for v in tri]
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = pts
        ux, uy, uz = tri[1][0] - tri[0][0], tri[1][1] - tri[0][1], tri[1][2] - tri[0][2]
        vx, vy, vz = tri[2][0] - tri[0][0], tri[2][1] - tri[0][1], tri[2][2] - tri[0][2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        shade = 0.25 + 0.75 * abs((0.3 * nx + 0.5 * ny + 0.8 * nz) / ln / 1.0)
        shade = min(shade, 1.0)
        c = bytes(min(255, int(ch * shade)) for ch in col)
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        minx, maxx = max(int(min(x0, x1, x2)), 0), min(int(max(x0, x1, x2)) + 1, size - 1)
        miny, maxy = max(int(min(y0, y1, y2)), 0), min(int(max(y0, y1, y2)) + 1, size - 1)
        for py in range(miny, maxy + 1):
            for px in range(minx, maxx + 1):
                fx, fy = px + 0.5, py + 0.5
                w0 = ((x1 - fx) * (y2 - fy) - (x2 - fx) * (y1 - fy)) / area
                w1 = ((x2 - fx) * (y0 - fy) - (x0 - fx) * (y2 - fy)) / area
                w2 = 1.0 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w0 * z0 + w1 * z1 + w2 * z2
                k = py * size + px
                if z > zbuf[k]:
                    zbuf[k] = z
                    img[3 * k : 3 * k + 3] = c
    out_png.parent.mkdir(parents=True, exist_ok=True)
    out_png.write_bytes(_png(size, size, img))
    return {"triangles": len(tris), "png": str(out_png)}


# ---------------------------------------------------------------------------
# Census and CLI
# ---------------------------------------------------------------------------


def find_elf_members(root: Path) -> list[Path]:
    """ELF members under ``root``; prefer ``X.unpacked`` (RefPack-decoded) over ``X``."""
    found: list[Path] = []
    for dirpath, _dirs, files in os.walk(root):
        names = set(files)
        for f in sorted(files):
            if f + ".unpacked" in names:
                continue
            p = Path(dirpath) / f
            try:
                with open(p, "rb") as fh:
                    if fh.read(4) == ELF_MAGIC:
                        found.append(p)
            except OSError:
                continue
    return sorted(found)


def normalise_symbol(name: str) -> str:
    """Strip instance-specific parts so names can be counted as patterns."""
    n = re.sub(r"UID=\d+", "UID=#", name)
    n = re.sub(r"SHAPENAME=[^;,]*,\d+", "SHAPENAME=*", n)
    n = re.sub(r"__geoprimdatabuffer_\d+_\d+_.*", "__geoprimdatabuffer_#_#_<model>", n)
    n = re.sub(r"__GPRenderMethod_.*_\d+$", "__GPRenderMethod_<model>_#", n)
    n = re.sub(r"(:::)([^:]+?)\.variation\d+$", r"\1<model>.variation#", n)
    n = re.sub(r"^(__(?:Model|BBOX|Skeleton):::)(?!<model>).*", r"\1<model>", n)
    n = re.sub(r"^(__Bone:::)[^.]+\.", r"\1<skel>.", n)
    return n


def classify(path: Path, asset: Asset) -> str:
    """Content guess from model, part and texture names (heuristic only)."""
    defined = " ".join(s.name for s in asset.obj.defined_symbols())
    if any("ParentRM_" in s.name for s in asset.obj.defined_symbols("__RenderMethod")):
        return "render-method-library"
    if not asset.models:
        if asset.skeletons:
            return "skeleton"
        return "animation-bank" if "__AnimationBank" in defined else "unknown"
    names = " ".join(m.name for m in asset.models).lower()
    shapes = {t.shape for g in asset.geometry.values() for t in g.textures}
    for key, label in (
        ("player", "player-body"),
        ("referee", "referee-body"),
        ("hair_temp", "head (skinned, hair_temp)"),
        ("head_temp", "head (skinned, head_temp)"),
        ("stadium", "stadium"),
        ("pitchlines", "pitch-lines"),
        ("pitch", "pitch"),
        ("lines", "pitch-lines"),
        ("sky", "sky"),
        ("flag", "corner-flag"),
        ("ball", "ball/ball-ui"),
        ("drill", "training-drill-ui"),
        ("globe", "frontend-globe"),
    ):
        if key in names:
            return label
    if "envm" in shapes or "troph" in names:
        return "trophy"
    if "face" in shapes or "hifa" in shapes:
        return "head"
    if shapes and shapes <= {"dirt", "hair"}:
        return "hair"
    if shapes and shapes <= {"dirt", "eart"}:
        return "ear-tape"
    if "shad" in shapes or "shadow" in names:
        return "shadow"
    return "prop/ui"


def census(root: Path) -> dict:
    files = find_elf_members(root)
    patterns: Counter[str] = Counter()
    undefined: Counter[str] = Counter()
    reloc_types: Counter[int] = Counter()
    fvfs: Counter[str] = Counter()
    prims: Counter[str] = Counter()
    microcodes: Counter[str] = Counter()
    kinds: Counter[str] = Counter()
    shapes_all: Counter[str] = Counter()
    sections: Counter[str] = Counter()
    entries = []
    for p in files:
        rel = p.relative_to(root).as_posix()
        try:
            asset = load_asset(p)
        except (EaglError, struct.error, ValueError) as exc:
            entries.append({"path": rel, "error": str(exc)})
            continue
        obj = asset.obj
        sections[",".join(s.name for s in obj.sections if s.name)] += 1
        for s in obj.symbols:
            if s.type == STT_SECTION or not s.name:
                continue
            key = ("DEF " if s.defined else "UND ") + normalise_symbol(s.name)
            patterns[key] += 1
            if not s.defined:
                undefined[normalise_symbol(s.name)] += 1
        for rl in obj.relocs.values():
            for r in rl:
                reloc_types[r.type] += 1
        kind = classify(p, asset)
        kinds[kind] += 1
        shapes = sorted({t.shape for g in asset.geometry.values() for t in g.textures})
        shapes_all.update(shapes)
        nverts = sum(g.vertex_count for g in asset.geometry.values())
        nidx = sum(g.index_count for g in asset.geometry.values())
        for g in asset.geometry.values():
            fvfs[f"{g.layout.fvf:#x}/stride{g.layout.stride}"] += 1
            prims[g.primitive] += 1
            microcodes[(g.microcode or "?").replace("__EAGLMicroCode", "")] += 1
        entries.append(
            {
                "path": rel,
                "kind_guess": kind,
                "data_size": len(obj.data),
                "relocations": sum(len(v) for v in obj.relocs.values()),
                "models": [
                    {
                        "symbol": m.symbol,
                        "name": m.name,
                        "parts": [pt.name for pt in m.parts],
                        "bbox": [list(m.bbox_min), list(m.bbox_max)],
                    }
                    for m in asset.models
                    if ".variation" not in m.symbol
                ],
                "variations": sum(1 for m in asset.models if ".variation" in m.symbol),
                "render_methods": len(asset.render_methods),
                "geometry_chunks": len(asset.geometry),
                "vertices": nverts,
                "indices": nidx,
                "skinned_chunks": sum(1 for g in asset.geometry.values() if g.compounds),
                "skeleton_bones": [len(s.bones) for s in asset.skeletons],
                "texture_shapes": shapes,
                "errors": asset.errors,
            }
        )
    return {
        "root": str(root),
        "objects": len(files),
        "kinds": dict(kinds.most_common()),
        "section_layouts": dict(sections.most_common()),
        "relocation_types": {
            ("R_MIPS_32" if t == R_MIPS_32 else f"type_{t}"): n for t, n in reloc_types.items()
        },
        "fvf_formats": dict(fvfs.most_common()),
        "primitive_types": dict(prims.most_common()),
        "microcodes": dict(microcodes.most_common()),
        "symbol_patterns": dict(patterns.most_common()),
        "texture_shapes": dict(shapes_all.most_common()),
        "decode_errors": sum(len(e.get("errors", [])) + ("error" in e) for e in entries),
        "files": entries,
    }


def dump(asset: Asset) -> str:
    """Human-readable structure dump of one object."""
    lines = []
    obj = asset.obj
    lines.append(f".data {len(obj.data)} bytes, {len(obj._ptrs)} relocations")
    for m in asset.models:
        lines.append(f"Model {m.symbol} @{m.offset:#x} name={m.name!r} variation={m.variation}")
        lines.append(
            f"  bbox {tuple(round(x, 3) for x in m.bbox_min)} .. "
            f"{tuple(round(x, 3) for x in m.bbox_max)} sphere "
            f"{tuple(round(x, 3) for x in m.sphere)}"
        )
        if m.texture_table:
            lines.append("  textures " + ", ".join(f"{t.shape},{t.group}" for t in m.texture_table))
        for pt in m.parts:
            lines.append(
                f"  part {pt.name!r}: RM " + ", ".join(f"{r:#x}" for r in pt.render_methods)
            )
    for off, rm in asset.render_methods.items():
        geo = asset.geometry.get(off)
        lines.append(
            f"RenderMethod {rm.name} @{off:#x} shader={rm.shader_name} "
            f"stream={rm.stream and hex(rm.stream)} bindings={len(rm.bindings)} cmds={rm.commands}"
        )
        if geo:
            lines.append(
                f"  {geo.primitive} fvf={geo.layout.fvf:#x} stride={geo.layout.stride} "
                f"verts={geo.vertex_count}@{geo.vertex_offset:#x} "
                f"indices={geo.index_count}@{geo.index_offset:#x} "
                f"textures={[t.shape for t in geo.textures]} "
                f"compounds={len(geo.compounds) if geo.compounds else 0}"
            )
    for sk in asset.skeletons:
        lines.append(f"Skeleton {sk.symbol}: {len(sk.bones)} bones")
        for bone in sk.bones:
            lines.append(
                f"  {bone.index:3d} {bone.name:<16} parent={bone.parent:3d} "
                f"t={tuple(round(x, 3) for x in bone.translation)}"
            )
    for e in asset.errors:
        lines.append(f"ERROR {e}")
    return "\n".join(lines)


def texture_dirs_for(model_path: Path, extracted: Path, textures: Path) -> list[Path]:
    """Decoded-texture directories of FSH archives stored next to a model.

    Only used for models inside a small nested archive (where the FSH is a
    sibling member); loose ``data.gob`` members have no known texture link.
    """
    try:
        rel_dir = model_path.parent.relative_to(extracted)
    except ValueError:
        return []
    cand = textures / rel_dir
    if not cand.is_dir():
        return []
    dirs = sorted(d for d in cand.iterdir() if d.is_dir() and d.suffix.lower() == ".fsh")
    return dirs if len(dirs) <= 8 else []


def _out_name(path: Path, extracted: Path) -> str:
    try:
        rel = path.relative_to(extracted)
    except ValueError:
        return path.stem
    parts = [p for p in rel.parts]
    return "__".join(parts).replace(".unpacked", "").replace("!", "_")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="python -m openrugby_tools.eagl", description=__doc__.split("\n")[0]
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("census", help="survey every ELF member under a root")
    c.add_argument("root", nargs="?", type=Path, default=DEFAULT_EXTRACTED)
    c.add_argument("-o", "--out", type=Path, default=DEFAULT_CENSUS)
    d = sub.add_parser("dump", help="print the decoded structure of one object")
    d.add_argument("path", type=Path)
    g = sub.add_parser("gltf", help="convert objects to glTF 2.0 (.gltf + .bin)")
    g.add_argument("paths", nargs="+", type=Path)
    g.add_argument("-o", "--out-dir", type=Path, default=DEFAULT_MODELS)
    g.add_argument("--skeleton", type=Path, help="object with a __Skeleton (e.g. !skel.o)")
    g.add_argument("--textures", type=Path, default=DEFAULT_TEXTURES)
    g.add_argument("--variations", action="store_true", help="also export .variationN models")
    pv = sub.add_parser("preview", help="render an orthographic flat-shaded PNG")
    pv.add_argument("path", type=Path)
    pv.add_argument("-o", "--out", type=Path, required=True)
    pv.add_argument("--size", type=int, default=512)
    pv.add_argument("--yaw", type=float, default=30.0)
    pv.add_argument("--pitch", type=float, default=15.0)
    args = ap.parse_args(argv)

    if args.cmd == "census":
        result = census(args.root)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=1))
        print(f"{result['objects']} objects, {result['decode_errors']} decode errors -> {args.out}")
        print(json.dumps(result["kinds"]))
        return 0
    if args.cmd == "dump":
        print(dump(load_asset(args.path)))
        return 0
    if args.cmd == "preview":
        info = render_preview(load_asset(args.path), args.out, args.size, args.yaw, args.pitch)
        print(json.dumps(info))
        return 0
    skel = None
    if args.skeleton:
        sk_asset = load_asset(args.skeleton)
        if not sk_asset.skeletons:
            print(f"no skeleton in {args.skeleton}", file=sys.stderr)
            return 2
        skel = sk_asset.skeletons[0]
    status = 0
    for p in args.paths:
        try:
            asset = load_asset(p)
        except (EaglError, struct.error, ValueError) as exc:
            print(f"{p}: {exc}", file=sys.stderr)
            status = 1
            continue
        out = args.out_dir / (_out_name(p.resolve(), DEFAULT_EXTRACTED.resolve()) + ".gltf")
        tex_dirs = texture_dirs_for(
            p.resolve(), DEFAULT_EXTRACTED.resolve(), args.textures.resolve()
        )
        info = export_gltf(asset, out, tex_dirs, skel, args.variations)
        print(f"{p} -> {out} {json.dumps(info)}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
