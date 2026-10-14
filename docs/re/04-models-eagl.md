# 04 - Models: EAGL objects (Rugby 08 PC)

Status: geometry, materials-by-name, skinning and skeletons are decoded and converted to glTF 2.0.
The converter is `tools/openrugby_tools/eagl.py`
(`python -m openrugby_tools.eagl {census,dump,gltf,preview}`). The corpus census is in
`.omc/research/models/census.json` (gitignored).

All offsets below are byte offsets into the `.data` section of one object, unless they say
otherwise. "Observed" means read directly from shipped files. "Inferred" means a reading that
fits all the data but has no runtime or code confirmation. Every structure was checked across the
whole corpus (1,400 objects), not only on the examples named here.

## 1. Corpus and container

| Item | Value | Confidence |
|---|---|---|
| Object count | 1,400 ELF members: 123 in `data.gob` (RefPack-packed; use the `.unpacked` files) and 1,277 inside nested `.big` archives under `data.gob.nested/`. None under `script.big.nested/`. | observed |
| ELF header | ELF32, little-endian, `ET_REL`, `e_machine` 8 (MIPS), `e_flags` `0x20924000` (mips3, eabi64). No code sections. | observed |
| Sections | `.data`, `.rel.data`, `.symtab`, `.strtab`, `.shstrtab` in 1,398 objects. One object stores them in a different order. One object has no `.rel.data`. | observed |
| Relocations | 321,074 entries, all `R_MIPS_32` (type 2) in `.rel.data`. | observed |
| Relocation rule | value = S + A. A is the 32-bit word stored at the patched location. If the symbol is the `.data` section symbol, the target is the internal offset A, because `.data` sits at base 0. If the symbol is undefined, the runtime resolves it by name (see section 2). | observed: every internal pointer leads to a plausible structure |
| Toolchain tag | weak symbol `__EAGL_TOOLLIB_VERSION:::EAGL_TOOLLIB_VERSION-4` in every object | observed |

The MIPS machine type is left over from EA's PS2-era EAGL asset pipeline. On PC, the payload is
Direct3D data: FVF codes, D3DCOLOR and D3D8 vertex shaders (section 6).

## 2. Symbol grammar

Defined symbols name structures. Undefined symbols are runtime bindings that the engine resolves
by name. Counts are corpus totals after instance-specific parts are stripped. The full table is
`symbol_patterns` in the census.

| Pattern | Kind | Count | Meaning |
|---|---|---|---|
| `__Model:::<name>` | defined | 1,397 | Model root (section 3) |
| `__Model:::<name>.variationN` | defined | 212 | Texture-variant copies of a Model |
| `__BBOX:::<name>` | defined | 1,397 | 6-float box: min xyz, then max xyz |
| `__RenderMethod:::__GPRenderMethod_<name>_<i>` | defined | 9,991 | One drawable chunk (section 4) |
| `__geoprimdatabuffer_<i>_<uid>_<name>` | defined | 9,991 | Header word placed before the command stream of RenderMethod i |
| `__Skeleton:::<name>` / `__Bone:::<name>.<bone>` | defined | 31 skeletons | Section 8 |
| `__AnimationBank:::<name>` | defined | 2 | Animation data (`!eagl`, flag). Not decoded. |
| `__EAGL::TAR:::RUNTIME_ALLOC::UID=n;SHAPENAME=<shape>,<k>;PCEXTOBJ_SetClampU=..;PCEXTOBJ_SetClampV=..` | undefined | 7,381 | Texture handle. `<shape>` is the 4-character FSH shape name; clamp modes are `PCCM_WRAP`/`PCCM_CLAMP`. Some carry `SetTextureFunction=EAGL::TF_DECAL`. |
| `__EAGL::GeoPrimState:::RUNTIME_ALLOC::UID=n;...;SetPrimitiveType=EAGL::PT_<type>;` | undefined | about 1,700 | Render state. Supplies the primitive type (`TRIANGLESTRIP`, `LINELIST`) plus transparency, blend and texture-enable flags. |
| `<Shader>__EAGLMicroCode`, `ParentRM_<Shader>` | undefined | | Shader and template, defined in the render-method library object `data.gob/a9d179c58d5c861fcd90a5f9b45571ed.o` |
| `__const MATRIX4:::EAGL::ViewPort::gp*Matrix`, `__const MATRIX4:::EAGLAnimationBuffer`, `__COORD4:::...` | undefined | | Engine shader constants (matrices, lights, bone palette) |

