# 03 - Audio archives (Rugby 08)

Scope: the `Audio/` directory of the Rugby 08 (EN) install. Everything below is from
observation (magic bytes, header tags, names, and ffmpeg/ffprobe output). Anything not
verified is labelled as such. Originals are read-only; extraction output lives under
`extracted/audio/` and conversion output under `extracted/ogg/` (both gitignored).

Tooling:

- `openrugby_tools extract <archive> -o extracted/audio/<name>.big` (BIGF + RefPack)
- `openrugby_tools.audio convert <src> <out> [--vgmstream PATH]` (SCHl header parse; ffmpeg to OGG Vorbis `-q:a 5` where ffmpeg can read the stream, otherwise `vgmstream-cli` to WAV then ffmpeg to OGG; 8 workers; writes `index.json` with a per-entry `decoder` field). vgmstream path: `--vgmstream`, then `$OPENRUGBY_VGMSTREAM`, then `.omc/research/bin/vgmstream-cli`, then PATH.

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
| `0xA0` | second codec field ("revision2" in ffmpeg, "codec2" in vgmstream). 4 = EA MicroTalk (speech codec; all `dat_eng` and `ref_eng`), 9 = signed 8-bit PCM (`practice_crowd.ast`). **Verified** with vgmstream r2117 (see "vgmstream verification"). | ffmpeg demuxer rejects both values; `vgmstream-cli -m` reports "Electronic Arts MicroTalk" / "8-bit signed PCM" |
| `0x06` | always 101. Meaning unknown. | every SCHl member |
| `0x0B` | value 2 in some `chants` PT streams. Meaning unknown. | 14+9 chants members |
| `0x05`, `0x13`, `0x9C`, `0x9D` | present only in `aems` `crowd_streams.ast`. Meaning unknown. | single member |

Header values that disagree with ffmpeg:

- `aems/crowd_reactions.ast`: header sample count 236582 and no 0x84 rate. ffmpeg decodes 202.92 s at 22050 Hz (about 4.47 M frames), so for this member `0x85` does not equal the decoded frame count. Unresolved: either the header count or the demuxer's view of the stream is wrong. Treat its duration as ffmpeg's value for now.

## vgmstream verification

vgmstream-cli r2117 (official `vgmstream-linux.zip`, sha256 `2f98c77f756079f63fbd119939067f1ed461d77e70993bc4cc372736d859c84a`, matching the GitHub release digest) installed to `.omc/research/bin/vgmstream-cli` (gitignored). vgmstream selects parsers by file extension and rejects `.dat` (`failed opening`), so the converter links the source as `in.snd` in a temp dir. Raw `-m` output:

```
ref_eng.big/Referee_Australia_Colours_Advantage_Calling_1.snd   (0xA0 = 4)
sample rate: 44100 Hz
channels: 1
stream total samples: 53717 (0:01.218 seconds)
encoding: Electronic Arts MicroTalk
layout: blocked (EA SCHl)
metadata from: Electronic Arts SCHl header (variable)
bitrate: 76 kbps

dat_eng.big/0001_Abril.dat (as .snd)   (0xA0 = 4)
sample rate: 22050 Hz
channels: 1
stream total samples: 15937 (0:00.723 seconds)
encoding: Electronic Arts MicroTalk
layout: blocked (EA SCHl)
bitrate: 51 kbps

aems.big/practice_crowd.ast   (0xA0 = 9)
sample rate: 22050 Hz
channels: 2
stream total samples: 14 (0:00.001 seconds)
encoding: 8-bit signed PCM
layout: blocked (EA SCHl)
```

So `0xA0` is the codec2 field: 4 = MicroTalk, 9 = 8-bit signed PCM. The hypothesis is confirmed. `crowd_streams.ast` (no `0xA0`) is reported as "EA-XA 4-bit ADPCM v2", 44100 Hz, 2 ch, 32 samples.

Conversion with vgmstream (`extracted/ogg`, whole tree re-run): 5508 SCHl members, 5508 ok, 0 failed (434 ffmpeg, 5074 vgmstream), 14740.1 s total, 188.5 MB OGG, 96.6 s wall at 8 workers. Per archive: `dat_eng` 3788 ok, 7412.0 s, 69.61 MB; `ref_eng` 1284 ok, 3097.1 s, 41.81 MB; `aems` 4 ok, 235.3 s. Decoded duration equals header sample count / rate on all 4785 vgmstream members that carry 0x84 and 0x85 (worst delta 0.0000005 s).

Caveats:

- `aems/practice_crowd.ast` (14 samples) and `aems/crowd_streams.ast` (32 samples) "convert" to sub-millisecond stubs. Their SCDl payload is tiny, so the real data is presumably elsewhere (the `.abk` banks); not verified.
- Peak sample is 32768 (full scale) in 4 of 5 spot-checked files, so the decoder output may clip or be mastered hot. Not investigated.
- Sanity numbers (mono, first 5 streams checked; 20 ms RMS envelope, ratio = 90th / 10th percentile): `dat_eng/0001_Abril` rms 0.298 FS, zcr 0.048, ratio 11.7; `dat_eng/10N_NEED_WIN` rms 0.260, zcr 0.112, ratio 35.3; `dat_eng/ZP_OPENING` rms 0.261, zcr 0.116, ratio 51.3; `ref_eng/Referee_Australia_Colours_Advantage_Calling_1` rms 0.205, zcr 0.065, ratio 51.4; `ref_eng/TUTORIAL_CONCLUSION_1A` rms 0.121, zcr 0.071, ratio 18.8. Low-to-moderate ZCR with a large amplitude envelope range is what speech looks like; white noise would give ZCR near 0.5 and a flat envelope. Not listened to.

