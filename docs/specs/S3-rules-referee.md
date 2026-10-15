# S3: rules, referee, scoring and restarts

- Slice: S3. Depends on S1 core and S2 physics/contact. PLAN: Phase 3, slice S3.
- Evidence: [RE 05 rules](../re/05-rules.md) and its acceptance tests; [RE 07 set pieces](../re/07-setpieces.md) only where it names a rules-to-set-piece handoff.
- Reimplementation: carry over observable rugby behaviour and numeric values only. The data model, class names, call graph and update order are new.
- Test inventory: [S3 independent test inventory](S3-test-inventory.md). Resume state: [S3-RESUME](S3-RESUME.md).

## 1. Goal and boundary

Implement the deterministic referee and laws layer needed to award scores, classify supported
infringements, manage advantage and discipline, choose a restart, and control match periods. This is
the PLAN S3 slice. It replaces the placeholder transitions in S1's `default_match_flow.tres` and
supplies the RulesConfig fields which S1 deliberately left for S3.

S3 awards a restart and reports its kind, mark, awarded side and any set-piece ownership information.
S4 owns the scrum, line-out, ruck and maul mechanics. S3 consumes their typed reports and returns
awards to them; it does not implement formation contests, player binding, jump contests, scrum push,
maul drive, kick meters or set-piece animation.

S2 owns physical movement, ball flight, catches, pickups, tackle outcomes and kick launches. S2
does not decide legality, possession advantage, scoring, touch, try-line crossings, knock-on law,
offside, or restart selection. S3 owns those decisions when it has the required physical observation.

## 2. Evidence labels and implementation rule

Use **O** for an observed rule or value in RE 05/07, **I** for an inference, and **U** for unresolved
evidence. The labels on those sources apply here. Classic defaults may use O facts. I facts must be
isolated in named, patchable fields and described as inferred. U facts must not be presented as
recovered behavior or silently replaced by a plausible real-world law. A feature that depends on a U
fact must either remain explicitly provisional or be gated from the Classic default.

RE 05/07 use z for pitch length. S1's canonical `PitchGeometry` uses x for pitch length, y up and z
across width. Convert each RE position by `(x_S1, y_S1, z_S1) = (z_RE, y_RE, x_RE)`, preserving
signs; thus attack toward `+z_RE` is attack toward `+x_S1`. All implementation-facing state, report
and test values use S1 coordinates after this conversion. This axis mapping does not change any
observed rule or metric.

PLAN section 4 controls fidelity: behavior and numbers matter; no original object layout or names are
carried forward. Follow `docs/CONVENTIONS.md`: typed GDScript, exported Resource tuning, fixed-step
determinism, and match-local state owned by a transactional simulation participant.

## 3. Dependencies and blocking interface decisions

| Dependency | Required from that slice | Status / gate |
|---|---|---|
| S1 core | 60 Hz `MatchSim`, seeded `SimRng`, `SimSystem` checked lifecycle/checkpoint/snapshot, `MatchClock`, `MatchFlowConfig`, `MatchTriggers`, `RulesConfig`, `MatchConfig`; staged trigger/flow publication remains inside S1's transaction. | Documented in S1-core. S1's default flow is explicitly a placeholder until S3. |
| S2 physics/contact | Deterministic, immutable per-tick observations sufficient to distinguish ball possession/carrier, current position, kick type and kicker, bounce/touch, restart/try/dead-ball crossings, pass/drop/kick origin, tackle and contact events. | **Blocking contract gap.** S2-physics names physical result values and says typed results are available downstream, but the current S2 public test API candidate describes command results, not this law-observation stream. S3 implementers must not infer these observations by reading scenes, physics servers, mutable S2 internals, or raw event names. Freeze the typed handoff with S2 before implementation. |
| S1/S2 transaction and output API | S3 state, RNG effects, reports and emitted match triggers must roll back and replay with the full tick. Rule outputs must use the S1/S2 committed output path. | **Contract versions need reconciliation.** S1-core says `SystemTickResult` has `{ok,error}`; the S2 public test API candidate adds ordered `outputs`, while S1-test-api still gives the two-field shape. The S2 test API also lists required types as pending. Do not commit an S3 output API that assumes the pending variant. |
| S1/RE pitch frame | One canonical coordinate frame for `PitchGeometry`, S2 observations, reports and RE-derived law positions. | RE 05/07 use z for length, while S1 uses x. Convert `(x_S1, y_S1, z_S1) = (z_RE, y_RE, x_RE)` with signs preserved; this is a coordinate mapping, not a behavior conflict. |
| S4 set pieces | Typed notification for scrum/line-out/ruck/maul completion, infringement, unavailability, collapse and restart completion; S3's award response. | S3 can define the behavior boundary and test doubles. Exact names, timing and event payload are a follow-up S3/S4 interface review, not recovered facts. |
| Phase 1 RE | RE 05 observed/inferred behavior and RE 07 only for explicitly delegated set-piece handoffs. | Do not run further RE for this slice. Carry the unresolved list in §10 into code review. |

