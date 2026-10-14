# Reverse-engineering specifications

This index covers the Phase 1 specifications. The specs describe observable behaviour and numeric
values; implementation structure belongs to the Godot architecture (PLAN §4 rule 0). Evidence
addresses and original names are evidence labels only.

## Spec index

| Spec | Scope | Confidence | Key open items |
|---|---|---|---|
| [00 — Binary orientation](00-binary-orientation.md) | Executable identity, packing and analysis setup | High for file facts; medium for packer interpretation | Exact provenance of the repacked executable; protection wrapper behaviour |
| [01 — Archive inventory](01-archive-inventory.md) | Archive and member census | High for counts and signatures; low for unidentified formats | ABK/CSI formats, `moai.viv`, unknown nested binary members |
| [02 — FSH textures](02-fsh-textures.md) | SHPI/FSH texture layout and extraction | High for decoded layouts | 0x7C region semantics, alpha treatment and unused header fields |
| [03 — Audio](03-audio.md) | SCHl streams and header archives | High for archive census and parser results | ABK/CSI; runtime MicroTalk route and licensing; SCORE stream/header mismatch |
| [04 — Models / EAGL](04-models-eagl.md) | Model, render method, skeleton and vertex conversion | High for layouts; medium for exact unit interpretation | Runtime opcode meanings, exact asset scale/axis conversion, texture variations, animation banks |
| [05 — Rules](05-rules.md) | Referee, laws, scoring, clock, cards and restarts | High for core clock, score and card values; medium for some triggers | Golden-point stop, shoot-out format, some decision labels and detection conditions |
| [06 — Physics](06-physics.md) | Ball flight, contact, passing, tackling and locomotion | High for many numeric models; medium/low for selected predicates and data | Frame-dt source/cap, pass/catch predicates, tackle reach, field width confirmation |
| [07 — Set pieces](07-setpieces.md) | Scrum, lineout, ruck, maul, kicks and restart mechanics | High for decoded formulas; medium for inferred mechanics | Quick-tap gates, scrum/lineout/ruck/maul outcomes, kick-off targets, set-play units |
| [08 — AI](08-ai.md) | Carrier decisions, defence, CPU choices and difficulty | High for core tables; medium for incomplete branches | Defensive values, team tactic wiring, impact-player behavior, set-play units |
| [09 — Players and teams](09-players-teams-db.md) | Player records, attributes, fatigue, injuries and squads | High for roster layout and fatigue model; medium for unclear bytes | Unknown record fields, form application, substitution policy, career injury duration |
| [10 — Modes and competitions](10-modes-competitions.md) | Competition data, standings, modes and settings | High for schedule data; medium for competition builders | Playoff seeding, save layout, simulated matches, tournament defaults and third-period golden point |
| [11 — Input, camera and HUD](11-input-camera-hud-save.md) | Controls, camera presets, UI flow and settings/save evidence | High for input mappings; medium/low for camera and save behavior | Save schema, camera dynamics, HUD layout and device assignment details |
| [12 — Motion and animation](12-motion-animation.md) | Motion clips, sampling and sequence-bank framing | High for clip layout and sampling; medium/low for sequence semantics | Event semantics, blend behavior, root-motion composition and facial animation |
| [13 — Game-data catalogue](13-game-data-catalogue.md) | Text, locale, XML and commentary-event formats | High for decoded structures; medium/low for inferred field meanings | PBP rules, unknown FntF fields, `.match`/`.rdf`, `.list` prefix and unresolved clips |

The binary orientation and archive/format inventories (00–04) are supporting format references,
not gameplay subsystem specs. They do not yet all use the complete Phase 1 subsystem brief structure;
see [the gate review](REVIEW-phase1.md).

## Shared glossary and units

