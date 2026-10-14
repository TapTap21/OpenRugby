# 03 - Audio archives (Rugby 08)

Scope: the `Audio/` directory of the Rugby 08 (EN) install. Everything below is from
observation (magic bytes, header tags, names, and ffmpeg/ffprobe output). Anything not
verified is labelled as such. Originals are read-only; extraction output lives under
`extracted/audio/` and conversion output under `extracted/ogg/` (both gitignored).

Tooling:

- `openrugby_tools extract <archive> -o extracted/audio/<name>.big` (BIGF + RefPack)
- `openrugby_tools.audio convert <src> <out>` (SCHl header parse + ffmpeg to OGG Vorbis, `-q:a 5`, 8 workers, writes `index.json`)

## Archive census

| archive | members | member types (by magic) | notes |
|---|---|---|---|
| `anthems.big` | 20 | 20 SCHl (`GSTR`) | national anthems (`Argentina.asf` etc.) |
| `chants.big` | 394 | 394 SCHl (`PT`) | `EngGen*`, `FreGen*`, `Aus001`, `GnClap06`: crowd/chant clips, English and French names |
| `music.big` | 12 | 12 SCHl (`GSTR`) | long stereo tracks, e.g. `di.asf` (3:34) |
| `pamusic.big` | 6 | 6 SCHl (`GSTR`) | `pamusic1.asf` etc. |
| `ref_eng.big` | 1284 | 1284 SCHl (`GSTR`) | 996 `Referee_<Country>_<Topic>_<n>.snd`, 288 `TUTORIAL_*.snd` |
| `dat_eng.big` | 3793 | 3788 SCHl (`GSTR`), 5 zero-prefixed (`SCORE_*`) | see below |
| `hdr_eng.big` | 3793 | 3793 `.hdr` (no magic) | per-member header records, names match `dat_eng.big` 1:1 |
| `aems.big` | 22 | 17 ABKC, 4 SCHl (`PT`), 1 MOIR (`rugby2k8.csi`) | crowd, fireworks and practice-crowd streams (by name); ABKC = sound banks |

Loose files in `Audio/`:

- `nzh.dat`: one SCHl (`PT`), codec 1, 2 channels, 44100 Hz. ffprobe's bitrate estimate says 43.98 s; the converted OGG is 40.66 s. Presumed the haka (per the brief; not verified by listening).
- `pbp.evt`: 76.5 KB, first bytes `03 12 3c 07 b8 b9 00 00 ...`. Not SCHl, not BIGF. Unknown.

### dat_eng.big naming (observed)

- 2601 members named `NNNN_<Surname>` (e.g. `0001_Abril`, `0002_Abusseridze`), 65 numeric (`10195`, `1052`, ...), 1094 ALLCAPS event/situation names (`10N_NEED_WIN`, `YELLOW_KILLING_BALL`, `ZP_OPENING`), 5 mixed-case `Adlib_*` names.
- 15 `SCORED_*` and 13 `SCORE_*` names. Thirteen `SCORE_*` plus fifteen `SCORED_*` are SCHl. The other five `SCORE_*` members are zero-prefixed (see Unknowns).

Whether the `NNNN_<Surname>` members are player-name speech is an inference from the names only. The
brief's "commentary lines" description has not been checked by listening or by decoding.

### ref_eng.big naming (observed)

- `Referee_<Team>_<Situation>_<n>` (996 members). Situation names visible include `Colours_Advantage_Calling`, `DISCIPLINE`. The reading "referee calls" is consistent with the names but is not checked against content.
- `TUTORIAL_CONCLUSION_<n><x>` (288 members). Tutorial speech, by name.

## SCHl header (what the parser reads)

Layout, verified on every SCHl member:

- `"SCHl"`, uint32 LE header size (this value is also the offset of the following `SCCl` chunk; verified on all members that expose it).
- Patch block, one of:
  - `"PT\0\0"`, items start at offset 12 (`chants`, `aems`, `nzh.dat`).
  - `"GSTR"` + 4-byte version word, items start at offset 16 (`anthems`, `music`, `pamusic`, `ref_eng`, `dat_eng`).
