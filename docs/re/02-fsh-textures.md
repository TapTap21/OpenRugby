# 02 - SHPI / FSH textures

Decoder: `tools/openrugby_tools/fsh.py` (`python -m openrugby_tools.fsh {census,convert}`).
Requires Pillow (`pip install '.[tools]'`) for DXT decoding via its DDS plugin and for PNG output.
Input is every member whose decoded payload starts with `SHPI` (RefPack `.unpacked` sibling
preferred). No game image data is reproduced here.

## Corpus

5124 SHPI files, 16984 bitmaps: 4074 in `data.gob` (all had a `.unpacked` sibling), 1050 in
`data.gob.nested`; none in `script.big.nested` or `moai.viv`. 1403 files hold more than one
bitmap. Sizes up to 1024 px; 339 bitmaps are not power-of-two. Every file's declared size
equals its payload length. Full conversion: 0 failures, ~22 s with 8 processes.

## Container (matches public docs)

`SHPI`, u32 total size, u32 entry count, 4-char directory id, then `{tag[4], u32 offset}` per entry.
Directory ids seen: `G359` (5123 files), `G354` (1 file). Eight bytes of ASCII filler
(`Buy ERTS`) sit between the directory and the first entry. Each bitmap has a 16-byte header:
`u32 (format | attachment_offset << 8)`, u16 width, u16 height, u16 x/y centre, u16 x_pos,
u16 y_pos. Pixel data follows; the attachment offset is relative to the entry start.

## Format codes observed

| Code | Count | Meaning | Notes |
|------|-------|---------|-------|
| 0x60 | 9556 | DXT1 (BC1) | 8 bytes per 4x4 block |
| 0x62 | 7131 | DXT5 (BC3) | 16 bytes per block; interpolated alpha confirmed visually (0x62, not DXT3) |
| 0x7D | 291 | ARGB8888 | stored B,G,R,A byte order |
| 0x7F | 6 | RGB888 | stored B,G,R byte order |

Not present in this game (decoder rejects them with `FshError`): 0x61, 0x78, 0x7B, 0x7E, 0x6D,
0x79, 0x7A, and all palette attachments (0x2A/0x2D/0x24/0x22/0x23).

## Mipmaps (deviation from public docs)

The mip count is the top nibble of the `y_pos` header field (x_pos nibble is always 0), and it
counts levels in addition to level 0 (total levels = n + 1). Mip chains are stored largest to
smallest, packed back to back, with the chain end padded (0 to 16 bytes) before the first
attachment. Observed counts: 0x60: 0 (9250), 5 (11), 6 (110), 7 (85), 8 (59), 9 (41);
0x7D: 0 (276), 6 (3), 7 (7), 8 (5); 0x62 and 0x7F never carry mips. Level 0 of non-mipped DXT
data is also followed by up to 16 bytes of zero padding before attachments. The decoder
verifies the chain size against the attachment offset (all 16984 bitmaps are consistent).

## Attachments seen

Attachments are a chain of `u32 (code | next_relative_offset << 8)` blocks; next = 0 ends the chain.

| Code | Count | Content |
|------|-------|---------|
| 0x69 | 16536 | "metal bin" marker: 76-byte block, fixed ASCII text about runtime texture management |
| 0x70 | 16984 | Name: NUL-terminated string (12 bytes, 28 in 9 cases). Every bitmap has one |
| 0x6F | 5586 | Comment: u32 field then text such as `TXLY,<id>,...` layout hints; 12/28/44-byte forms |
| 0x7C | 4950 | Not in public docs. 4-byte count followed by 4-byte-reversed ASCII labels and u32 rectangles (looks like sprite/slice regions for UI atlases). Not decoded |

Chains seen: 0x69+0x70 (10906), 0x69+0x7C+0x70+0x6F (4906), 0x69+0x70+0x6F (680), 0x70 only
(448), 0x69+0x7C+0x70 (44).

## Naming

The directory tag is only 4 characters, space padded, so it truncates and collides (233 files
repeat a tag). The 0x70 name attachment is the full name (2318 differ from the tag); the
converter uses it, sanitises to `[A-Za-z0-9_.-]`, and suffixes `_2`, `_3`... on case-insensitive
clashes. Output: `extracted/textures/<source-relative-path>/<name>.png` and `index.json`
(source, directory id, per-bitmap tag, name, format, size, mips, centre, attachments, files, error).
`--mips` additionally writes `<name>_mipN.png`.

## Unknowns

- Meaning of 0x7C regions, and of the u32 prefix in 0x6F/0x7C blocks.
- x_centre / y_centre and the low 12 bits of x_pos / y_pos are carried in the index but unused.
- Whether alpha in 0x7D is premultiplied (treated as straight alpha).
- DXT1 1-bit transparency is decoded as alpha 0 (Pillow behaviour).
