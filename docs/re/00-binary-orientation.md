# 00 — Binary orientation: `Rugby08.exe`

Status: Phase 1, first pass. Each claim is tagged **observed** (checked
directly against the file, process memory or Ghidra output), **inferred**
(reasoned from observed facts) or **unknown**. This file contains no code or
binary content from the game. Raw dumps live only under the git-ignored
`.omc/research/unpacked/`.

## 1. Shipped file

| Item | Value | Tag |
|---|---|---|
| File | `Rugby08.exe`, 6,278,656 bytes, sha256 `f9844377…2a5297960304` | observed |
| Format | PE32, i386, GUI, image base `0x400000`, SizeOfImage `0x1063000` | observed |
| PE timestamp | `0x562B029A` (2015-10-24), so this is the repacker's build date, not EA's | observed / inferred |
| Optional-header linker version | 7.10 | observed |
| Packed sections | `.ROT` VA `0x401000` vsize `0xA64000`, raw 0 · `.IN` VA `0xE65000` vsize `0x5F2000` raw `0x5F1200` · `.HEAVEN` VA `0x1457000` vsize `0xC000` (resources + stub import table) | observed |
| Packed entry | `0x1455FB0`, in `.IN` (not `.HEAVEN`) | observed |

### Packer identification

- **Observed:** the entry stub is the classic UPX win32/pe loader: `pushad`,
  an NRV2B bit-stream decompressor (source `0xE65000`, destination
  `0x401000`), the E8/E9 "call-trick" filter with marker byte `0x9E`, the UPX
  import loop (`LoadLibraryA` / `GetProcAddress` driven by a packed name blob),
  a `VirtualProtect` pass that clears the write bit on two section headers,
  `popad`, a stack-clearing loop, and a final `jmp` to the original entry
  point.