- Items are `tag(uint8) len(uint8) value(len bytes, big-endian)`. `0xFD` and `0x00` are single-byte markers. `0xFF` terminates the list.

Tags, with evidence:

| tag | meaning | evidence |
|---|---|---|
| `0x80` | codec: 1, 2, 3 = `adpcm_ea_r1/r2/r3` | ffmpeg decodes the same value as r1/r2/r3 (checked on nzh, crowd_reactions, Argentina) |
| `0x82` | channels. Absent in 371 chants and in all 1284 `ref_eng` and 3788 `dat_eng` members. Converted absent-tag chants decode as mono. | ffmpeg output channels agree wherever the tag is present (no mismatches on 63 stereo members) |
| `0x84` | sample rate (Hz) | ffmpeg output rate equals the header on all 432 converted members that carry the tag. Absent in `crowd_reactions.ast` and `fireworks.ast` (ffmpeg picked 22050). |
| `0x85` | sample count per channel | matches ffmpeg decoded length to within 30 frames on all 432 converted members that carry 0x84 (deltas -27 to +0.02 frames on chants; fireworks 11) |
| `0xA0` | "revision2" (name from ffmpeg's error text). Values seen: 4 (all `dat_eng` and `ref_eng`), 9 (`practice_crowd.ast`). Meaning not verified. | ffmpeg demuxer rejects `revision2=4` |
| `0x06` | always 101. Meaning unknown. | every SCHl member |
| `0x0B` | value 2 in some `chants` PT streams. Meaning unknown. | 14+9 chants members |
| `0x05`, `0x13`, `0x9C`, `0x9D` | present only in `aems` `crowd_streams.ast`. Meaning unknown. | single member |

Header values that disagree with ffmpeg:

- `aems/crowd_reactions.ast`: header sample count 236582 and no 0x84 rate. ffmpeg decodes 202.92 s at 22050 Hz (about 4.47 M frames), so for this member `0x85` does not equal the decoded frame count. Unresolved: either the header count or the demuxer's view of the stream is wrong. Treat its duration as ffmpeg's value for now.

## ffmpeg / ffprobe census

ffprobe with autodetect works on PT and on GSTR streams that lack `0xA0`. It fails on `0xA0`-bearing streams with `stream type; revision2=4 is not implemented`. Forcing `-f ea` does not change this.

Conversion run (`convert extracted/audio extracted/ogg`, plus `nzh.dat` alone):

| archive | total | converted | failed | OGG duration (s) | OGG bytes | channels (ogg) | rates (ogg) |
|---|---|---|---|---|---|---|---|
| anthems.big | 20 | 20 | 0 | 403.5 | 7.73 MB | 2 | 44100 |
| chants.big | 394 | 394 | 0 | 1077.6 | 18.92 MB | 371 mono, 23 stereo | 48000 (385), 44100 (9) |
| music.big | 12 | 12 | 0 | 2352.7 | 44.42 MB | 2 | 44100 |
| pamusic.big | 6 | 6 | 0 | 161.9 | 3.09 MB | 2 | 44100 |
| aems.big (SCHl only) | 4 | 2 | 2 | 235.3 | 2.94 MB | 2 | 22050 (both converted members) |
| ref_eng.big | 1284 | 0 | 1284 | - | - | - | - |
| dat_eng.big | 3788 | 0 | 3788 | - | - | - | - |
| nzh.dat | 1 | 1 | 0 | 40.7 | 0.77 MB | 2 | 44100 |
| **total (incl. nzh)** | 5509 | **435** | **5074** | **4271.7** | **77.9 MB** | | |

Failures:

- 5072 members (3788 `dat_eng` + 1284 `ref_eng`), all with `0xA0 = 4`: `Error opening input files: Invalid data found when processing input`. Forcing the codec, or neutralising the `0xA0` item in a scratch copy, did not help. The demuxer rejects the file or the packets are not the layout R3 expects (`invalid number of samples in packet`).
- `aems/crowd_streams.ast`: header declares 32 samples and carries tags 0x9C/0x9D. ffmpeg cannot open it.
- `aems/practice_crowd.ast`: `0xA0 = 9`, rejected by ffmpeg.

Timing: 5508 members, 8 workers, wall 51 s for the extracted set (ffmpeg fails fast on the 5072 `0xA0` members; the 434 decodable members take most of the time, about 265 s user CPU). nzh.dat alone: 0.6 s. Index totals are in `extracted/ogg/index.json` (`summary`).

Header-derived duration (not decoded, unverified) for the undecodable archives: `dat_eng` 7412 s (about 2 h 4 min) at 22050 Hz, `ref_eng` 1290 s at 44100 Hz (996 members) and 22050/44100 unknown for 288 TUTORIAL members (no 0x84).

## hdr_eng.big

- 3793 members, names identical to `dat_eng.big` (3793/3793 matched, same stems, `.hdr` vs `.dat`).
- Two record shapes by size: 24-byte (2836 records) and 16/20-byte (334 and 244 records, different prefixes such as `c4 05 ff ff` and `f6 05 ...`). Other sizes are rare (up to 100 bytes).
- Observed on the 24-byte records:
  - uint32 LE at offset 8 is proportional to the `dat_eng` size. Ratio of dat bytes to this field: mean 262.92, stdev 1.98. The field is therefore a block or packet count for the `.dat`. The packet structure was not decoded, so treat this as a strong correlation, not a confirmed field meaning.
  - uint16 at offset 2 equals the member's ordinal in the first entries (`0001 → 01 00`, `0002 → 02 00`, ... `0012 → 0c 00`), but not in every record.
  - No field correlates with the header sample count strongly enough to call it the length (max correlation 0.87 with samples for u32@8, which is the dat-size proxy).
- hdr_eng is not a playable format. It is a companion index keyed by the same names as dat_eng, carrying a per-member count-like field.

## Unknowns

- `SCORE_*.dat` (5 members): `SCORE_LEAD_BY`, `SCORE_LEAD_BY_OVER`, `SCORE_LINES`, `SCORE_TRAIL_BY`, `SCORE_TRAIL_BY_MORE_THAN`. Their first 64 bytes are zero, not SCHl. Later bytes are non-zero (e.g. `SCORE_TRAIL_BY.dat`: 167,688 non-zero bytes of 225,536), so the format is unknown. Sizes: 0.2 MB to 8.9 MB. Not converted.
- `aems/*.abk` (17 ABKC): sound-bank format, not converted. `aems/rugby2k8.csi` is the MOIR member, format unknown.
- `pbp.evt`: unknown; not converted.
- The GSTR `0xA0 = 4` streams (dat_eng, ref_eng; 5072 members): the codec is probably ADPCM with a different packet layout, but this is not established. Nothing in ffmpeg reads them, and vgmstream (which documents the PT tags) is not installed. Converting the dialogue requires either a decoder for this variant or vgmstream.
- `0x06`, `0x0B`, `0xA0` values, and the 0x84 absence in TUTORIAL and crowd_reactions: meaning unknown.

## Reproduce

```sh
PYTHONPATH=tools .omc/research/venv/bin/python -m openrugby_tools extract <Audio>/<name>.big -o extracted/audio/<name>.big
PYTHONPATH=tools .omc/research/venv/bin/python -m openrugby_tools.audio convert extracted/audio extracted/ogg
PYTHONPATH=tools .omc/research/venv/bin/python -m openrugby_tools.audio convert <Audio>/nzh.dat extracted/ogg-standalone
```

Tests: `cd tools && ../.omc/research/venv/bin/python -m pytest -q` (header parser tests are synthetic; ffmpeg tests skip if ffmpeg or the extracted audio is missing).