## 3. Model

Entry point: `__Model:::<name>` (symbol value = offset M). Field offsets are relative to M.

| Off | Type | Meaning | Confidence |
|---|---|---|---|
| 0x00 | ptr | Runtime parameter-slot table: 16-byte entries `{char *name, u32 flags 0x0001xxxx, u32 count, ptr}`. Names include `CompoundIndex::CompIdx`, `Coordinate4::LightMultipliers`, `GeoPrimState::State`, `IrradLight::IrradBlock`, `Light::LightBlock`. | observed layout; purpose inferred |
| 0x04 | u32 | Number of slot-table entries | observed |
| 0x08 | u32 | Variation count + 1. Equal in all 1,397 models; for example 35 for PlayerHigh. | observed |
| 0x0C | f32[16] | Model transform. Identity in all 1,397. | observed |
| 0x4C | f32[4] | Equals 4 x max\|extent\| (w = 1) | observed; purpose unknown |
| 0x5C | f32[4] | Equals 2 x max\|extent\| (w = 0) | observed; purpose unknown |
| 0x6C | f32[4] | Bounding-box min (w = 1) | observed |
| 0x7C | f32[4] | Bounding-box max (w = 1) | observed |
| 0x8C | f32[4] | Bounding sphere: centre xyz, radius | observed |
| 0x9C | u32 | Part count P | observed |
| 0xA0 | ptr | `char *partName[P]`, for example `00`..`11`, `geo_headShape`, `basehead`, `hhra`, `0000_0000` | observed |
| 0xB4 | ptr | Model name string | observed |
| 0xB8 | ptr | Shared texture table (format at offset 0xBC) | observed |
| 0xBC | ptr | Texture table: 16-byte entries `{char *shape, u32 1, TAR *handle, u32 flags}` | observed |
| 0xC0 | u32 | Variation index. 0 for the base model, N for `.variationN`. | observed |
| 0xC4 | ptr | Per-part u32 table: values `0x0001xxxx` that rise by 11 per part | observed; meaning unknown |
| 0xC8 | u32 | 1 in all 1,397 models. Probably the LOD count, but player LODs ship as separate files. | inferred |
| 0xCC | ptr | Part table: `u32 0`, then for each part `u32 n, ptr block[n]`. Each block is a RenderMethod binding block (section 4.2). | observed (all 1,397 have a leading 0) |

Variations differ from the base Model only at 0xBC, 0xC0 and 0xC4. They share all geometry, so
a variation is a runtime texture-set choice. The converter exports only the base Model unless
`--variations` is passed.

Placeholder objects exist: 121 `PitchFinal.o` and a few others have zero parts or zero geometry.
They convert to empty scenes.

## 4. RenderMethod

### 4.1 Header (symbol `__RenderMethod:::__GPRenderMethod_*`, offset R)

| Off | Type | Meaning | Confidence |
|---|---|---|---|
| 0x00 | ptr | Command stream. Equals the geoprimdatabuffer symbol + 4. | observed |
| 0x08 | ext | `<Shader>__EAGLMicroCode` | observed |
| 0x10 | ext | `ParentRM_<Shader>` | observed |
| 0x1C | u32 | 0xFFFFFFFF | observed |
| 0x24 | ptr | geoprimdatabuffer symbol (a zero word) | observed |
| 0x28 | i32 | 4 for skinned shaders (1,479), 3 (36), -1 otherwise (8,521) | observed; meaning unknown |
| 0x2C | ptr | Shader name string, for example `LitTexture2IrradSkinSubSurfSpec` | observed |
| 0x34 | u32 | Magic `0xABCDEFEA`. Present in all 9,991 instance RenderMethods; absent in the library templates. | observed |
| 0x38 | - | Binding block (4.2) | observed |

### 4.2 Binding block (at R + 0x38; Model part tables point here)

Layout: `ptr self -> R`, then `(u32 count, ptr target)` pairs. The parent template fixes the
number of pairs; no terminator is guaranteed. The reader stops at the first pair whose pointer
word has no relocation. The order follows the shader's parameter list. Typical skinned order:

| Pair | Target | count |
|---|---|---|
| 0 | GeoInfo `{u32 indexCount, u32 vertexCount, u32 primitiveCount}` | 1 |
| 1..k | `EAGL::TAR` texture handles in sampler order (texture stage 0, 1) | 1 |
| | `EAGL::GeoPrimState` | 1 |
| | engine constant block | 1 |
| | Compound table (section 7) | number of compounds |
| | `EAGLAnimationBuffer` | 128 (bone-palette size) |
| | view matrices, light blocks, `__COORD4` constants | 1 |
| last-1 | vertex buffer | vertex count |
| last | index buffer | true index count |

The last two pairs always point at the same buffers as the stream commands. The index-buffer
pair carries the true index count, which can be one less than the command's padded count
(section 5.2).

## 5. Command stream ("geoprim data buffer")

A sequence of 32-bit words. Each command header is `(opcode << 16) | wordCount`, and wordCount
includes the header. A single zero word separates per-pass blocks. Two zero words, or a relocated
word in header position, end the stream. Each block starts with an opcode-0x45 command
`(passIndex, -1)`. Block 0 is the main pass.

Opcode numbers are not global. The same logical command is `0x4B`/`0x07` in instances of
`LitTexture2IrradSkinSubSurfSpec`, `0x4A`/`0x08` in that shader's ParentRM template, and
`0x04`/`0x07` in `IrradLitTexture2x`. Opcode 1 appears to be a NOP: later blocks replace earlier
commands with op 1 while keeping their arguments. Opcode `0x41` wraps a copy of the vertex
command plus further sub-commands (`0x33`, `0x34`, `0x3D`, `0x32`, `0x44`); its meaning is unknown.
The converter therefore matches commands by **shape**. Across the corpus, the 36,540 vertex
commands and 36,540 index commands below are the only commands that carry a `.data` pointer
outside `0x41` wrappers. (Confidence: observed shape; opcode semantics unknown.)

### 5.1 Vertex buffer command (12 words)

`hdr, stream(0), stride, FVF, -1, -1, *vertices, vertexCount, -1, bufferId, -1, -1`

* FVF is a Direct3D FVF code. The stride computed from the FVF matches the stored stride for
  every chunk.
* bufferId equals the RenderMethod index `i` in most objects; some files use other numbers.

### 5.2 Index buffer command (6 words)

`hdr, 2, -1, -1, *indices, indexCount`

* Indices are u16 and local to the chunk's vertex buffer.
* indexCount is always even (padded). In 872 of 9,991 chunks the pad index is out of range. In
  others it is an in-range garbage value (for example, head 002ace..: GeoInfo 2121 vs command
  2122). Always use the GeoInfo / binding count.
* Primitive type comes from the bound GeoPrimState name. Observed: `TRIANGLESTRIP` (9,814 chunks)
  and `LINELIST` (177). Strips join with repeated (degenerate) indices. Triangle i is
  (i, i+1, i+2) for even i and (i+1, i, i+2) for odd i.

## 6. Vertex formats (D3D FVF)

| FVF | Stride | Layout | Chunks | Used by |
|---|---|---|---|---|
| 0x142 | 24 | pos f32x3, D3DCOLOR, uv f32x2 | 8,249 | stadium, pitch, sky, props |
| 0x256 | 48 | pos f32x3, beta u32, normal f32x3, D3DCOLOR, uv0 f32x2, uv1 f32x2 | 1,477 | players, heads, hair (skinned) |
| 0x42 | 16 | pos, D3DCOLOR | 180 | line lists |
| 0x156 | 40 | pos, beta, normal, D3DCOLOR, uv | 39 | skinned props |
| 0x152 | 36 | pos, normal, D3DCOLOR, uv | 28 | ball, trophies |
| 0x52 | 28 | pos, normal, D3DCOLOR | 17 | |
| 0x46 | 20 | pos, beta, D3DCOLOR | 1 | |

* D3DCOLOR is stored as bytes B, G, R, A (observed: 0xFFFFFFFF on faces).
* UV origin is top-left. No V flip is needed; the textured head render confirms this.
* The "beta" slot (XYZB1) holds an **integer compound index**: denormal float bit patterns such
  as 0x7A, all smaller than the bound compound count. The library microcode declares it as
  `D3DVSD_REG(1, FLOAT1)`. The D3D8 vertex-shader declarations in
  `LitTexture2IrradSkinSubSurfSpec__EAGLMicroCode` are stream 0: v0 FLOAT3, v1 FLOAT1, v2 FLOAT3,
  v3 D3DCOLOR, v4 FLOAT2, v5 FLOAT2. This matches FVF 0x256. (observed)

## 7. Skinning: compound table

