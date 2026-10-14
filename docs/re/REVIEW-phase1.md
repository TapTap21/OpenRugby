# Phase 1 consistency gate review

**Verdict: PASS WITH FIXES.** Core cross-spec values are coherent after the corrections below.
Phase 1 is not a blanket clearance for every S2–S5 behavior: the blocking unknowns are listed by
slice. This is a documentation gate; no REA session was used.

## Findings

| ID | File and section | Severity | Finding | Status |
|---|---|---|---|---|
| C1 | `docs/re/09-players-teams-db.md`, Answers §4 | Medium | The player answer said in-goal depth was not found, but 06 §2.1 specifies 14.1 m beyond the try line (dead-ball line at \|z\|=64.1 m). | Fixed: 09 now points to the shared physics constant; stadium variation remains unknown. |
| C2 | `docs/re/04-models-eagl.md`, §10 | Low | Asset measurements estimated 0.02 m/model unit while 06 §2.1 gives 0.01905 m/model unit. | Fixed: 04 retains the measurement estimate and identifies the precise conversion and owning spec. |
| C3 | `docs/re/10-modes-competitions.md`, §6 acceptance test 9 vs `docs/re/05-rules.md` §2.8 | High | Modes required a golden-point stop in extra-time period 3, while rules says the front-end text suggests it but an early stop was not found. | Fixed: the test now checks the observed period count and leaves golden point unasserted pending evidence. |
| C4 | `docs/re/10-modes-competitions.md`, §2.11 vs `docs/re/05-rules.md` §2.8 | Medium | “First referee report” could imply every report ends a period; rules enumerates only qualifying reports/stoppages. | Fixed: modes now links to the rules filter. |
| C5 | `docs/re/05-rules.md` §2.6, `docs/re/07-setpieces.md` §K.6, `docs/re/08-ai.md` §2.5 | Low | Penalty option ids and actions agree: 0 goal, 1 scrum, 2 invalid, 3 touch, 4 tap. Rules does not repeat numeric ids for all human-menu options, but its CPU mapping is consistent. | No change needed. Canonical mapping recorded in README. |
| C6 | `docs/re/05-rules.md` §2.8 / §3, `docs/re/09-players-teams-db.md` §2.3 / Answers §4, `docs/re/10-modes-competitions.md` §2.11, `docs/re/11-input-camera-hud-save.md` §3 | Low | Match clock, half-length options, rates, default, and period endpoints agree. The modes acceptance test only covers visible 5/10/20-minute choices, consistent with its note that 2 and 40 are settings-table values not shown in observed menu strings. | No change needed. |
| C7 | `docs/re/06-physics.md` §2.1, `docs/re/07-setpieces.md` §0, `docs/re/08-ai.md` preface, `docs/re/09-players-teams-db.md` Answers §4 | Low | Pitch origin, axes, try lines and 22 m lines agree. Touchline width is approximately ±33.65–33.7 m from drill/model data; physics explicitly says the code's out-of-bounds half-width remains unconfirmed. | No change needed; keep the field-width test/data qualified. |
| C8 | `docs/re/09-players-teams-db.md` §4.1 / Answers §1, `docs/re/07-setpieces.md` §0.1, `docs/re/06-physics.md` §2.6, `docs/re/08-ai.md` preface | Medium | Stored KickingPower at +0x29 is read directly and omitted from the getter's 25-entry index sequence. GoalKicking is getter index 8, Tackling 9, Creativity 20. Current cross-references agree. The separate XML/database 26-attribute schema includes three fields whose player-record bytes are unresolved; do not silently assign them to those reserved bytes. | Partly unresolved; no unsupported mapping added. |
| C9 | `docs/re/09-players-teams-db.md` §2.3 / §3, `docs/re/06-physics.md` §2.7–2.9, `docs/re/07-setpieces.md` §0.1 / §R.2 / §S.4, `docs/re/08-ai.md` §2.4 | Low | Shared fatigue condition and fatigue-adjusted Passing/Tackling/Rucking descriptions are consistent. Physics' independent sprint-energy pool is distinct and cross-references the player fatigue curve for its cap. | No change needed. |
| C10 | `docs/re/05-rules.md` §2.7 / §3, `docs/re/07-setpieces.md` §K.6, `docs/re/08-ai.md` §2.6 | Low | Sin-bin duration is 600 game seconds, return is at the first stoppage after expiry, and the two-player limit agrees. AI's penalty-expired event is explicitly the sin-bin event. | No change needed. |
| C11 | `docs/re/07-setpieces.md` §0 and `docs/re/06-physics.md` §2.8 / §3 vs `docs/re/12-motion-animation.md` §2.2 | Medium | Set pieces report a 50-tick/s animation clock and physics uses a 50-tick reach factor, while motion clips use 1/60 s playback ticks and 15 Hz frames. The specs do not establish that these are the same clock. | Open: keep separate time domains until callers are traced; do not normalize them by assumption. |
| C12 | `docs/re/06-physics.md` §2.2; `docs/PLAN.md` §1b, §4 | Medium | The original PC simulation is variable-step, but the rebuild convention requires a deterministic fixed physics step. Physics correctly marks the Godot tick as an ADR decision; implementation must preserve observed behavior rather than copy original update structure. | Open architecture decision for S1/ADR-001; not a contradiction in the behavior spec. |
| F1 | `docs/re/00-binary-orientation.md` | Medium | This file is an executable orientation reference, not a subsystem brief: it has no scoped gameplay behavior, tunables with units, rebuild data structures/mod hooks, acceptance tests, or confidence summary. “Known limitations” is not an explicit open-questions section. | Not fixed: supporting reference; template gap recorded. |
| F2 | `docs/re/01-archive-inventory.md` | Medium | Inventory only; no explicit subsystem scope/behavior, tunables with units, rebuild data structures/mod hooks, acceptance tests, or confidence summary. | Not fixed: supporting inventory; template gap recorded. |
| F3 | `docs/re/02-fsh-textures.md` | Medium | Format behavior and unknowns are documented, but there is no explicit scope, named tunable table with units/evidence, rebuild data structures/mod hooks, acceptance tests, or confidence summary. | Not fixed: texture-format follow-up can add the missing brief sections. |
| F4 | `docs/re/03-audio.md` | Medium | Archive behavior, evidence, reproduction and unknowns are present, but no explicit scope, named tunable table with units/evidence, rebuild data structures/mod hooks, acceptance tests, or confidence summary. | Not fixed: audio-format follow-up can add the missing brief sections. |
| F5 | `docs/re/04-models-eagl.md` | Low | The model format has behavior, data layouts, verification and open questions, but lacks a dedicated mod-hooks section, GDScript-checkable acceptance tests, and confidence summary. | Not fixed: add if model import is an active Phase 3 slice. |
| F6 | `docs/re/05-rules.md`–`docs/re/13-game-data-catalogue.md` | Low | These subsystem specs contain the requested section families. 10's acceptance test conflict and generic period-end wording are corrected above. Several use mixed heading names or subordinate sub-specs, but their intent is clear. | Fixed where contradictory; remaining structural variance is non-blocking. |
| Q1 | `docs/re/05-rules.md` §“Answers for implementation”; `docs/re/08-ai.md` §“Answers for implementation”; `docs/re/09-players-teams-db.md` Answers §1–4; `docs/re/10-modes-competitions.md` §2.11; `docs/re/11-input-camera-hud-save.md` §“Answers for implementation” | Medium | Each explicit S1/S9 “Answers for implementation” prompt has a response. Some responses are explicitly unresolved (cut-scene clock pauses; exact conversion spot; pitch-width rule; unknown player-record bytes; camera/save details), and are listed in slice blockers below. | Answered as far as evidence permits; unresolved items remain blockers where relevant. |