### 3.1 Current hard blockers before S3 implementation starts

1. S2 and S3 owners agree and document the immutable observation value, its producer phase, tick
   timing and replay/snapshot behavior. It must expose the facts in the second table row above; an
   S3 implementation must not add a second ball/physics simulation.
2. S1/S2 resolve the `SystemTickResult` output-shape conflict and approve the record path for
   referee events and restart awards. Reports cannot be published before the current sim tick
   commits.
3. S1 resolves variable period lengths or an equivalent clock contract before extra-time periods
   are claimed. Its current clock has one `period_ticks` and one `game_seconds_per_period`, which
   cannot directly encode two 2400-second periods followed by three 600-second periods.
4. S3/S4 agree on restart-award and set-piece-result records before either implementation is
   reviewed. S3 may use test-owned fakes to finish independent rules tests while that interface is
   open.

## 4. Proposed S3 surface (new implementation names)

These names define a proposed clean interface, not an assertion about the original game. Final
source paths and public constructors must be frozen with S1/S2/S4 before implementation.

| Proposed value / owner | Minimum purpose |
|---|---|
| `RulesSystem` (`SimSystem`) | Own match-local referee, advantage, scoring, penalties/cards and rule-observation cursor. Implement checked tick, complete checkpoint/restore and deterministic snapshot. |
| `RulesConfig` (extend S1 Resource) | Export each numeric Classic rule parameter with units, provenance and validation; no tuning literals in the tick. Preserve existing S1 fields and replace the provisional `extra` bag as values are promoted. |
| `RefereeReport` | Typed value for reason, decision, offending team, player when known, incident position, game time and rule flags such as `from_advantage`. Snapshot/copy is detached. |
| `RestartAward` | Typed value for restart kind, mark, awarded team, offending team, throw-in/feed side when applicable, and associated report. S4 consumes it; no set-piece mechanic lives here. |
| `RuleObservationFrame` | S2-owned or jointly approved immutable facts for one candidate match tick. It is the required S2 seam from §3, not a new S3 read of mutable S2 state. |
| `ScoreState` / discipline state | Match-local counters and active sin-bin/card state; never mutate shared `Team` or `PlayerProfile` Resources. |

Every state value that can change a future decision, output, or random draw belongs in the
`RulesSystem` checkpoint and deterministic snapshot. All draws come from the injected `sim.rng`;
no `RandomNumberGenerator`, wall clock, global singleton, scene-tree lookup or system time.
Presentation cues and audio are committed events for the runner/presentation layer, not mid-tick
side effects.

## 5. Rule report and decision pipeline

Implement the observable report pipeline from RE 05 §2.1–2.2:

1. A detector creates a typed report from a committed-tick observation. Its incident time is the
   current game time unless it already has an explicit source time.
2. An advantageable report enters advantage when its detector requests it; other reports are
   submitted directly. Inactive referees ignore submitted reports.
3. If a quick tap/throw option is pending and untaken, pass the report to that option controller;
   do not stop play. Otherwise, a report may require going back to the stored advantage report.
4. Apply the period-end report substitution rules, then resolve the decision into an event and
   `RestartAward`. Reports 15–17 (penalty try/conversion paths) are not swallowed by advantage.
5. Publish the report, whistle, score, restart, discipline and cue events only through S1's
   successful tick publication boundary. The rule state and pending event values must restore on
   retry or replay failure.

`Decision` and `RestartKind` meanings and labels are in RE 05 §2.1. S3 may use different enum names,
but it must preserve the observed decisions: penalty, scrum, free kick/mark, end period, 22 drop-out,
line-out, kick-off, informational kick-at-goal result, penalty try, and conversion. Unknown decision
values and restart kinds remain explicitly unknown; do not route them to a made-up Classic restart.