Licensing: vgmstream is a dev-time extraction tool only and is not shipped with the game. Open item: the shipped game needs its own decoder (or pre-extracted OGG with a rights decision); not yet decided.

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
| ref_eng.big | 1284 | 0 | 1284 | - | - | - | - (ffmpeg only; 1284 ok via vgmstream, see below) |
| dat_eng.big | 3788 | 0 | 3788 | - | - | - | - (ffmpeg only; 3788 ok via vgmstream, see below) |
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
- **Pairing (evidence):** each `dat_eng` member is a container of several concatenated SCHl streams, each starting at a 256-byte-aligned offset (3576 of 3788 members hold more than one; 11205 streams in total; the `SCHl` magic occurs only at 256-aligned offsets after the first). `.hdr` byte 5 equals the number of `SCHl` streams in the paired `.dat` on 3787 of 3788 members (miss: `KNOCK_ON_DROP_PUNT`, hdr 9 vs 8 found). The `.hdr` also lists the start offsets of streams 2..N in 256-byte units (e.g. `ADVANTAGE_GENERAL.hdr` ends `27 00 4d 00 6d 00 9f 00 70 70`, and the `.dat` has SCHl at 0, 39, 77, 109, 159 x 256). For 24-byte records the u16 at offset 16 times 256 equals the second stream's offset on 2602 of 2836 records. The earlier "u32@8 proportional to dat size" is therefore a size-like field, not a count of SCCl/SCDl chunks (the SCCl value, big-endian, equals the SCDl count of a stream on 3725 of 3788 members).
- **Consequence:** the converter decodes only the first stream of each member (3788 of 11205 dat_eng streams, 7412 s). Splitting at the later 256-aligned `SCHl` offsets would yield the rest. Not done yet.
- Two record shapes by size: 24-byte (2836 records) and 16/20-byte (334 and 244 records, different prefixes such as `c4 05 ff ff` and `f6 05 ...`). Other sizes are rare (up to 100 bytes).
- Observed on the 24-byte records:
  - uint32 LE at offset 8 is proportional to the `dat_eng` size. Ratio of dat bytes to this field: mean 262.92, stdev 1.98. The field is therefore a block or packet count for the `.dat`. The packet structure was not decoded, so treat this as a strong correlation, not a confirmed field meaning.
  - uint16 at offset 2 equals the member's ordinal in the first entries (`0001 → 01 00`, `0002 → 02 00`, ... `0012 → 0c 00`), but not in every record.
  - No field correlates with the header sample count strongly enough to call it the length (max correlation 0.87 with samples for u32@8, which is the dat-size proxy).
- hdr_eng is not a playable format. It is a companion index keyed by the same names as dat_eng, carrying a per-member count-like field.

## Unknowns

- `SCORE_*.dat` (5 members): `SCORE_LEAD_BY`, `SCORE_LEAD_BY_OVER`, `SCORE_LINES`, `SCORE_TRAIL_BY`, `SCORE_TRAIL_BY_MORE_THAN`. vgmstream rejects them because they begin with zero padding, but they are the same multi-stream containers as other `dat_eng` members: the first SCHl (GSTR, same header shape as dialogue) starts at the first 256-aligned offset after the zeros (21760, 1408000, 724224, 10240 and 1254400 bytes), followed by more 256-aligned SCHl streams. Presumably score-announcement speech (by name). Not converted yet (the converter skips files that do not start with SCHl).
- `aems/*.abk` (17 ABKC): sound-bank format, not converted. `aems/rugby2k8.csi` is the MOIR member, format unknown.
- `pbp.evt`: unknown; not converted.
- Runtime decoding: the GSTR `0xA0 = 4` streams are EA MicroTalk (decoded offline via vgmstream, dev-time only). Open item: the game needs its own MicroTalk (UTK) decoder or shipped pre-converted OGG; licensing of either route is undecided.
- Open item: split the multi-stream `dat_eng` members (and `SCORE_*`) at 256-aligned `SCHl` offsets to decode all 11205+ streams.
- `0x06`, `0x0B`, and the 0x84 absence in TUTORIAL and crowd_reactions: meaning unknown.

## Reproduce

```sh
PYTHONPATH=tools .omc/research/venv/bin/python -m openrugby_tools extract <Audio>/<name>.big -o extracted/audio/<name>.big
PYTHONPATH=tools .omc/research/venv/bin/python -m openrugby_tools.audio convert extracted/audio extracted/ogg   # add --vgmstream PATH if not in .omc/research/bin
PYTHONPATH=tools .omc/research/venv/bin/python -m openrugby_tools.audio convert <Audio>/nzh.dat extracted/ogg-standalone
```

Tests: `cd tools && ../.omc/research/venv/bin/python -m pytest -q` (header parser tests are synthetic; ffmpeg and vgmstream tests skip if the tool or the extracted audio is missing).