- **Inferred:** this is UPX (or a light UPX fork) with the section names and
  magic replaced by the ViTALiTY release group (`.ROT` = UPX0, `.IN` = UPX1,
  `.HEAVEN` = rsrc/stub data; strings `+V!TAL!TY+` and "cannot be run in GOD
  mode"). Stock `upx -d` is not expected to work because the UPX headers and
  magic are gone. It was not tried.
- **Observed:** the unpacked image still contains a **SecuROM 7.33** wrapper
  (PDB path `…\SecuROM_DRM\Wrapper\wrapper.pdb`, about 40 `SecuROM` /
  `.securom` / `paul.dll` strings in `0x1066000–0x12F0000`). **Inferred:** the
  release group dumped a SecuROM-wrapped retail build and repacked it. They did
  not strip the wrapper. Game code does not depend on it for our purposes.
- **Observed:** original game PDB path
  `e:\perforce\depot\Rugby08\branches\Milestone\exe\rugby_DVD_Win32.pdb`.
  The developer namespace in the RTTI is `Hbs` (HB Studios).

## 2. Dump method

Tool: `tools/re/dump_wine_process.py` (stdlib Python, documented in its
docstring). The method that succeeded was **"hold at OEP" under Wine**:

1. Static scan of the stub for `popad … jmp rel32` gives the stub-tail jump
   at `0x145614D` and its target **OEP `0x87555C`** (observed).
2. The script starts `wine Rugby08.exe` as its own child, with a fresh prefix
   (`.omc/research/wineprefix`, wine-11.19, new WoW64). The script is a child
   subreaper, so `/proc/PID/mem` access works under `ptrace_scope=1`. As soon
   as the exe is mapped at `0x400000` (about 1.5 s), the stub-tail `jmp` is
   overwritten **in process memory only** with `jmp $`. The file on disk is
   never written.
3. Once the code at the OEP is present and stable and a thread is spinning,
   the process is SIGSTOPped. The image range `0x400000–0x1463000` is read
   (17,182,720 bytes, no unreadable holes) and the two patched bytes are
   restored in the dump. No game code ran, so `.data` is in its as-loaded state.
   The whole run takes about 3 s, and no game window appears.
4. The IAT names come from the packer's own import blob at `0x1453000`. Every
   slot was cross-checked against the live pointer by parsing the export
   tables (including forwarders) of all 30 mapped 32-bit modules. Result:
   226/226 resolved, 0 unresolved, 0 mismatched (observed).
5. The script rebuilds a PE with raw size == virtual size and a new `.idata`
   (unbound import directory whose `FirstThunk`s point at the original IAT).
   It sets the entry point to the OEP and the relocs-stripped flag.

OEP cross-check (observed): the bytes at `0x87555C` are the Visual C++ 7.1
`WinMainCRTStartup` prologue (`push 60h; push <SEH scope table>; call
__SEH_prolog; mov edi, 94h; …; call __alloca_probe; …`) followed by the
`GetVersionExA` call pattern.

## 3. Compiler and toolchain (from the Rich header)

The Rich header survived the repack. Its tool IDs agree with linker version
7.10 (observed values, inferred tool names):

| Tool (inferred) | Build | Objects |
|---|---|---|
| C++ compiler, VC++ 7.1 (VS .NET 2003) | 13.10.3077 | 957 |
| C compiler, VC++ 7.1 | 13.10.3077 | 224 |
| MASM 7.10 | 3077 | 89 |
| Linker 7.10 | 3077 | 1 |
| CvtRes 7.10 | 3052 | 1 |
| Import-lib entries (VS2003 / SDK implibs) | 2067, 2179 | 10 |
| VC++ 6.0-era tools (prebuilt middleware/static libs) | 8444–9466 | ~160 |
| Imported functions (`Import0`) | — | 237 |

**Inferred:** the game is a Visual Studio .NET 2003 C++ build with static CRT
(`__SEH_prolog` / `__alloca_probe` in the CRT start-up path, and the default
`/GS` cookie constant `0xBB40E64E` appears in `.text`). Some middleware was built with
VC6. The Rich header counts 237 imports against 226 recovered from the IAT;
the gap is **unknown** (likely duplicate or unused import-library entries).

## 4. Layout of the unpacked image

Rebuilt sections (observed: our own layout). The original section table is
lost because UPX merged everything into one span.

| Rebuilt section | VA range | Basis |
|---|---|---|
| `.text` (RX) | `0x401000–0x8CC000` | start of image up to the IAT. MSVC puts the IAT first in `.rdata`, so this is the original `.text` end (inferred) |
| `.data` (RW) | `0x8CC000–0x1453000` | original `.rdata`, `.data`, a ~980 KB zero (bss-like) run at `0x9B7000–0xAAC000`, then a large block `0xAB9000–0x1000000` (uniform ~31 % printable bytes, purpose **unknown**) and SecuROM wrapper code/data `0x1000000–0x1453000` (inferred from density/strings) |
| `.unpstub` (RWX) | `0x1453000–0x1457000` | UPX import blob and loader stub |
| `.rsrc` (RW) | `0x1457000–0x1463000` | resources and packer import table (resource directory kept at RVA `0x1057000`) |
| `.idata` (RW) | `0x1463000–0x1465000` | rebuilt import directory |

IAT: `0x8CC000–0x8CC3A8`, 9 descriptor blocks.

## 5. Imports (observed, 226 functions)

| DLL | Functions |
|---|---|
| KERNEL32.DLL | 136 |
| USER32.dll | 56 |
| GDI32.dll | 17 |
| WINMM.dll | 7 |
| ADVAPI32.dll | 5 |
| DSOUND.dll | 2 |
| d3d8.dll | 1 (`Direct3DCreate8`) |
| DDRAW.dll | 1 |
| DINPUT.dll | 1 |

**Inferred:** the renderer is **Direct3D 8** (it also has D3D8 error strings
such as `IDirect3DDevice8_GetDeviceCaps failed`), input is DirectInput,
and audio is DirectSound plus winmm. Everything else (COM interfaces) is
reached through the vtables returned by the create functions. There is no
network DLL in the static imports; the networking strings suggest it is
loaded dynamically or not used (**unknown**).

## 6. Analysis counts (Ghidra 12.1.4 via REA)

Observed. Source: the `rea analyze` CLI (rea-agents 6.4.0, Ghidra 12.1.4,
default analyzers) on `Rugby08_unpacked.exe`, sha256 `08de3dde…6e6023be100f5b8d`:

| Metric | Packed exe | Unpacked exe |
|---|---|---|
| Procedures | 11 (entry stub + 10 imports) | **26,896** |
| Defined strings (Ghidra) | 37 | **15,745** |
| Segments | 3 sections | Headers, `.text` (5,025,792 B), `.data` (12,087,296 B), `.unpstub`, `.rsrc`, `.idata`, plus Ghidra's synthetic `tdb` |

Ghidra's full auto-analysis of the unpacked image takes about 7.5 min of wall-clock
time and about 1.6 GB RSS. That is longer than the REA MCP server's default
330 s provider deadline (`REA_GHIDRA_STARTUP_TIMEOUT_MS`), so a fresh
`open_binary` + `binary_overview` through MCP timed out three times in this
session. The counts above come from the CLI run with a raised deadline.
Game-vocabulary presence (scrum, lineout, knock-on, `.big`, `data.gob`, …;
see §7) was checked by a byte-level string scan of the same file. A Ghidra
string search for it was started and then stopped to save memory.

## 7. Notable string clusters (names/categories only)

From a printable-ASCII scan of the unpacked image (about 30,100 strings of 5 or more
characters, plus about 360 UTF-16 strings):

- **C++ RTTI:** about 804 MSVC type descriptors in namespaces `Hbs::Rugby`,
  `Hbs::Common`, `Hbs::Async`, `Hbs::IO`, … (state machines, backend modes,
  stadium/pitch renderers, loadables). This is a strong class-recovery
  foothold.
- **EA graphics library:** about 140 `EAGL::…` symbols (view/projection matrices,
  render state).
- **Match vocabulary:** scrum (about 160), lineout (about 86), ruck (about 180 incl.
  camera names), maul (about 70), penalty (about 50), conversion, drop goal, knock-on,
  referee. Includes a command table of the form `scrum drive $SCRUM_DRIVE …
  maul collapse $MAUL_COLLAPSE … kick grubber $KICK_GRUBBER`.
- **Game events:** about 350 `GEVENT_*` identifiers (for example a player joining a maul).
- **Commentary / referee audio cues:** `Ref_*`, `knock_on_TeamA_01`,
  `conversion_success_01`, `Penalty_kick_chosen_01`, `haka%03d.asf`, `pbp.evt`.
- **UI:** about 100 `GameFace*` identifiers (front-end / menu framework).
- **Cameras:** `Lineout Hand Cam`, `Lineout Broadcast`, `Zoom Truck`, …
- **Asset paths:** `data/data.gob`, `audio/*.big` (aems, chants, anthems, …),
  `replays/replays.big`, `data/motion/moai.viv`, `*.fsh` textures, `*.o`
  models (`misc/models/*.o`), `*.xml` (about 40), `*.rsg`, `*.ffn` fonts,
  `data/controltypes.csv`. Big-file error messages are present.
- **Source file names:** `.\src\CommonGame.cpp`, `.\src\drill\*.cpp`
  (training drills), `.\src\rep\replaymanager.cpp`,
  `highlightmanager.cpp`, `strm.cpp` (audio streaming), with assert line
  numbers.
- **Not found as literals:** "Tri Nations", "World League", "Six Nations",
  "World Cup". **Inferred:** competition and team names live in the data
  files, not the exe.

## 8. Known limitations of the dump

- **Relocations:** none. UPX stripped them, and the image is marked
  relocs-stripped and must load at `0x400000`. This does not matter for static
  analysis.
- **Section boundaries:** the original section table is unknown; see §4.
  The SecuROM tail (`0x1000000–0x1453000`) is inside an RW non-exec rebuilt
  section, so Ghidra only disassembles there if it follows references.
- **TLS / load config / debug directory:** the packed header has none and the
  rebuilt header adds none. The debug directory's CodeView record is still
  in the image as data.
- **Imports:** complete for the static IAT. Imports resolved at runtime
  (`GetProcAddress` by the game or the SecuROM wrapper) are not in the
  import table.
- **Resources:** kept as the packer left them. Leaves that UPX compressed
  are not individually verified.
- **The rebuilt exe is for analysis only.** It was not test-run.
- **Not verified independently:** the dump was not compared against a
  static NRV2B decompression of `.IN`. The hold-at-OEP method makes this low
  risk, and the IAT cross-check and CRT prologue are consistent.

## 9. Reproduce

```
python3 tools/re/dump_wine_process.py \
  --exe <game dir>/Rugby08.exe \
  --prefix .omc/research/wineprefix \
  --out-dir .omc/research/unpacked --stem Rugby08
```

Outputs: `Rugby08_unpacked.exe`, `Rugby08_raw_400000-1463000.bin`,
`Rugby08_dump_report.json`, `wine.log` (all git-ignored).

## 10. SecuROM trampolines and the repair

**Observed:** `.text` contains about 2,300 six-byte `jmp dword ptr [imm32]`
(`FF 25`) instructions whose pointer lies in the SecuROM data block
(`0x1000000-0x1453000`). The pointed-at dword holds a stub address. Ghidra and
other analysers cannot follow the indirect jump, so the surrounding code decompiles
with holes or dead ends. Two distinct mechanisms share this encoding:

| Kind | Count | What the stub holds |
|---|---|---|
| Stolen instructions (mid-function) | 246 | 1 relocated instruction, then a direct `jmp` back to trampoline + 6 |
| Function-entry redirect | about 2,070 | the whole relocated function body, with an obfuscated prologue and no jmp-back |
| Obfuscated reads (too long to inline) | 7 | 2-5 relocated instructions (more than 6 bytes) |

**Repair:** `tools/re/inline_securom.py` does two things, all at fixed addresses
(same size and layout as the input).

1. *Inline.* Where the stub's jmp-back equals trampoline + 6 and the code fits in 6
   bytes, the stolen instruction is written back (relative call/jmp/jcc are
   re-encoded for the new address) and padded with `0x90`. 246 sites.
2. *Redirect* (`--redirect`, default on). Every other trampoline whose stub pointer
   is a code address (2,076 sites: the function-entry redirects, the mismatched
   jmp-back cases and the 7 obfuscated reads) becomes `E9 rel32` to the stub plus one
   `NOP`, so analysers follow it into the relocated body. The stub range
   (VA `0x1057000-0x1452000`, measured from the lowest and highest stub) is split out
   of `.data` into its own `.secu` section (code, execute, read), with `.data` before
   and `.data2` after it. Raw and virtual offsets are unchanged, `SizeOfCode` and
   `SizeOfInitializedData` are adjusted, and the file size is the same.

Three matches (`0x43fbb4`, `0x896508`, `0x896ace`) were left alone: disassembling their
functions linearly shows they fall inside a `mov eax,[ebp-disp]` displacement, so they
are not instructions. Redirected stubs end in `ret` or a `jmp` back into `.text`; a few
jump back to trampoline + 7, which is why the stub is not simply inlined.

**Obfuscated prologues (inferred, not removed):** many relocated bodies start with
`push ebp; dec dword ptr [counter]; je <label in the SecuROM block>; mov ebp,esp ...`,
where `counter` is a dword in the SecuROM data. This looks like a per-function call
countdown: the Nth call takes the branch into SecuROM code, presumably a protection
or integrity trigger check. On the normal path it is a no-op for game logic, so
decompiler output can ignore the `dec`/`je` pair. Some prologues instead load `ebp`
from a SecuROM address and subtract a constant before the `dec`. They are left as
found.

```
python3 tools/re/inline_securom.py --in .omc/research/unpacked/Rugby08_unpacked.exe \
  --out .omc/research/unpacked/Rugby08_fixed.exe \
  --report .omc/research/unpacked/securom_fix_report.json
```

Requires `capstone`. Outputs are git-ignored. The repaired exe is for analysis only
and was not test-run.