## 6. Classic behavior required by this slice

### 6.1 Score and kick restarts

- Try: reject while the opposing side owns advantage; reject an offside scorer; otherwise add 5
  points and one try, record try touchdown, and award a conversion.
- Penalty try: credit 5 points and one try to the side opposite the offender; set the mark on the
  attacked try line, whistle, and award a conversion. The exact selected kicker is unresolved.
- Successful conversion adds 2; successful penalty goal adds 3. Both restart with a kick-off by the
  conceding side. Drop goal adds 3 and also restarts by kick-off to the conceding side.
- A missed conversion restarts with a kick-off; conceding side is the inferred Classic default.
  A missed drop goal dead in-goal produces a 22 drop-out. A missed penalty goal dead in-goal to a
  22 drop-out is inferred and remains marked as such.
- Restart handlers emit typed awards; S4 owns the actual set-piece execution. A score/event cannot
  be counted twice if the source event appears again in the same or replayed tick.

### 6.2 Touch and kick-to-touch awards

Use S1 `PitchGeometry` and the observed stadium touchline width. Under the conversion above, RE 05's
halfway `z_RE=0`, try lines `|z_RE|=50`, and 22 m lines `|z_RE|=28` are S1 `x=0`, `|x|=50` and
`|x|=28`. Each team's own 22 follows its S1 x-axis attack direction. RE touch-width x values map to
S1 z values. Do not hard-code touchline width.

| Last play | Condition | S3 award |
|---|---|---|
| Kick-off | Touch before 10 m from halfway (`|x_S1| < 10`; RE `|z_RE| < 10`) | Centre scrum to non-kicking side. |
| Kick-off | Otherwise, on full | Centre scrum to non-kicking side. |
| Kick-off | Otherwise, bounced first | Line-out at crossing; non-kicking side throws. |
| 22 m drop-out | On full | Scrum at kicking side's 22; non-kicking side puts in. |
| 22 m drop-out | Bounced | Line-out at crossing; non-kicking side throws. |
| Penalty kick to touch | Any | Line-out at crossing; kicking/awarded side throws. |
| Open-play kick from eligible own 22 | Kick origin and (for open play) receipt/take both satisfy source rule | Line-out at crossing; emit touch-kick-gain. |
| Open-play kick outside own 22 | On full | No-gain line-out at kick position; emit set-no-gain. |
| Open-play kick outside own 22 | Bounced | Line-out at crossing; emit touch-kick-gain. |
| Goal kick types 5/6 into touch | Any | Goal-kick miss handling; kick-off decision. |
| No kick / carried out | Any | Line-out at crossing to the side that did not carry it out. |

Kick type 3 is explicitly unknown; do not assume a Classic behavior until resolved. Practice/tutorial
mode bypass is documented but this slice has no mode model in S1; keep the bypass behind an explicit
mode input or leave it out of the Classic match test fixture, never infer it from scene names.

### 6.3 Infringements and offside

Implement the observed detection decisions in RE 05 §2.4 only when supplied observations identify
the trigger. The S2 handoff blocker in §3 is material: no test may claim these laws work from physical
motion alone without the required typed input.

- Forward pass: based on the throw's attack-direction component alone, and only when its magnitude
  toward attack exceeds 0.01 m/s. The passer's run speed, receiver and catch are not considered.
- Forward-pass assist: horizontal throw speed at most 8 m/s always bends a would-be forward throw
  to `-0.01 m/s`; faster-throw probability by option is `[0, .5, .6, .7, .8, .9]`. Option ownership is
  unresolved and must remain a required injected setting, not a guessed UI mapping.
- Knock-on: tracked dropped/released ball must bounce, then travel over 0.1 m forward from release
  before a player holds or kicks it. A passer's tracked pass is not a knock-on here. Same dropper
  re-gathers before bounce legally.
- Offside after kick: list teammates strictly ahead of kicker; a listed player becomes onside after
  a non-listed teammate passes him. No open-play 10 m law.
- Formation offside: use the RE 05 offsets: scrum 2.0 m, maul 1.4 m, ruck 0.7 m; penalty/free kick
  retreat line 10 m. Respect the 2.5 m defending scrum-half tolerance. The remaining role
  exemptions are unresolved. Delayed check: 0.2 s after ball leaves formation/maul start; retreat at
  or below `-0.5 m/s` is tolerated, forward motion over `0.1 m/s` or holding is penalised. Clamp
  lines to half-length minus 0.1 m and clear on stop/out.