Each skinned chunk binds a table of N 16-byte "compounds". The beta value of each vertex selects
one compound. A compound is four f32 weights. **The low 8 mantissa bits of each weight hold the
bone index**: `bone = word & 0xFF`, `weight = float(word & 0xFFFFFF00)`. Zero words are unused
slots. The weights of a compound sum to 1 within 0.02.

Example: PlayerHigh `dc6975fd..` chunk 0 (boots, textures `clet` and `dirt`) has 8 compounds
over bones 20, 21, 24 and 25 (LFoot, LToe, RFoot, RToe). The weights are 0.55/0.45,
0.625/0.375 and 1.0 pairs.

Identification: in all 1,517 skinned chunks, the binding just before `EAGLAnimationBuffer` has
count >= max(beta)+1 and decodes as valid weights. The converter uses that binding and falls back
to content validation.

Confidence: high. A posed CPU-skinning test (arms rotated, forearm and knee bent) deforms the
body cleanly.

## 8. Skeleton

The `__Skeleton:::<name>` header is `u32 0x01FEC0DA, u32 0xC0DA, u32 boneCount, u32 0`. Bone
records of 112 bytes follow from +0x10:

| Off | Type | Meaning |
|---|---|---|
| 0x00 | f32x3 | local scale |
| 0x0C | i32 | parent index (-1 = root) |
| 0x10 | f32x4 | local rotation quaternion (x, y, z, w) |
| 0x20 | f32x4 | local translation (w = 0) |
| 0x30 | f32[16] | inverse bind matrix, D3D row-vector order (translation in the last row) |

`__Bone:::<skel>.<name>` symbols point at a 16-byte-per-bone table just before the header
(`header - 16 x boneCount + 16 x i`). Each entry's first word is the bone index.

* The player skeleton is `!skel.o` in `data.gob.nested/6fe231645db934f9f6afa48797b39579.big/`
  (51 bones: Hips, spine x3, Neck, Head, arm chains with twist bones, legs, 15 face bones, two
  fingers + thumb per hand). That archive also holds `!eagl` (`__AnimationBank:::bank`).
* Bodies, heads and hair in other files carry no skeleton. Their compound bone indices index this
  51-bone skeleton: head chunks use Jaw/LoLip/Head and so on. `hair_temp`/`head_temp` objects
  embed their own copy (same bone names).
* Check: for every bone, (local chain) x (inverse bind) = identity within 0.0064. Quaternion and
  row-vector conventions are confirmed.
* `flag.o` (corner flag, `data.gob/65f1fa06..`) has a cloth skeleton with a different header (no
  magic). It is not decoded; the census logs it as its only decode error.

## 9. Textures

The shape name in each bound TAR symbol is the FSH entry name (for example `face`, `hair`,
`dirt`, `kit0`, `jbck`, `clet`, `skin`, `bala`, `tp08`). The first TAR binding is used as base
colour. Stage 1 is usually `dirt` or a detail map, kept in `materials[].extras.eagl_textures`.

* Nested archives ship the FSH next to the model (`model.o` + `textures.fsh`; `Stadium.o` +
  `Textures.fsh`/`Crowd.fsh`). The converter links
  `extracted/textures/<same path>/<fsh>/<shape>.png` when that file exists.
* Loose `data.gob` objects (player bodies, ball, trophies) bind shapes such as `kit0`, `jbck` and
  `bala`. These shapes exist in many hashed FSH members (`jbck` in 4,164, `kit0` in 195), and
  their selection is done at runtime. These materials carry the shape name only.
* `SHAPENAME=<s>,<k>`: k equals the number of variations (35 for PlayerHigh, 1 for heads). It is
  probably a texture-group size for variation selection (inferred).

## 10. Coordinates, winding and units