## S1 implementation questions

The explicit answer sections in 05, 08, 09 and 11 and the match-length answer in 10 cover every
question found in those sections. Some answers report evidence gaps rather than confirmed behavior:

- 05: whether cut-scenes pause the clock; exact conversion position; several shoot-out and card gates.
- 08: DifficultyProfile values are answered; some units and AI wiring remain unknown.
- 09: player bytes 0x33–0x35 and fitness_2/3 semantics, model-to-stadium pitch variation and some team data remain unknown.
- 11: right-stick consumer internals, camera dynamics and save serialization remain unknown.

No additional unheaded list of S1 implementation questions was found in the 00–13 specs. These
answers are sufficient to start S1 scaffolding with explicit unknown/default boundaries, but not to
claim final fidelity for the affected systems.

## Open questions blocking Phase 3 slices S2–S5

These gaps affect gameplay outcomes or required numeric tuning. They should be resolved or accepted
as explicit implementation defaults in the relevant slice spec before that slice's fidelity gate.

| Slice | Blocking questions |
|---|---|
| S2 — physics and locomotion | Confirm actual touchline/out-of-bounds half-width; determine the set-piece 50-tick clock relationship to motion's 60 Hz tick base; resolve wind mapping and pass/catch/tackle predicates that change outcomes; identify current sprint/fatigue inputs and preserve separate energy pools. See 06 §§2.1–2.2, 2.7–2.9, 7 and 12 §2.2. |
| S3 — rules/referee | Confirm cut-scene pause effects on clock; exact penalty goal spot and fourth-option semantics if user behavior requires it; resolve extra second-half period-end gate and golden point; resolve shoot-out number/positions/sudden death and key report/decision labels. See 05 §§2.6–2.8, 7. |
| S4 — set pieces | Resolve scrum rotate/No.8 and push-result semantics; lineout post-catch/ground-ball consequences; ruck release/holding-on thresholds; maul formation/exits/collapse restart; human kick-off/drop-out power, quick-tap gate/window; set-play range units and fly-half offset frame. See 07 §§R, S, L, M, K, Q. |
| S5 — AI | Resolve action-id behavior and team tactic/set-play wiring; defensive formation numeric values and switch input; units/frame for set-play ranges and offsets; incomplete scrum chooser, support spacing, scramble, impact-player and defensive branches. See 08 §§2.2–2.6, 7. |

Additional data/model questions in 04, 09 and 13 block asset integration or data completeness rather
than S2–S5 core gameplay: EAGL scale details, unresolved roster fields, and commentary/XML formats.