- Other report mappings are the table in RE 05 §2.4: ruck hands/killing, ruck not used, maul
  collapse, dangerous tackle, slow set piece, scrum offences, mark, defensive grounding and dead
  ball. Preserve observed notice probabilities and decision outcome; keep inferred rows visibly
  provisional.

Do not duplicate S2 tackle/contact legality: S2 emits physical results; S3 applies the law to those
results. S4 emits formation/set-piece outcomes; S3 applies sanctions and restart decisions.

### 6.4 Advantage

- On first eligible report, store report and reset elapsed to zero; emit advantage begin. Offside
  also emits the offside-start event.
- If the non-offender of the stored advantage commits an advantageable offence, go back to the
  original offence immediately.
- If the same side offends again with same decision, replace stored report only when the source
  position comparison succeeds. Exact comparison remains unresolved and cannot be guessed.
  Observed penalty-to-scrum downgrade is represented by `advantage_downgrade_penalty_to_scrum`,
  default `true` for Classic fidelity.
- Compute gain along the non-offending side's attack direction. Go back if the offending side
  takes possession or wins the reported contest. End advantage when gain is strictly greater than
  15 m and the non-offender carries or kicks while ball remains in field of play.
- Apply the observed 25 s pending-stoppage branch and 30 s/no-progress timeout as written in RE 05;
  keep the branch intent marked inferred/unresolved. A period-end report during active advantage
  returns to the original offence.
- On go-back, resolve the original mark and report. Clear advantage before submitting the report so
  it is not re-captured.

### 6.5 Penalties, cards and sin bin

- Penalty choices: kick at goal, punt for touch, scrum or tap-and-run. Free-kick and mark choices:
  punt, scrum or tap-and-run; no kick at goal. The 4th penalty screen button's inferred punt mapping
  remains labelled inferred in data/UI.
- Preserve the offence mark; kick-at-goal spots are inferred to remain at least 5 m from touchline.
  Do not add the absent 15 m-in law to Classic.
- Offending side retreats 10 m; quick penalty/throw reports can remain pending while untaken. A
  new report can supersede a pending quick option as described in RE 05.
- Referee profile table, card pressure, card-roll thresholds, yellow/warning split, repeat-own-22
  chances, front-row exemption, max two players off, second-yellow red, 5% straight-red foul play,
  600 game-second sin bin and return-at-next-stoppage are defined in RE 05 §§2.7/3. Keep the
  depth axis, player-card flag and own-22 team-flag uncertainties explicit.
- Cards take effect at stoppage; red-card players never return. Keep discipline/statistic changes
  match-local and emit events after commit.

### 6.6 Clock, periods and match end

S1 owns the clock and its fixed tick. S3 supplies rule configuration and determines which accepted
stoppages end a period. Never add a second clock.

- Classic regular match: two 2400-game-second periods; real-time option table `[2,5,10,20,40]`
  minutes maps to rates `[20,8,4,2,1]`; default option index 1. Clock advances in the running
  period state during live play and ordinary stoppages, and freezes at the period boundary. It does
  not pause solely for scrums, line-outs, conversions, kick-offs or injuries. Whether a particular
  cut-scene pauses the world is unresolved; S1 currently has no pause API. Kick-off setup's exact
  clock gate remains TBC-RE in S1 and must not be guessed by S3.
- At time up, kick-at-goal results and a scored drop goal end immediately. Only the listed
  ball-dead/scrum or 22, ball-in-touch/line-out, and defensive-grounding/22 reports end on report
  time at or past the boundary. Other stoppages do not. Preserve unresolved second-half gate.
- Half-time swaps ends; inferred second-half kick-off side remains marked inferred.
- Extra time is knockout-only: three 600-second periods, level score required; after third level
  period, begin shoot-out. Golden-point behavior and shoot-out order/positions/sudden-death remain
  unresolved. Do not claim a complete extra-time/shoot-out implementation until the S1 variable
  period contract and those RE facts are resolved.

## 7. Mod and data requirements