| Item | Finding | Confidence |
|---|---|---|
| Up axis | +Y. Players stand on y = 0. | observed |
| Facing / handedness | Nose and toes point to +Z and the bone named LArm is at +X. This matches glTF convention (+Z forward, +X = the asset's left), so no axis mirror is applied. | inferred; text orientation not yet checked |
| Winding | With the strip parity rule, 785,250 of 787,752 triangles (99.7%) have a right-hand geometric normal opposite to their stored vertex normals. Front faces are clockwise, so the converter reverses winding for glTF. A back-face-culled textured render then shows the outside of the head and the inside of the stadium bowl. | observed |
| Units | Player 96 units tall, ball 16 units long, pitch markings span x +/-1,774 by z +/-3,379, stadium about 12,500 across. Estimate about 48-54 units per metre (about 0.02 m per unit). The converter keeps native units. | inferred |

## 11. Walking from symbols to vertices (converter algorithm)

1. Parse the ELF and build the relocation map (offset -> internal target or external symbol).
2. For each `__RenderMethod:::__GPRenderMethod_*`:
   - Read the stream pointer (+0x00) and the binding block (+0x38).
   - Scan stream block 0 for the 12-word vertex command and the 6-word index command.
   - Decode the FVF.
   - Take the true index count from the binding whose pointer equals the index buffer.
   - Take the primitive type from the GeoPrimState binding and textures from TAR bindings.
   - If the FVF has a beta, decode the compound table.
3. For each base `__Model:::*`, walk the part table (+0xCC). Each part gives one glTF mesh whose
   primitives are its RenderMethods.
4. Skeleton: use the object's own `__Skeleton`, or `--skeleton .../!skel.o`. Emit joints as nodes
   with local TRS, and the inverse bind matrices unchanged: row-major D3D storage equals glTF
   column-major storage. JOINTS_0/WEIGHTS_0 come from the compounds.
5. Write the triangles with winding reversed, line lists as `LINES`, and COLOR_0, NORMAL and
   TEXCOORD_0/1.

## 12. Verification

* Bulk conversion of all 1,400 objects: exit 0, 2,057,928 triangles, 625 skinned files, 128 empty
  scenes (placeholders, library, skeleton and animation bank).
* Every exported index is in range, every joint index is less than the joint count, and the
  weights of every vertex sum to 1. The checks ran on the four sample exports.
* Godot 4.7.2 headless `GLTFDocument.append_from_file` loads the ball, player, head and stadium
  with `err = 0`. Mesh counts are 1, 14, 2 and 6. The player and head each have a Skeleton3D.
* Rendered previews are in `.omc/research/models/previews/` (gitignored):
  - flat-shaded ball, player body and stadium (`eagl preview`)
  - textured, back-face-culled head and stadium rendered from the glTF
  - posed, CPU-skinned player
  The verification scripts are kept next to them.

## 13. Evidence index

| Claim | Where |
|---|---|
| Model/BBOX/RenderMethod layout | `data.gob/c77c42003b72d5d7a7c17f0659fbe253.o` (ball): Model @0x5FF0, RM @0x2F50/0x5E20, GeoInfo @0x0 = {586, 274, 584} |
| Padded index count | head `data.gob.nested/002ace43../model.o`: RM2 IB command count 0x238, binding count 0x237, last index 0x2220 |
| Opcode variance | the same head (0x4B/0x07) vs ball (0x04/0x07) vs library ParentRM template @0x15470 (0x4A/0x08) |
| Compound encoding | PlayerHigh `data.gob/dc6975fd9498de7faa1f5b263a690e5e.o`: table @0x1C, bound with count 8 by RM0 @0x71F0 |
| Skeleton record layout | `!skel.o` header @0x330, records from @0x340, stride 0x70 |
| Microcode vertex declaration | `data.gob/a9d179c58d5c861fcd90a5f9b45571ed.o` @0x137EC, `IrradLitTexture2x` @0x73EC |
| Stadium (6 parts, 161 RMs, `Texture2x`) | `data.gob.nested/006f374424db202257646c5f8ebb9bea.big/Stadium.o` |
| Corpus-wide counts | `.omc/research/models/census.json` |

## 14. Open questions (also recorded as REA unknowns)

1. The opcode dispatch table for the EAGL PC runtime: what the opcodes mean, including `0x41`
   and `0x1C (a, b, c)`. Needs the unpacked exe. (REA `unk_ad7f093d..`)
2. The exact unit scale, and whether the runtime mirrors any axis. Verify using sponsor-board or
   kit-number text on a textured stadium or kit. (REA `unk_1746a74f..`)
3. How variations and the `SHAPENAME=..,k` group pick textures, which hashed FSH feeds loose
   player and ball objects, and the format of the flag cloth skeleton. (REA `unk_03bcadbd..`)
4. Meaning of the Model fields at 0x4C, 0x5C and 0xC4, and RenderMethod +0x28.
5. Animation banks (`__AnimationBank`) are untouched. They are the next step for player
   animation.
6. Whether a part's 2 RenderMethods are layered materials (both drawn) or alternatives. Bodies
   show overlapping shirt shells. The converter draws all of them.