| Term | Meaning / unit |
|---|---|
| Gameplay distance | Metres (m), except where an asset's native model units are explicitly stated |
| Gameplay time | Seconds (s); the match clock uses game seconds, while input and presentation timers generally use real seconds |
| Match clock | Game seconds elapsed from kick-off; 60 game seconds = one game minute |
| `dt_real` / `dt_sim` | Wall-clock frame delta / game simulation delta; physics reports the PC build as variable-step, while the rebuild plan requires a deterministic fixed step |
| Pitch frame | x lateral, y up, z longitudinal; halfway at z=0; team attack direction is ±1 |
| Team-relative depth | `z × direction`; increasing values point toward the opponent's try line |
| Attribute stat | Integer 0–100 unless a field states another range; stored player bytes and getter indices are distinct identifiers |
| Probability | Unit interval [0,1], unless a table explicitly uses percent or per-mille |
| Model unit | Native EAGL asset coordinate; physics gives 1 model unit = 0.01905 m |
| Clip frame rate | 15 decoded frames/s; clip sampling time is stored in ticks of 1/60 s (four ticks per frame) |
| Set-piece animation tick | `07` reports 50 ticks/s for a separate animation clock; equivalence to the motion clip sampling clock is unresolved |
| Confidence labels | Observed means directly read from data/code; inferred means supported but not directly confirmed; unknown means unresolved |

## Canonical shared values

The owner column names the spec that defines the value for implementation. Other specs should
cross-reference that owner when repeating it. Values shown here recur across at least two specs.

| Value | Canonical value | Owning spec | Other references |
|---|---|---|---|
| Pitch axes and origin | x lateral, y up, z longitudinal; halfway z=0 | [06 §2.1](06-physics.md) | 04 §10, 07 §0, 08 preface, 09 Answers §4 |
| Try-line depth | z = ±50 m | [06 §2.1](06-physics.md) | 05 §3, 07 §0, 08 preface/§3, 09 Answers §4 |
| 22 m line depth | z = ±28 m | [06 §2.1](06-physics.md) | 05 §3, 07 §0, 08 preface/§3 |
| In-goal depth / dead-ball line | 14.1 m beyond try line; \|z\| = 64.1 m | [06 §2.1](06-physics.md) | 09 Answers §4 (corrected to cross-reference 06) |
| Goal width | 5.6 m between posts | [06 §2.1](06-physics.md) | 07 §K.2 / §3, 09 Answers §4, 13 §3.3 |
| Match half duration | 2400 game s (40 game min) | [05 §2.8](05-rules.md) | 09 §2.3, 10 §2.11 |
| Match-length options | indices 0..4 = 2, 5, 10, 20, 40 real min per half; rates 20, 8, 4, 2, 1 game s/real s | [05 §2.8](05-rules.md) | 09 §2.3, 10 §2.11, 11 §3 |
| Default match length | index 1 = 5 real min per half | [05 §2.8](05-rules.md) | 10 §2.11 |
| Period end values | 2400, 4800, 5400, 6000, 6600 game s | [05 §2.8](05-rules.md) | 09 §2.3, 10 §2.11 |
| Extra time | Up to three periods, 600 game s each | [05 §2.8](05-rules.md) | 07 §3, 10 §2.11; golden-point end in period 3 is unresolved |
| Sin-bin duration | 600 game s; return at first stoppage after expiry | [05 §2.7](05-rules.md) | 07 §K.6, 08 §2.6, 09 §2.3 |
| Maximum players off | Two per team | [05 §2.7](05-rules.md) | 09 §2.3 |
| Penalty option ids | 0 goal, 1 scrum, 2 invalid, 3 touch punt, 4 tap-and-run | [07 §K.6](07-setpieces.md) | 05 §2.6, 08 §2.5 |
| Player attribute stored order | KickingPower is byte +0x29 but omitted from the 25-index getter sequence; later getter indices shift by one | [09 §4.1 and Answers §1](09-players-teams-db.md) | 06 §2.6, 07 §0.1, 08 preface; 07 confirms the set-piece getter behavior |
| Goal-kick difficulty levels | Club/Pro/Elite map to easy/normal/hard XML rows | [08 Answers](08-ai.md) | 07 §0 and §K.2; 13 §3.3 |
| Difficulty simulation speed | Club 1.10×, Pro 1.10×, Elite 1.15× | [08 Answers](08-ai.md) | 06 §2.2 |
| Model-to-gameplay scale | 1 model unit = 0.01905 m | [06 §2.1](06-physics.md) | 04 §10, 12 §2.2 |
| Motion clip timing | 15 frames/s; 1/60 s sampling ticks, four ticks per frame | [12 §2.2](12-motion-animation.md) | 04 §8 and §14 (animation bank noted); 07's 50-tick clock is separate/unresolved |