Classic RulesConfig is the base. Every recovered numeric value is a typed exported field with units,
default and RE 05 evidence reference. Values listed in RE 05 §§3/5 include points, advantage limits,
clock and period parameters, kick-off minimum, field/22 geometry, forward-pass/knock-on thresholds,
offside offsets, notice probabilities, ruck/lineout time limits, card policy, penalty options and
referee profiles. Mod hooks follow RE 05 §5: decision mapping, period-end policy, advantage policy,
penalty-try policy, penalty option sets, discipline, detection thresholds and time limits.

For base-game parity, test the same rules resources with mods disabled and after enable/disable
round-trip. Do not hard-code values that the declared rule resource or mod hooks own. S3 does not
add presentation or UI strings beyond translation keys/events required by the existing layers.

### 7.1 Referee presentation events

S3 selects a typed cue/speech request from `(reason, decision, committed match event)` and publishes
it only after commit. Presentation/audio systems consume the event; S3 does not load clips or play
audio. `RefereeCueTable` maps reason and decision to cue/caption keys. RE 05 §2.9 gives the observed
cue categories and HUD reason/decision mappings. Referee voice is chosen per match from six
referee nationalities using a weighted table: exclude either team's nation except a shared nation
gets ×20; favor neighbouring nations; allow a French referee only when a French team plays; map
New Zealand, South Africa and Australia to the Australian accent bank. The exact neighbouring
weights and nation/profile rows remain data inputs unless resolved elsewhere.

Speech lines are selected uniformly within the documented category/range, with no anti-repeat or
cooldown. Ruck-formed speech has the observed 80% roll plus its further gate. Unused Colours and
Misc lines are not Classic hooks. No test chooses a specific speech string or requires copyrighted
voice assets; assert only selection category, range, weighting facts and event timing.

## 8. Determinism and rollback acceptance

S3 must fit S1 transactional semantics. A failed system tick, failed flow phase, rejected output
preparation, aborted append or replay-row failure leaves scores, reports, advantage, cards, clock
side effects, pending restart awards, next random draw and snapshots at their exact pre-tick values.
Retry the same sampled input and candidate commands; commit produces one and only one result/event
batch. Direct and runner replay of one log yield equal rule snapshots and score/restart outputs.

Store every active timer as integer match ticks or as the S1-provided exact rational clock delta;
do not derive it from wall time. If a source timer advances in game seconds rather than ticks, its
conversion is explicit and tested against S1's match clock. Rule event ordering is stable and
documented where it affects score, advantage, restart or seeded RNG draws.

## 9. Exit criteria

S3 is reviewable for merge when:

1. §3 blockers 1–2 are resolved in committed S1/S2 API documents; S3/S4 restart records are
   agreed or S4 consumes the S3 published value contract.
2. The Classic 80-minute match, scoring, legal restart selection, advantage, accepted reports and
   card/sin-bin behaviors pass the independent test inventory.
3. Rule state, reports, events, RNG and score state are transactional, snapshot-complete,
   deterministic across replay, and published only after tick commit.
4. All O numeric values are data-driven, and every I/U item is marked in code/data and tests.
5. RE positions are converted to S1 coordinates using §2 with signs preserved. No S3 test relies
   on original assets, binary names/data layouts, scene-tree order or guessed RE facts. Full
   extra-time/shoot-out acceptance is gated as described in §6.6.

## 10. Unresolved RE facts carried forward

Keep these visible in implementation and acceptance reports; use `docs/re/05-rules.md` as the source
of truth and do not resolve them by selecting a plausible law:

- Advantage 25-second branch intent and same-decision mark comparison; SecuROM runtime-keyed calls.
- Unknown decision/reason/restart enum values; whether period clock pauses during cutscenes/set-piece
  setup; second-half period-end gate.
- Golden-point early stop and shoot-out format; extra-time eligibility competition ID; second-half
  kick-off selection (inferred).
- Exact mark trigger conditions; penalty-try kicker selection; lineout's unexplained 4.0 team field.
- Forward-pass assist option owner; goal-kick type 3 behavior; goal-kick missed in-touch handling.
- Offside formation role exemptions; referee severity interpretation and the source of strictness
  level where the RE labels it inferred.
- Card eligibility flag, own-22 counter team flag and depth axis; exact penalty fourth-option UI
  label; penalty-goal dead-in-goal outcome is inferred.
- S2 law-observation frame, S1/S2 output API shape, S4 handoff schema and S1 variable-period clock
  capability are implementation-contract dependencies, not RE discoveries. Convert positions by
  the explicit axis mapping in §2.
