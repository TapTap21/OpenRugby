#!/usr/bin/env python3
"""Inline SecuROM "stolen instruction" trampolines back into game code.

Purpose
-------
The SecuROM wrapper removed 1-2 instructions from many game functions and put
a 6-byte ``jmp dword ptr [imm32]`` (``FF 25 imm32``) in their place. The
``imm32`` points at a dword in the SecuROM data block (``0x1000000-0x1453000``);
that dword holds the address of a stub (in int3 padding) containing the
relocated original instruction(s) followed by a direct ``jmp rel32``/``rel8``
back to the byte after the trampoline. Static analysers cannot follow the
indirect jump, so functions decompile with missing code.

Most trampolines are different: the stub is a whole relocated function body with an
obfuscated prologue. Those are rewritten as ``E9 rel32`` direct jumps to the stub (plus a
NOP) and the stub block becomes an executable ``.secu`` section so Ghidra follows them.

This tool scans ``.text``, resolves each trampoline, and when the stolen
instructions fit in 6 bytes writes them back in place (relative branches are
re-encoded for the new address) and pads with NOPs. Everything else is left
untouched and reported. The output image has the same size and layout as the
input.

Requires ``capstone`` (``pip install capstone``). Stdlib otherwise.

Usage
-----
    python3 tools/re/inline_securom.py --in Rugby08_unpacked.exe \
        --out Rugby08_fixed.exe --report securom_fix_report.json
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

from capstone import CS_ARCH_X86, CS_MODE_32, Cs
from capstone.x86_const import X86_GRP_BRANCH_RELATIVE, X86_GRP_CALL, X86_GRP_JUMP

IMAGE_BASE = 0x400000
TEXT_START = 0x401000
TEXT_END = 0x8CC000
SECUROM_START = 0x1000000
SECUROM_END = 0x1453000
TRAMPOLINE_LEN = 6
MAX_STUB_BYTES = 48

REDIRECT_START = 0x1057000  # measured: lowest stub in the SecuROM block is 0x10577db
REDIRECT_END = 0x1452000  # measured: highest stub starts at 0x1451003
SECU_NAME = b".secu"
SCN_CODE_EXEC_READ = 0x60000020  # CNT_CODE | MEM_EXECUTE | MEM_READ

OK = "OK"
REDIRECT = "REDIRECT"
TOO_LONG = "TOO_LONG"
BAD = "BAD"


@dataclass
class Result:
    """Classification of one trampoline."""

    addr: int
    status: str
    reason: str = ""
    stub: int = 0
    old: bytes = b""
    new: bytes = b""
    asm: list[str] = field(default_factory=list)


def _off(va: int) -> int:
    """File offset of a VA (the dump maps file offset == VA - image base)."""
    return va - IMAGE_BASE


def find_trampolines(data: bytes) -> list[int]:
    """Return VAs of every ``FF 25 imm32`` in .text whose imm32 is in the SecuROM block."""
    out: list[int] = []
    lo, hi = _off(TEXT_START), _off(TEXT_END) - TRAMPOLINE_LEN + 1
    pos = lo
    while True:
        pos = data.find(b"\xff\x25", pos, hi + 1)
        if pos < 0:
            break
        (imm,) = struct.unpack_from("<I", data, pos + 2)
        if SECUROM_START <= imm < SECUROM_END:
            out.append(pos + IMAGE_BASE)
        pos += 1
    return out


def _encode_branch(insn, new_addr: int) -> bytes | None:
    """Re-encode a relative call/jmp/jcc at ``new_addr``; None if it cannot be done."""
    target = insn.operands[0].imm
    op = bytes(insn.bytes)
    if op[0] == 0xE8 or op[0] == 0xE9:
        return bytes([op[0]]) + struct.pack("<i", target - (new_addr + 5))
    if op[0] == 0x0F and 0x80 <= op[1] <= 0x8F:
        return bytes([0x0F, op[1]]) + struct.pack("<i", target - (new_addr + 6))
    if 0x70 <= op[0] <= 0x7F or op[0] in (0xE3, 0xEB, 0xE0, 0xE1, 0xE2):
        rel = target - (new_addr + 2)
        if -128 <= rel <= 127:
            return bytes([op[0], rel & 0xFF])
        if op[0] == 0xEB:
            return b"\xe9" + struct.pack("<i", target - (new_addr + 5))
        if 0x70 <= op[0] <= 0x7F:
            return bytes([0x0F, 0x80 + (op[0] - 0x70)]) + struct.pack("<i", target - (new_addr + 6))
    return None


def classify(data: bytes, addr: int, md: Cs) -> Result:
    """Resolve and classify one trampoline at ``addr``."""
    old = data[_off(addr) : _off(addr) + TRAMPOLINE_LEN]
    (ptr,) = struct.unpack_from("<I", old, 2)
    res = Result(addr, BAD, old=old)
    if _off(ptr) + 4 > len(data):
        res.reason = "pointer outside image"
        return res
    (stub,) = struct.unpack_from("<I", data, _off(ptr))
    res.stub = stub
    if not (IMAGE_BASE < stub < IMAGE_BASE + len(data) - MAX_STUB_BYTES):
        res.reason = "stub address outside image"
        return res
    code = data[_off(stub) : _off(stub) + MAX_STUB_BYTES]
    stolen: list = []
    back = None
    for insn in md.disasm(code, stub):
        if insn.bytes[0] in (0xE9, 0xEB) and len(insn.operands) == 1:
            back = insn.operands[0].imm
            break
        if insn.mnemonic in ("int3", "ret", "retn", "int", "ud2", "hlt"):
            break
        stolen.append(insn)
        if len(stolen) > 6:
            break
    if back is None:
        res.reason = "no jmp-back: stub is a relocated function body (function-entry redirect)"
        return res
    if back != addr + TRAMPOLINE_LEN:
        res.reason = (
            f"jmp-back {back:#x} != trampoline+6 {addr + TRAMPOLINE_LEN:#x} "
            "(relocated function body or false match)"
        )
        return res
    if not stolen:
        res.reason = "stub has no stolen instructions"
        return res
    res.asm = [f"{i.mnemonic} {i.op_str}".strip() for i in stolen]
    total = sum(i.size for i in stolen)
    if total > TRAMPOLINE_LEN:
        res.status, res.reason = TOO_LONG, f"stolen code is {total} bytes (> 6)"
        return res
    new = b""
    cur = addr
    for insn in stolen:
        if X86_GRP_BRANCH_RELATIVE in insn.groups or (
            {X86_GRP_CALL, X86_GRP_JUMP} & set(insn.groups) and insn.bytes[0] in (0xE8, 0xE9)
        ):
            enc = _encode_branch(insn, cur)
            if enc is None:
                res.reason = f"cannot re-encode relative branch '{insn.mnemonic} {insn.op_str}'"
                return res
        else:
            enc = bytes(insn.bytes)
        new += enc
        cur += len(enc)
    if len(new) > TRAMPOLINE_LEN:
        res.status, res.reason = TOO_LONG, f"re-encoded code is {len(new)} bytes (> 6)"
        return res
    res.status = OK
    res.new = new + b"\x90" * (TRAMPOLINE_LEN - len(new))
    return res


def _stub_in_code(stub: int) -> bool:
    """True if ``stub`` lies in .text or the measured SecuROM stub range."""
    return TEXT_START <= stub < TEXT_END or REDIRECT_START <= stub < REDIRECT_END


def split_secu_section(img: bytearray) -> dict:
    """Split the section holding the stubs into ``.data`` / ``.secu`` / ``.data2``.

    ``.secu`` covers VA REDIRECT_START..REDIRECT_END and is code+execute+read so analysers
    treat the relocated function bodies as code. Raw and virtual layout are unchanged
    (raw pointer == RVA in the dump), so the file size does not change. Needs two spare
    section-header slots, which the dump's 4 KiB header area has.
    """
    pe = struct.unpack_from("<I", img, 0x3C)[0]
    nsec = struct.unpack_from("<H", img, pe + 6)[0]
    opt_size = struct.unpack_from("<H", img, pe + 20)[0]
    opt = pe + 24
    table = opt + opt_size
    hdr_size = struct.unpack_from("<I", img, opt + 60)[0]
    if table + 40 * (nsec + 2) > hdr_size:
        raise ValueError("no room for two more section headers")
    secs = [bytes(img[table + 40 * i : table + 40 * (i + 1)]) for i in range(nsec)]
    lo, hi = REDIRECT_START - IMAGE_BASE, REDIRECT_END - IMAGE_BASE
    new: list[bytes] = []
    done = False
    for raw in secs:
        vsize, rva, rsize, rptr = struct.unpack_from("<4I", raw, 8)
        if not done and rva <= lo and hi <= rva + vsize and rptr == rva and rsize == vsize:
            chars = struct.unpack_from("<I", raw, 36)[0]
            parts = [
                (raw[:8], rva, lo - rva, chars),
                (SECU_NAME.ljust(8, b"\0"), lo, hi - lo, SCN_CODE_EXEC_READ),
                (b".data2".ljust(8, b"\0"), hi, rva + vsize - hi, chars),
            ]
            for name, r0, size, ch in parts:
                if size == 0:
                    continue
                ent = bytearray(raw)
                ent[0:8] = name
                struct.pack_into("<4I", ent, 8, size, r0, size, r0)
                struct.pack_into("<I", ent, 36, ch)
                new.append(bytes(ent))
            done = True
        else:
            new.append(raw)
    if not done:
        raise ValueError("no section contains the SecuROM stub range")
    for i, ent in enumerate(new):
        img[table + 40 * i : table + 40 * (i + 1)] = ent
    struct.pack_into("<H", img, pe + 6, len(new))
    code = struct.unpack_from("<I", img, opt + 4)[0] + (hi - lo)
    idata = struct.unpack_from("<I", img, opt + 8)[0] - (hi - lo)
    struct.pack_into("<I", img, opt + 4, code)
    struct.pack_into("<I", img, opt + 8, idata)
    return {"sections": len(new), "secu_rva": f"{lo:#x}", "secu_size": f"{hi - lo:#x}"}


def repair(data: bytes, redirect: bool = True) -> tuple[bytearray, list[Result], dict | None]:
    """Return the patched image, per-trampoline results and section-split info.

    Inlinable trampolines are inlined. With ``redirect`` every other trampoline whose stub
    pointer is a plausible code address becomes ``jmp rel32 <stub>`` plus one NOP so
    analysers follow it into the relocated body, and the stub section is made executable.
    """
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    md.detail = True
    out = bytearray(data)
    results = [classify(data, a, md) for a in find_trampolines(data)]
    for r in results:
        if r.status == OK:
            out[_off(r.addr) : _off(r.addr) + TRAMPOLINE_LEN] = r.new
        elif redirect and _stub_in_code(r.stub):
            r.reason = f"{r.status}: {r.reason}"
            r.status = REDIRECT
            r.new = b"\xe9" + struct.pack("<i", r.stub - (r.addr + 5)) + b"\x90"
            out[_off(r.addr) : _off(r.addr) + TRAMPOLINE_LEN] = r.new
    info = split_secu_section(out) if redirect else None
    return out, results, info


def build_report(results: list[Result], info: dict | None = None) -> dict:
    """JSON-serialisable report."""
    counts = {s: sum(1 for r in results if r.status == s) for s in (OK, REDIRECT, TOO_LONG, BAD)}
    return {
        "total": len(results),
        "counts": counts,
        "section_split": info,
        "redirected": [
            {"addr": f"{r.addr:#x}", "stub": f"{r.stub:#x}", "new": r.new.hex(), "was": r.reason}
            for r in results
            if r.status == REDIRECT
        ],
        "patched": [
            {
                "addr": f"{r.addr:#x}",
                "stub": f"{r.stub:#x}",
                "old": r.old.hex(),
                "new": r.new.hex(),
                "asm": r.asm,
            }
            for r in results
            if r.status == OK
        ],
        "skipped": [
            {
                "addr": f"{r.addr:#x}",
                "class": r.status,
                "reason": r.reason,
                "stub": f"{r.stub:#x}",
                "asm": r.asm,
            }
            for r in results
            if r.status not in (OK, REDIRECT)
        ],
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--in", dest="inp", required=True, type=Path, help="unpacked exe")
    ap.add_argument("--out", required=True, type=Path, help="repaired exe to write")
    ap.add_argument("--report", required=True, type=Path, help="JSON report to write")
    ap.add_argument(
        "--redirect",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="rewrite non-inlinable trampolines as direct jmp to the stub and make the "
        "stub block an executable .secu section (default on)",
    )
    args = ap.parse_args(argv)
    data = args.inp.read_bytes()
    out, results, info = repair(data, args.redirect)
    args.out.write_bytes(bytes(out))
    rep = build_report(results, info)
    args.report.write_text(json.dumps(rep, indent=1) + "\n")
    print(json.dumps(rep["counts"]), f"total={rep['total']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
