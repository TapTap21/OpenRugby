#!/usr/bin/env python3
"""Dump an unpacked 32-bit Windows PE image from a process running under Wine.

Purpose
-------
OpenRugby Phase 1 needs a statically analysable copy of ``Rugby08.exe``. The
shipped binary is wrapped in a UPX-family packer (sections renamed ``.ROT`` /
``.IN`` / ``.HEAVEN`` by the ViTALiTY release group). This script runs the
packed exe under Wine as a *child* of itself (so ``/proc/PID/mem`` is readable
under ``kernel.yama.ptrace_scope=1``), lets the packer stub decompress the
image, then reads the image from memory and rebuilds a loadable PE with a
fresh import directory and the original entry point.

Stdlib only. Linux only (uses /proc and prctl).

How the OEP is found ("hold" mode, default)
-------------------------------------------
1. The packed file's entry stub is scanned for the UPX-style tail
   ``popad ... jmp rel32``; the jmp target is the original entry point (OEP).
2. As soon as the Wine process maps the exe, the tail ``jmp`` is overwritten
   in the *process memory only* with ``EB FE`` (jmp $) via ``/proc/PID/mem``.
   The file on disk is never written.
3. When the stub finishes (code present at the OEP, image stable, main thread
   spinning) the process is SIGSTOPped and dumped. Because no game code has
   run, ``.data`` is in its pristine, as-loaded state and the IAT is filled.
4. The patched bytes are restored in the dump.

``--mode delay`` instead lets the program run for ``--delay`` seconds and dumps
whatever is in memory (data sections then hold runtime state). The OEP is
still taken from the stub tail or ``--oep``.

How imports are rebuilt
-----------------------
* Loaded modules are enumerated from ``/proc/PID/maps`` (Wine maps PE DLLs as
  files); each 32-bit module's export table is parsed *from process memory*,
  including forwarders (e.g. kernel32!HeapAlloc -> ntdll!RtlAllocateHeap).
* If the stub is the UPX import loop, the packer's own import blob (DLL name,
  IAT address, function names/ordinals) is parsed from memory. That is the
  authoritative name source; every slot is cross-checked against the export
  resolution of the live pointer.
* Otherwise IAT slots are found by scanning for runs of dwords that resolve to
  module exports.
* A new ``.idata`` section is appended with descriptors, ILT, hint/name
  entries and DLL names; ``FirstThunk`` points at the original IAT slots,
  which are rewritten to match the ILT (an unbound import table).

Outputs (``--out-dir``)
-----------------------
* ``<stem>_raw_<base>-<end>.bin``  raw memory of the image range
* ``<stem>_unpacked.exe``           rebuilt PE (raw size == virtual size)
* ``<stem>_dump_report.json``       OEP, method, sections, imports, timing
* ``wine.log``                      Wine stdout/stderr

Example
-------
    python3 tools/re/dump_wine_process.py \\
        --exe /path/to/Rugby-08/Rugby08.exe \\
        --prefix .omc/research/wineprefix \\
        --out-dir .omc/research/unpacked

Never point ``--out-dir`` at a tracked directory: dumps are copyrighted code.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import signal
import struct
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

PR_SET_CHILD_SUBREAPER = 36

# --------------------------------------------------------------------------
# PE helpers (file and memory)
# --------------------------------------------------------------------------


@dataclass
class Section:
    name: str
    vsize: int
    rva: int
    rsize: int
    roff: int
    chars: int


@dataclass
class PEInfo:
    e_lfanew: int
    opt_off: int
    opt_size: int
    nsec: int
    image_base: int
    entry_rva: int
    size_of_image: int
    size_of_headers: int
    sect_align: int
    file_align: int
    data_dirs: list[tuple[int, int]]
    sections: list[Section]


def parse_pe_headers(buf: bytes) -> PEInfo:
    if buf[:2] != b"MZ":
        raise ValueError("not an MZ image")
    e = struct.unpack_from("<I", buf, 0x3C)[0]
    if buf[e : e + 4] != b"PE\0\0":
        raise ValueError("no PE signature")
    (nsec,) = struct.unpack_from("<H", buf, e + 6)
    (opt_size,) = struct.unpack_from("<H", buf, e + 20)
    opt = e + 24
    (magic,) = struct.unpack_from("<H", buf, opt)
    if magic != 0x10B:
        raise ValueError("only PE32 (32-bit) images are supported")
    (entry,) = struct.unpack_from("<I", buf, opt + 16)
    image_base, sect_align, file_align = struct.unpack_from("<III", buf, opt + 28)
    size_of_image, size_of_headers = struct.unpack_from("<II", buf, opt + 56)
    (ndirs,) = struct.unpack_from("<I", buf, opt + 92)
    dirs = [struct.unpack_from("<II", buf, opt + 96 + i * 8) for i in range(min(ndirs, 16))]
    secs = []
    s = opt + opt_size
    for i in range(nsec):
        raw = struct.unpack_from("<8sIIII12xI", buf, s + i * 40)
        secs.append(
            Section(raw[0].rstrip(b"\0").decode("latin-1"), raw[1], raw[2], raw[3], raw[4], raw[5])
        )
    return PEInfo(
        e,
        opt,
        opt_size,
        nsec,
        image_base,
        entry,
        size_of_image,
        size_of_headers,
        sect_align,
        file_align,
        dirs,
        secs,
    )


def rva_to_off(pe: PEInfo, rva: int) -> int | None:
    for s in pe.sections:
        if s.rva <= rva < s.rva + max(s.rsize, s.vsize):
            if rva - s.rva < s.rsize:
                return s.roff + rva - s.rva
            return None
    return rva if rva < pe.size_of_headers else None


def cstr(buf: bytes, off: int, limit: int = 512) -> str:
    end = buf.find(b"\0", off, off + limit)
    if end < 0:
        end = off + limit
    return buf[off:end].decode("latin-1")


def decode_rich(header: bytes) -> list[dict]:
    """Decode the MSVC Rich header (linker/compiler build ids) if present."""
    end = header.find(b"Rich", 0x80, 0x400)
    if end < 0:
        return []
    key = header[end + 4 : end + 8]
    k = struct.unpack("<I", key)[0]
    # walk back to DanS
    start = None
    for off in range(end - 4, 0x7C, -4):
        if struct.unpack_from("<I", header, off)[0] ^ k == 0x536E6144:  # 'DanS'
            start = off
            break
    if start is None:
        return []
    out = []
    for off in range(start + 16, end, 8):
        compid = struct.unpack_from("<I", header, off)[0] ^ k
        count = struct.unpack_from("<I", header, off + 4)[0] ^ k
        out.append({"prod_id": compid >> 16, "build": compid & 0xFFFF, "count": count})
    return out


# --------------------------------------------------------------------------
# /proc helpers
# --------------------------------------------------------------------------


@dataclass
class MapEntry:
    start: int
    end: int
    perms: str
    offset: int
    path: str


def read_maps(pid: int) -> list[MapEntry]:
    out = []
    try:
        with open(f"/proc/{pid}/maps") as f:
            for line in f:
                parts = line.split(None, 5)
                a, b = parts[0].split("-")
                path = parts[5].strip() if len(parts) > 5 else ""
                out.append(MapEntry(int(a, 16), int(b, 16), parts[1], int(parts[2], 16), path))
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
    return out


class ProcMem:
    def __init__(self, pid: int):
        self.pid = pid
        self.fd = os.open(f"/proc/{pid}/mem", os.O_RDWR)

    def read(self, addr: int, size: int) -> bytes:
        try:
            return os.pread(self.fd, size, addr)
        except OSError:
            return b""

    def read_region(
        self, start: int, end: int, maps: list[MapEntry]
    ) -> tuple[bytes, list[list[int]]]:
        """Read [start,end) filling unmapped/unreadable holes with zeros."""
        buf = bytearray(end - start)
        holes = []
        cur = start
        for m in sorted(maps, key=lambda m: m.start):
            if m.end <= start or m.start >= end:
                continue
            a, b = max(m.start, start), min(m.end, end)
            if a > cur:
                holes.append([cur, a])
            step = 1 << 20
            for p in range(a, b, step):
                n = min(step, b - p)
                data = self.read(p, n)
                if len(data) != n:
                    holes.append([p, p + n])
                    continue
                buf[p - start : p - start + n] = data
            cur = max(cur, b)
        if cur < end:
            holes.append([cur, end])
        return bytes(buf), holes

    def write(self, addr: int, data: bytes) -> int:
        return os.pwrite(self.fd, data, addr)

    def close(self) -> None:
        os.close(self.fd)


def proc_children_tree(root: int) -> list[int]:
    """All live processes whose ancestry reaches `root` (we are a subreaper)."""
    ppid = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                st = f.read()
            ppid[int(d)] = int(st[st.rfind(")") + 2 :].split()[1])
        except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
            continue
    out = []
    for pid in ppid:
        p, seen = pid, 0
        while p in ppid and seen < 64:
            p = ppid[p]
            seen += 1
            if p == root:
                out.append(pid)
                break
    return out


def find_target(root: int, exe_path: str, base: int) -> int | None:
    for pid in proc_children_tree(root):
        for m in read_maps(pid):
            if m.start == base and m.path == exe_path:
                return pid
    return None


def thread_cpu_ticks(pid: int) -> dict[int, int]:
    out = {}
    try:
        for tid in os.listdir(f"/proc/{pid}/task"):
            try:
                with open(f"/proc/{pid}/task/{tid}/stat") as f:
                    st = f.read()
                fields = st[st.rfind(")") + 2 :].split()
                out[int(tid)] = int(fields[11]) + int(fields[12])
            except (FileNotFoundError, ProcessLookupError):
                pass
    except FileNotFoundError:
        pass
    return out


# --------------------------------------------------------------------------
# Module exports
# --------------------------------------------------------------------------


@dataclass
class Module:
    name: str
    path: str
    base: int
    size: int
    exports: dict[int, list[tuple[str | None, int]]] = field(
        default_factory=dict
    )  # addr -> [(name, ordinal)]
    by_name: dict[str, int] = field(default_factory=dict)
    by_ord: dict[int, int] = field(default_factory=dict)
    forwarders: list[tuple[str | None, int, str]] = field(
        default_factory=list
    )  # (name, ord, "DLL.Func")


def enumerate_modules(mem: ProcMem, maps: list[MapEntry]) -> list[Module]:
    by_path: dict[str, list[MapEntry]] = {}
    for m in maps:
        if m.path.lower().endswith((".dll", ".drv", ".exe", ".acm", ".ocx", ".cpl", ".sys")):
            by_path.setdefault(m.path, []).append(m)
    mods = []
    for path, ents in by_path.items():
        base = min(e.start for e in ents)
        if base >= 1 << 32:
            continue  # 64-bit side of Wine's WoW64
        hdr = mem.read(base, 0x1000)
        try:
            pe = parse_pe_headers(hdr)
        except (ValueError, struct.error):
            continue
        mod = Module(Path(path).name.lower(), path, base, pe.size_of_image)
        ed_rva, ed_size = pe.data_dirs[0] if pe.data_dirs else (0, 0)
        if ed_rva and ed_size:
            ed = mem.read(base + ed_rva, 40)
            if len(ed) == 40:
                (_, _, _, _, name_rva, ord_base, nfuncs, nnames, funcs_rva, names_rva, ords_rva) = (
                    struct.unpack("<IIHHIIIIIII", ed)
                )
                funcs = mem.read(base + funcs_rva, nfuncs * 4)
                names = mem.read(base + names_rva, nnames * 4)
                ords = mem.read(base + ords_rva, nnames * 2)
                idx_name: dict[int, str] = {}
                for i in range(min(nnames, len(names) // 4, len(ords) // 2)):
                    nrva = struct.unpack_from("<I", names, i * 4)[0]
                    idx = struct.unpack_from("<H", ords, i * 2)[0]
                    raw = mem.read(base + nrva, 256)
                    idx_name[idx] = raw.split(b"\0", 1)[0].decode("latin-1")
                for i in range(len(funcs) // 4):
                    frva = struct.unpack_from("<I", funcs, i * 4)[0]
                    if not frva:
                        continue
                    ordinal = ord_base + i
                    nm = idx_name.get(i)
                    if ed_rva <= frva < ed_rva + ed_size:
                        fwd = mem.read(base + frva, 256).split(b"\0", 1)[0].decode("latin-1")
                        mod.forwarders.append((nm, ordinal, fwd))
                        continue
                    addr = base + frva
                    mod.exports.setdefault(addr, []).append((nm, ordinal))
                    if nm:
                        mod.by_name[nm] = addr
                    mod.by_ord[ordinal] = addr
        mods.append(mod)
    return mods


class Resolver:
    """Map an absolute address to the export(s) that produce it."""

    def __init__(self, mods: list[Module]):
        self.mods = mods
        self.by_short = {}
        for m in mods:
            self.by_short.setdefault(m.name.rsplit(".", 1)[0], m)
        # addr -> list[(dll, name, ordinal, via_forwarder)]
        self.table: dict[int, list[tuple[str, str | None, int, bool]]] = {}
        for m in mods:
            for addr, lst in m.exports.items():
                for nm, o in lst:
                    self.table.setdefault(addr, []).append((m.name, nm, o, False))
        for m in mods:
            for nm, o, fwd in m.forwarders:
                addr = self._resolve_fwd(fwd)
                if addr is not None:
                    self.table.setdefault(addr, []).append((m.name, nm, o, True))

    def _resolve_fwd(self, fwd: str, depth: int = 0) -> int | None:
        if "." not in fwd or depth > 8:
            return None
        dll, func = fwd.split(".", 1)
        tgt = self.by_short.get(dll.lower())
        if tgt is None:
            return None
        if func.startswith("#"):
            return tgt.by_ord.get(int(func[1:]))
        if func in tgt.by_name:
            return tgt.by_name[func]
        for nm, _o, f2 in tgt.forwarders:
            if nm == func:
                return self._resolve_fwd(f2, depth + 1)
        return None

    def module_of(self, addr: int) -> Module | None:
        for m in self.mods:
            if m.base <= addr < m.base + m.size:
                return m
        return None

    def lookup(self, addr: int):
        return self.table.get(addr, [])

    def address_of(self, dll: str, name: str | None, ordinal: int | None) -> list[int]:
        """All addresses a (dll, name|ordinal) import could legitimately hold."""
        m = self.by_short.get(dll.lower().rsplit(".", 1)[0])
        if m is None:
            return []
        if name is not None:
            if name in m.by_name:
                return [m.by_name[name]]
            for nm, _o, fwd in m.forwarders:
                if nm == name:
                    a = self._resolve_fwd(fwd)
                    return [a] if a is not None else []
            return []
        if ordinal in m.by_ord:
            return [m.by_ord[ordinal]]
        for _nm, o, fwd in m.forwarders:
            if o == ordinal:
                a = self._resolve_fwd(fwd)
                return [a] if a is not None else []
        return []


# --------------------------------------------------------------------------
# UPX-family stub analysis
# --------------------------------------------------------------------------


def find_stub_tail_jmp(code: bytes, code_va: int) -> tuple[int, int] | None:
    """Find `popad` followed (within 0x20 bytes) by `jmp rel32`; return (jmp_va, target)."""
    for i in range(len(code) - 5):
        if code[i] != 0x61:
            continue
        for j in range(i + 1, min(i + 0x20, len(code) - 5)):
            if code[j] == 0xE9:
                rel = struct.unpack_from("<i", code, j + 1)[0]
                tgt = (code_va + j + 5 + rel) & 0xFFFFFFFF
                if not (code_va <= tgt < code_va + len(code)):
                    return code_va + j, tgt
    return None


def find_upx_import_loop(code: bytes, code_va: int) -> dict | None:
    """Locate the UPX import loop and return the blob/name-base/ESI parameters.

    Pattern (UPX win32/pe): 60 BE <esi> 8D BE <dst-esi> ... 8D BE <blob-esi>
    8B 07 09 C0 74 ?? 8B 5F 04 8D 84 30 <names-esi>.
    ESI after the decompressor equals the pushed destination.
    """
    if code[0:2] != b"\x60\xbe" or code[6:8] != b"\x8d\xbe":
        return None
    esi0 = struct.unpack_from("<I", code, 2)[0]
    dst = (esi0 + struct.unpack_from("<i", code, 8)[0]) & 0xFFFFFFFF
    sig = b"\x8b\x07\x09\xc0\x74"
    i = code.find(sig)
    while i >= 0:
        if (
            code[i - 6 : i - 4] == b"\x8d\xbe"
            and code[i + 6 : i + 9] == b"\x8b\x5f\x04"
            and code[i + 9 : i + 12] == b"\x8d\x84\x30"
        ):
            blob_off = struct.unpack_from("<I", code, i - 4)[0]
            names_off = struct.unpack_from("<I", code, i + 12)[0]
            return {
                "dest": dst,
                "blob_va": (dst + blob_off) & 0xFFFFFFFF,
                "names_base_va": (dst + names_off) & 0xFFFFFFFF,
                "loop_va": code_va + i - 6,
            }
        i = code.find(sig, i + 1)
    return None


def parse_upx_import_blob(image: bytes, image_base: int, info: dict) -> list[dict]:
    """Walk the UPX import blob. Returns [{dll, iat_va, entries:[{name|ordinal}]}]."""
    pos = info["blob_va"] - image_base
    out = []
    while True:
        name_off, iat_off = struct.unpack_from("<II", image, pos)
        if name_off == 0:
            break
        pos += 8
        dll = cstr(image, info["names_base_va"] + name_off - image_base)
        ents = []
        while True:
            tag = image[pos]
            pos += 1
            if tag == 0:
                break
            if tag & 0x80:
                ordinal = struct.unpack_from("<H", image, pos)[0]
                pos += 2
                ents.append({"ordinal": ordinal})
            else:
                nm = cstr(image, pos)
                pos += len(nm) + 1
                ents.append({"name": nm})
        out.append({"dll": dll, "iat_va": (info["dest"] + iat_off) & 0xFFFFFFFF, "entries": ents})
    return out


# --------------------------------------------------------------------------
# Generic IAT scan (fallback when no UPX blob)
# --------------------------------------------------------------------------


def scan_iat(image: bytes, image_base: int, resolver: Resolver, lo: int, hi: int) -> list[dict]:
    blocks, cur = [], None
    for va in range(lo, hi, 4):
        v = struct.unpack_from("<I", image, va - image_base)[0]
        hits = resolver.lookup(v) if v else []
        if hits:
            dll, nm, o, _ = hits[0]
            if cur is None or cur["dll"] != dll or va != cur["iat_va"] + 4 * len(cur["entries"]):
                cur = {"dll": dll, "iat_va": va, "entries": []}
                blocks.append(cur)
            cur["entries"].append({"name": nm} if nm else {"ordinal": o})
        else:
            cur = None
    return [b for b in blocks if len(b["entries"]) >= 1]


# --------------------------------------------------------------------------
# PE rebuild
# --------------------------------------------------------------------------


def align(x: int, a: int) -> int:
    return (x + a - 1) & ~(a - 1)


def build_idata(blocks: list[dict], rva: int) -> bytes:
    """Build descriptors + ILTs + hint/names + dll names at section RVA `rva`."""
    ndesc = len(blocks) + 1
    desc_size = ndesc * 20
    ilt_size = sum((len(b["entries"]) + 1) * 4 for b in blocks)
    strings = bytearray()
    str_base = rva + desc_size + ilt_size
    desc = bytearray()
    ilt = bytearray()
    ilt_cursor = rva + desc_size
    for b in blocks:
        b["ilt"] = []
        dll_rva = str_base + len(strings)
        strings += b["dll"].encode("latin-1") + b"\0"
        if len(strings) % 2:
            strings += b"\0"
        for e in b["entries"]:
            if "name" in e and e["name"] is not None:
                hn = str_base + len(strings)
                strings += struct.pack("<H", 0) + e["name"].encode("latin-1") + b"\0"
                if len(strings) % 2:
                    strings += b"\0"
                b["ilt"].append(hn)
            else:
                b["ilt"].append(0x80000000 | e["ordinal"])
        desc += struct.pack("<IIIII", ilt_cursor, 0, 0, dll_rva, b["iat_va_rva"])
        for t in b["ilt"]:
            ilt += struct.pack("<I", t)
        ilt += b"\0\0\0\0"
        ilt_cursor += (len(b["entries"]) + 1) * 4
    desc += b"\0" * 20
    return bytes(desc + ilt + strings)


def rebuild_pe(
    orig_file: bytes,
    image: bytearray,
    image_base: int,
    oep_va: int | None,
    layout: list[tuple[str, int, int, int]],
    blocks: list[dict],
) -> tuple[bytes, dict]:
    """layout: [(name, va_start, va_end, characteristics)] contiguous, page aligned."""
    pe = parse_pe_headers(orig_file)
    sa, fa = pe.sect_align, 0x200
    last_end = layout[-1][2]
    idata_rva = last_end - image_base
    for b in blocks:
        b["iat_va_rva"] = b["iat_va"] - image_base
    idata = build_idata(blocks, idata_rva)
    # rewrite IAT slots in image so they match the ILT (unbound)
    iat_lo, iat_hi = None, None
    for b in blocks:
        for i, t in enumerate(b["ilt"]):
            off = b["iat_va"] - image_base + 4 * i
            struct.pack_into("<I", image, off, t)
        end_off = b["iat_va"] - image_base + 4 * len(b["ilt"])
        if end_off + 4 <= len(image) and not any(
            b2["iat_va"] == b["iat_va"] + 4 * len(b["ilt"]) for b2 in blocks
        ):
            struct.pack_into("<I", image, end_off, 0)
        lo, hi = b["iat_va"] - image_base, end_off + 4
        iat_lo = lo if iat_lo is None else min(iat_lo, lo)
        iat_hi = hi if iat_hi is None else max(iat_hi, hi)

    secs = [(n, a - image_base, e - a, c) for n, a, e, c in layout]
    secs.append((".idata", idata_rva, align(len(idata), sa), 0xC0000040))
    hdr = bytearray(orig_file[: pe.size_of_headers])
    nsec = len(secs)
    sec_tab = pe.opt_off + pe.opt_size
    if sec_tab + nsec * 40 > pe.size_of_headers:
        raise ValueError("no room for section headers")
    raw_ptr = align(pe.size_of_headers, fa)
    body = bytearray()
    for i, (name, rva, vsize, chars) in enumerate(secs):
        if name == ".idata":
            data = idata + b"\0" * (vsize - len(idata))
        else:
            data = bytes(image[rva : rva + vsize])
        rsize = align(len(data), fa)
        struct.pack_into(
            "<8sIIIIIIHHI",
            hdr,
            sec_tab + i * 40,
            name.encode()[:8],
            vsize,
            rva,
            rsize,
            raw_ptr + len(body),
            0,
            0,
            0,
            0,
            chars,
        )
        body += data + b"\0" * (rsize - len(data))
    for i in range(nsec, pe.nsec):
        struct.pack_into("<40s", hdr, sec_tab + i * 40, b"\0" * 40)
    e = pe.e_lfanew
    struct.pack_into("<H", hdr, e + 6, nsec)
    (chars,) = struct.unpack_from("<H", hdr, e + 22)
    struct.pack_into("<H", hdr, e + 22, chars | 0x0001)  # relocs stripped
    opt = pe.opt_off
    if oep_va is not None:
        struct.pack_into("<I", hdr, opt + 16, oep_va - image_base)
    size_of_image = idata_rva + align(len(idata), sa)
    struct.pack_into("<I", hdr, opt + 56, size_of_image)
    struct.pack_into("<I", hdr, opt + 64, 0)  # checksum
    # SizeOfCode / SizeOfInitializedData / BaseOfCode / BaseOfData (best effort)
    code = [s for s in secs if s[3] & 0x20]
    struct.pack_into("<I", hdr, opt + 4, sum(s[2] for s in code))
    struct.pack_into("<I", hdr, opt + 8, sum(s[2] for s in secs if not s[3] & 0x20))
    struct.pack_into("<I", hdr, opt + 12, 0)
    if code:
        struct.pack_into("<I", hdr, opt + 20, code[0][1])
    data_secs = [s for s in secs if not s[3] & 0x20]
    if data_secs:
        struct.pack_into("<I", hdr, opt + 24, data_secs[0][1])
    dd = opt + 96
    struct.pack_into("<II", hdr, dd + 1 * 8, idata_rva, 20 * (len(blocks) + 1))
    if iat_lo is not None:
        struct.pack_into("<II", hdr, dd + 12 * 8, iat_lo, iat_hi - iat_lo)
    for idx in (
        4,
        5,
        6,
        9,
        10,
        11,
        13,
        14,
    ):  # security, reloc, debug, tls, loadcfg, bound, delay, clr
        if pe.data_dirs[idx][0] and idx in (4, 5, 11):
            struct.pack_into("<II", hdr, dd + idx * 8, 0, 0)
    out = bytes(hdr) + b"\0" * (raw_ptr - len(hdr)) + bytes(body)
    return out, {
        "idata_rva": idata_rva,
        "idata_size": len(idata),
        "size_of_image": size_of_image,
        "iat_dir": [iat_lo, (iat_hi or 0) - (iat_lo or 0)],
    }


# --------------------------------------------------------------------------
# Main flow
# --------------------------------------------------------------------------


def log(msg: str) -> None:
    print(f"[dump {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--exe", required=True, help="path to the packed Windows exe (never written)")
    ap.add_argument("--cwd", help="working directory for the game (default: exe directory)")
    ap.add_argument("--prefix", required=True, help="WINEPREFIX to use")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--wine", default="wine")
    ap.add_argument("--mode", choices=["hold", "delay"], default="hold")
    ap.add_argument(
        "--delay", type=float, default=8.0, help="seconds to run before dumping (delay mode)"
    )
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--oep", type=lambda s: int(s, 0), help="override OEP VA")
    ap.add_argument("--stem", help="output file stem (default: exe stem)")
    ap.add_argument("--dll-overrides", default="", help="WINEDLLOVERRIDES value")
    args = ap.parse_args()

    exe = Path(args.exe).resolve()
    out = Path(args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    stem = args.stem or exe.stem
    orig = exe.read_bytes()
    pe = parse_pe_headers(orig)
    base = pe.image_base
    end = base + pe.size_of_image
    report: dict = {
        "exe": str(exe),
        "exe_size": len(orig),
        "mode": args.mode,
        "image_base": hex(base),
        "image_end": hex(end),
        "timing": {},
    }
    report["packed_sections"] = [
        {
            "name": s.name,
            "va": hex(base + s.rva),
            "vsize": hex(s.vsize),
            "raw_size": hex(s.rsize),
            "chars": hex(s.chars),
        }
        for s in pe.sections
    ]
    report["rich_header"] = decode_rich(orig[: pe.size_of_headers])

    # ---- static: stub analysis on the file bytes
    ep_va = base + pe.entry_rva
    ep_off = rva_to_off(pe, pe.entry_rva)
    stub = orig[ep_off : ep_off + 0x400] if ep_off is not None else b""
    tail = find_stub_tail_jmp(stub, ep_va) if stub else None
    upx = find_upx_import_loop(stub, ep_va) if stub else None
    oep = args.oep if args.oep is not None else (tail[1] if tail else None)
    report["packed_entry"] = hex(ep_va)
    report["stub_tail_jmp"] = hex(tail[0]) if tail else None
    report["oep"] = hex(oep) if oep is not None else None
    report["oep_method"] = (
        "--oep override"
        if args.oep is not None
        else "static: target of the stub's final `popad ... jmp rel32`"
        if tail
        else "unknown"
    )
    report["upx_import_loop"] = {k: hex(v) for k, v in upx.items()} if upx else None
    log(f"entry {ep_va:#x}, stub tail jmp {report['stub_tail_jmp']}, OEP {report['oep']}")
    if args.mode == "hold" and not tail:
        log("no stub tail found; falling back to delay mode")
        args.mode = "delay"

    # ---- launch
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0)
    except OSError:
        pass
    env = dict(os.environ, WINEPREFIX=str(Path(args.prefix).resolve()), WINEDEBUG="-all")
    if args.dll_overrides:
        env["WINEDLLOVERRIDES"] = args.dll_overrides
    subprocess.run(["wineserver", "-k"], env=env, stderr=subprocess.DEVNULL)
    wlog = open(out / "wine.log", "wb")
    t0 = time.monotonic()
    proc = subprocess.Popen(
        [args.wine, str(exe)],
        cwd=args.cwd or str(exe.parent),
        env=env,
        stdout=wlog,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
    )
    log(f"launched wine pid {proc.pid}")
    pid = None
    mem = None
    rc = 1
    try:
        while time.monotonic() - t0 < args.timeout:
            pid = find_target(os.getpid(), str(exe), base)
            if pid:
                break
            if proc.poll() is not None and not proc_children_tree(os.getpid()):
                raise RuntimeError("wine exited before the exe was mapped; see wine.log")
            time.sleep(0.002)
        if not pid:
            raise RuntimeError("timed out waiting for the exe to be mapped")
        report["timing"]["exe_mapped_s"] = round(time.monotonic() - t0, 3)
        log(f"target pid {pid} (exe mapped at {base:#x})")
        mem = ProcMem(pid)

        patched = None
        if args.mode == "hold":
            jva = tail[0]
            orig_bytes = mem.read(jva, 2)
            # Has the image already been unpacked (race lost)?
            pre = mem.read(oep, 16) if oep else b""
            mem.write(jva, b"\xeb\xfe")
            ok = mem.read(jva, 2) == b"\xeb\xfe"
            patched = (jva, orig_bytes)
            report["hold_patch"] = {
                "va": hex(jva),
                "original": orig_bytes.hex(),
                "applied": ok,
                "oep_bytes_before_patch_nonzero": any(pre),
            }
            report["timing"]["patched_s"] = round(time.monotonic() - t0, 3)
            log(f"patched {jva:#x} -> jmp $ (ok={ok}, oep already populated={any(pre)})")
            # wait: OEP populated, stable, and some thread spinning
            last = None
            stable = 0
            while time.monotonic() - t0 < args.timeout:
                time.sleep(0.25)
                cur = mem.read(oep, 64)
                ticks1 = thread_cpu_ticks(pid)
                time.sleep(0.25)
                ticks2 = thread_cpu_ticks(pid)
                spinning = any(ticks2.get(t, 0) - v >= 15 for t, v in ticks1.items())
                if any(cur) and cur == last and spinning:
                    stable += 1
                    if stable >= 2:
                        break
                else:
                    stable = 0
                last = cur
            else:
                raise RuntimeError("timed out waiting for the stub to reach the held jmp")
        else:
            time.sleep(args.delay)
        os.kill(pid, signal.SIGSTOP)
        report["timing"]["stopped_s"] = round(time.monotonic() - t0, 3)
        log("process stopped; dumping")

        maps = read_maps(pid)
        image, holes = mem.read_region(base, end, maps)
        image = bytearray(image)
        if patched:
            off = patched[0] - base
            image[off : off + 2] = patched[1]
        report["unreadable_ranges"] = [[hex(a), hex(b)] for a, b in holes]
        raw_path = out / f"{stem}_raw_{base:x}-{end:x}.bin"
        raw_path.write_bytes(bytes(image))
        log(f"raw dump {raw_path} ({len(image)} bytes, {len(holes)} holes)")

        mods = enumerate_modules(mem, maps)
        resolver = Resolver(mods)
        report["modules"] = [
            {
                "name": m.name,
                "base": hex(m.base),
                "size": hex(m.size),
                "exports": sum(len(v) for v in m.exports.values()),
                "forwarders": len(m.forwarders),
            }
            for m in sorted(mods, key=lambda m: m.base)
        ]
        log(f"{len(mods)} 32-bit modules mapped")

        # ---- imports
        if upx:
            blocks = parse_upx_import_blob(bytes(image), base, upx)
            source = "upx import blob (names) cross-checked with live IAT pointers"
        else:
            blocks = scan_iat(bytes(image), base, resolver, base + 0x1000, end)
            source = "generic IAT scan of live pointers"
        mismatches, unresolved = [], []
        for b in blocks:
            for i, e in enumerate(b["entries"]):
                va = b["iat_va"] + 4 * i
                live = struct.unpack_from("<I", image, va - base)[0]
                want = resolver.address_of(b["dll"], e.get("name"), e.get("ordinal"))
                hits = resolver.lookup(live)
                e["live"] = live
                if not hits and not want:
                    unresolved.append(
                        {
                            "slot": hex(va),
                            "dll": b["dll"],
                            "import": e.get("name") or e.get("ordinal"),
                            "live": hex(live),
                        }
                    )
                elif want and live not in want:
                    mismatches.append(
                        {
                            "slot": hex(va),
                            "dll": b["dll"],
                            "import": e.get("name") or e.get("ordinal"),
                            "live": hex(live),
                            "live_resolves_to": [f"{h[0]}!{h[1] or h[2]}" for h in hits],
                        }
                    )
        report["imports"] = {
            "source": source,
            "dll_blocks": len(blocks),
            "dlls": sorted({b["dll"].upper() for b in blocks}),
            "functions": sum(len(b["entries"]) for b in blocks),
            "by_dll": {b["dll"]: len(b["entries"]) for b in blocks},
            "iat_range": [
                hex(min(b["iat_va"] for b in blocks)),
                hex(max(b["iat_va"] + 4 * len(b["entries"]) for b in blocks)),
            ]
            if blocks
            else None,
            "unresolved_slots": unresolved,
            "mismatched_slots": mismatches,
        }
        log(
            f"imports: {report['imports']['functions']} functions from {len(blocks)} blocks "
            f"({len(unresolved)} unresolved, {len(mismatches)} mismatched)"
        )

        # ---- section layout of the rebuilt image
        page = pe.sect_align
        iat_lo = min(b["iat_va"] for b in blocks) & ~(page - 1) if blocks else None
        first = pe.sections[0]
        img_lo = base + first.rva
        # end of unpacked image = start of the UPX import blob (page aligned) when known
        img_hi = (upx["blob_va"] & ~(page - 1)) if upx else None
        stub_sec = next((s for s in pe.sections if s.rva <= pe.entry_rva < s.rva + s.vsize), None)
        rsrc_rva = pe.data_dirs[2][0] if len(pe.data_dirs) > 2 else 0
        layout = []
        if iat_lo and img_hi and img_lo < iat_lo < img_hi:
            layout.append((".text", img_lo, iat_lo, 0x60000020))
            layout.append((".data", iat_lo, img_hi, 0xC0000040))
            stub_lo = img_hi
        else:
            stub_lo = img_lo
        # remaining packed sections: keep extents, rename
        cur = stub_lo
        for s in pe.sections:
            s_lo, s_hi = base + s.rva, base + s.rva + align(s.vsize, page)
            if s_hi <= cur:
                continue
            lo = max(s_lo, cur)
            if stub_sec is s:
                name, ch = ".unpstub", 0xE0000060
            elif rsrc_rva and s.rva <= rsrc_rva < s.rva + s.vsize:
                name, ch = ".rsrc", 0xC0000040
            else:
                name, ch = ".unpdata", 0xC0000040
            layout.append((name, lo, s_hi, ch))
            cur = s_hi
        report["rebuilt_sections"] = [
            {"name": n, "va": hex(a), "end": hex(e), "chars": hex(c)} for n, a, e, c in layout
        ]
        rebuilt, info = rebuild_pe(orig, image, base, oep, layout, blocks)
        report["rebuilt"] = {k: (hex(v) if isinstance(v, int) else v) for k, v in info.items()}
        unp_path = out / f"{stem}_unpacked.exe"
        unp_path.write_bytes(rebuilt)
        report["outputs"] = {"raw": str(raw_path), "unpacked": str(unp_path)}
        log(f"rebuilt PE {unp_path} ({len(rebuilt)} bytes)")
        if oep:
            report["oep_bytes"] = bytes(image[oep - base : oep - base + 32]).hex()
        rc = 0
    except Exception as exc:  # noqa: BLE001 - report and clean up
        report["error"] = f"{type(exc).__name__}: {exc}"
        log(report["error"])
    finally:
        report["timing"]["total_s"] = round(time.monotonic() - t0, 3)
        if mem:
            mem.close()
        for p in proc_children_tree(os.getpid()) + ([pid] if pid else []):
            try:
                os.kill(p, signal.SIGKILL)
            except ProcessLookupError:
                pass
        subprocess.run(["wineserver", "-k"], env=env, stderr=subprocess.DEVNULL)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        # reap any orphans adopted via subreaper
        while True:
            try:
                if os.waitpid(-1, os.WNOHANG) == (0, 0):
                    break
            except ChildProcessError:
                break
        wlog.close()
        (out / f"{stem}_dump_report.json").write_text(json.dumps(report, indent=2))
        log(f"report written; exit {rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
