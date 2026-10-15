# S3 slice: score, conversion, kickoff, and time-up reports

Status: contract proposal; no S3 production implementation is included.
Scope: the smallest restart-to-score loop that can be supported by the current
rules evidence, plus the period-end whitelist needed to finish a match period.
This is not a playable match specification. The current S2 port does not yet
publish try-grounding or kick-at-goal event facts, and the required S4 place-kick
path is not available.

## 1. Boundaries and dependencies

This slice begins when an upstream rules input already represents a valid try,
or a completed conversion attempt. It does not implement movement, contact,
grounding detection, offside detection, kick physics, AI, camera, or cut-scenes.

Required upstream contracts before this slice can run in a real match:

1. **S1 match clock and match flow** provide authoritative game time, period
   index/end time, running/time-up/ended state, fixed-step order, staged events,
   and period transition ownership. S1 currently defines these flow concepts in
   `docs/specs/S1-core.md` §2.6–2.8 but still contains placeholder flow rows.
2. **S2 event bridge** publishes a deterministic typed physical fact when the
   ball is grounded in the opponent in-goal (team/player/position) and a
   completed kick result. S2 reports physical facts only; S3 owns offside,
   advantage and try legality. The current S2 runtime result types cover
   launch/pass/catch/pickup/tackle outputs, not grounding, kick scoring, or
   referee reports (`docs/specs/S2-physics.md` §3–7; current `S2RuntimeResult`
   has no corresponding payload).
3. **S4 place-kick** owns the conversion set-up and attempt mechanics. S3
   consumes its typed completed result and decides points/restart/period
   consequences; S3 must not recreate kick mechanics.
4. **Match setup** supplies stable team IDs, attack direction, score state,
   period rules and `RulesConfig`. The player/team identity must be stable for
   replay and snapshots.

Until those contracts exist, the loop can be tested only by injecting the typed
events in §4. A production runner must mark the path unavailable if any required
provider is missing; it must not fabricate a grounding, kick result, score, or
restart.

## 2. Behavioural contract

### 2.1 Try report and score

When the referee is active and receives an eligible try-grounding fact, it
checks the precedence described by RE 05 §2.3: an advantage being played for the
opponents sends play back to the original offence; an offside scorer produces
the offside decision; otherwise the try is awarded. Only the awarded-try path
increments the scoring team's try counter by one (+5 points) and submits a
`TRY / CONVERSION` report. The report goes through the normal report pipeline
and establishes a conversion restart. No kickoff follows the try directly.

Evidence: `docs/re/05-rules.md` §2.3, function `0x4308e0` (`local:rd 0x4308e0`);
report submission `0x439550` (`ev_6d6f5a1da8ae3eaf548fe63621b942d5da0e1a815d916bc880a1ddef462ca95f`);
report handling `0x439e90` (`local:rd 0x439e90`); scoreboard counters
`0x632c60` (`ev_d3541098b1ede857809da67b8eb8eab75b7f6c8578304ed55907e83f3fbb031b`).

### 2.2 Conversion result and restart

S4 submits one completed conversion result to S3. On success, add one
conversion and +2 points to the scoring team. On success or miss, the following
restart is a kickoff assigned to the opponent of the scoring team. The
successful-conversion restart is observed; the missed-conversion team
assignment is inferred by RE 05 §2.3 and remains behind an explicit policy
setting pending confirmation. This slice does not define conversion spot,
attempt eligibility, meter, kick trajectory, or what physical result counts as
success; those inputs belong to S4/S2 and remain prerequisites.

If the referee is already in time-up state because the clock reached the period
end, the conversion result ends that period on either success or miss. A try
scored after time-up still gets its conversion attempt. Thus a try report alone
must not be rewritten to end-period.

Evidence: `docs/re/05-rules.md` §§2.3, 2.8, acceptance cases 6–7; successful
goal-attempt handler `0x430b30`; period-end predicate `0x439700` (`local:rd
0x439700`); period transition handler `0x43baf0`.

### 2.3 Time-up report gate

The clock reaching its current period end changes the referee to `TIME_UP` and
freezes game time at that end. It does **not** itself end the period. Continue
play and process reports through the usual order: stamp report time if absent,
resolve quick option/advantage precedence, then apply the time-up predicate,
then handle the resulting report/restart. If advantage sends play back, award
the stored offence first; do not end the period solely because time is up.

For the scoped Classic policy, while `TIME_UP`:

| Incoming report | Period ends? | Result |
|---|---:|---|
| Kick-at-goal result (success or miss; why 1/2) | Yes | End period immediately |
| Scored drop goal (why 3) | Yes | End period immediately |
| Ball dead/unplayable, why `0x11`, with scrum or 22 m decision | Yes, if report time ≥ period end | End period; do not play that restart |
| Ball in touch, why `0x12`, with lineout decision | Yes, if report time ≥ period end | End period; do not play that restart |
| Defensive grounding in-goal, why `0x2d`, with 22 m decision | Yes, if report time ≥ period end | End period; do not play that restart |
| Try report | No | Award try if otherwise legal; take conversion |
| Penalty, free kick, knock-on/forward-pass scrum, any other report | No | Handle ordinary decision and continue play |

The period-end check's additional second-half referee gate is unresolved.
Until resolved, this slice must expose a policy hook and must not silently assume
whether a tied second half enters extra time. The broader extra-time qualification,
kickoff selection, shoot-out, and golden-point rules are outside this slice.

Evidence: `docs/re/05-rules.md` §§2.2, 2.8 and acceptance cases 4–7, 12;
clock tick `0x632f10`, period-end predicate `0x439700` (`local:rd 0x439700`),
period transition `0x43baf0`. The second-half gate is explicitly unknown in
§7.6. Time pausing inside cut-scenes is also unresolved (§7.1); the clock's
known contract is to run during stoppages and freeze at the period end.

## 3. Proposed public data types

These are rebuild-owned contracts, not a mirror of the original data layout.
Persist only values needed to reproduce future simulation. Avoid `Variant`
fields and string-encoded team identities.

### `RefereeReport` (plain deterministic value)

- `reason: StoppageReason`
- `decision: RefereeDecision`
- `offending_team_id: StringName` (stable ID; try report records the scoring side per
  RE 05 §2.1)
- `player_id: StringName` (`&""` only for a report with no actor)
- `position: Vector3`
- `has_report_time: bool`
- `report_time_game_seconds: float`
- `from_advantage: bool`

When `has_report_time` is false, S3 stamps the current match game time once at
submission. When true, preserve the supplied recorded time. Validation rejects
non-finite time/position, unknown enum values and missing team identity where
the decision requires one.

For this slice, public enum values must preserve the observed numeric identities
from RE 05: `StoppageReason.TRY = 4`, `KICK_AT_GOAL_IN = 1`,
`KICK_AT_GOAL_OUT = 2`, `DROP_GOAL_SCORED = 3`, `BALL_DEAD = 0x11`,
`BALL_IN_TOUCH = 0x12`, and `DEFENSIVE_GROUNDING_IN_GOAL = 0x2d`;
`RefereeDecision.CONVERSION = 16`, `END_OF_PERIOD = 5`, `SCRUM = 3`,
`KICK_OFF = 9`, `LINEOUT = 8`, and `DROP_OUT_22 = 6`. Use named enums in
rebuild code, not integer comparisons. Other numeric meanings remain governed
by `docs/re/05-rules.md` and are outside this slice.

### `ScoreCounters` and `MatchScore`

`ScoreCounters` carries non-negative integer `tries`, `conversions`,
`penalty_goals`, and `drop_goals`. `points_total(config: RulesConfig) -> int`
computes `tries * points_try + conversions * points_conversion +
penalty_goals * points_penalty_goal + drop_goals * points_drop_goal`.
Classic defaults are 5/2/3/3 from RE 05 §1 Q3 and §3. The counters are
authoritative; cached total points are not independently mutable.

`MatchScore` owns one `ScoreCounters` per stable team `StringName`, returns detached
read-only snapshots, and supports a validated atomic increment. It does not
derive points from the score display.

### `ConversionResult`

- `team_id: StringName` (team attempting the conversion)
- `scorer_id: StringName`
- `outcome: Outcome { SUCCESS, MISS }`
- `attempt_id: int` (stable monotonic ID to reject duplicate result delivery)
- `game_time_seconds: float`

This is an S4-produced completed outcome. S3 validates that one conversion is
pending for the same team, applies score only once on success, and assigns the
opponent kickoff on either outcome.

### `RestartAssignment`

- `kind: RestartKind`
- `team_id: StringName`
- `position: Vector3`
- `cause: RefereeDecision`

For a successful conversion, RE05 observes the restart as `KICK_OFF`, with
`team_id` equal to the opponent of the try-scoring team. RE05 says to assume
that same conceding-team kickoff after a missed conversion, so miss assignment
is an explicit inference, not a confirmed observation. Keep the Classic miss
assignment behind a named policy setting until confirmed. Kickoff position is
owned by the kickoff/set-piece contract; do not infer a spot in S3.

### `PeriodEndPolicy` and transition output

`PeriodEndPolicy.should_end(report: RefereeReport, period_state: PeriodState,
period_end_game_seconds: float) -> bool` encodes the evidence-backed whitelist
in §2.3, with an injected second-half gate provider. Its result is one typed
`RefereeOutcome` containing exactly one of: `report_handled`, `restart_assigned`,
or `period_end_requested`. Mutations to score, pending conversion, report,
restart and period state must be staged together in the S1 transaction; publish
notifications only after the owning match tick commits, per S1-core §2.7.

## 4. Ordered integration points

The deterministic match tick must provide these inputs to S3 in one defined
owner order:

1. S1 supplies current game time, period state/end, and pending transition
   boundary.
2. S2 publishes its committed physical facts/results. S3 may consume only
   facts whose tick committed; a rolled-back S2 tick cannot score.
3. S4 publishes a completed conversion result after its kick attempt resolves.
4. S3 consumes referee reports in submission order, resolving quick options and
   advantage before the time-up gate, then staging report effects/restart or
   period-end request.
5. S1 commits the simulation row; only then are `try_awarded`,
   `conversion_resolved`, `restart_assigned`, or `period_end_requested` events
   published to presentation/flow consumers.

No existing S2 command/result event currently supplies items 2 or 3. The exact
S1/S2 staged-event adapter must be settled in the integration spec before
production wiring.

## 5. Acceptance cases

These cases define the slice independently of implementation. Use fixed match
IDs, injected event facts, deterministic tick time and `RulesConfig` fixtures.

1. **Ordinary try:** with team A attacking +Z, an eligible grounded try by A
   increments A's try count once and total by 5; creates one pending conversion
   for A; assigns no kickoff yet.
2. **Try invalidated by advantage:** if the opponents' advantage is active, the
   same grounding fact awards no try and routes the stored report through the
   go-back path.
3. **Offside scorer:** if the injected scorer eligibility says offside, do not
   increment score; submit the offside outcome instead.
4. **Conversion success:** after A's pending conversion, a successful result for
   A adds exactly one conversion (+2), clears that pending conversion, and
   assigns kickoff to B.
5. **Conversion miss:** a miss changes no score, clears the pending conversion,
   and assigns kickoff to B under the explicit RE05 §2.3 assumption. Keep the
   assignment isolated behind policy so this case can change if runtime evidence
   disproves the inference.
6. **Duplicate conversion result:** replaying the same `attempt_id` cannot add
   another 2 points or assign a second restart.
7. **Wrong team/no pending attempt:** reject the result without changing score,
   referee state, or restart.
8. **Clock reaches end:** while in `RUNNING`, advancing to the end clamps game
   time and enters `TIME_UP`; it does not end the period or emit period-ended.
9. **Try at time-up:** award an otherwise eligible try (+5), stage conversion,
   and remain in `TIME_UP` until conversion result.
10. **Conversion at time-up:** either success (+2) or miss ends the period
    immediately and assigns no kickoff.
11. **Qualifying report:** time-up plus `0x12/LINEOUT` at or after period end
    requests period end and does not assign the lineout restart. Equivalent
    cases for `0x11` with scrum/22 and `0x2d` with 22 pass.
12. **Kick result reports:** time-up plus why 1/2 ends immediately regardless
    of report time; a scored drop goal why 3 also ends immediately.
13. **Non-qualifying report:** time-up plus knock-on/forward-pass scrum,
    penalty, or free kick handles the ordinary restart and leaves state
    `TIME_UP`.
14. **Advantage precedence:** if a qualifying time-up report triggers go-back
    while an advantage is active, the stored report is awarded first; the
    qualifying report does not end the period.
15. **Second-half uncertainty:** the policy provider's unresolved result makes
    the second-half period transition unavailable/explicitly unresolved; code
    must not guess extra-time eligibility or turn a draw into full time.
16. **Determinism/rollback:** identical seeded setup and injected facts produce
    identical snapshots; any failed tick rolls score, attempt ID, pending
    conversion, restart and staged events back together.

## 6. Mod hooks

All hooks run through the existing base mod layer and must participate in the
match replay identity. Classic defaults remain the unmodified baseline.

- `RulesConfig` data overrides for points values, period lengths, conversion
  eligibility policy, and kickoff setup configuration.
- `period_end_policy(report, period_state, period_end_time)` for law mods. Its
  Classic implementation uses the §2.3 whitelist and the explicit unresolved
  second-half gate.
- `try_award_policy(grounding_fact, match_context)` for alternate try-grounding
  laws; the base uses the S2-provided legal eligibility facts.
- `conversion_result_policy(attempt, typed_kick_result)` for alternate scoring
  law outcomes. Kick physics and attempt controls remain owned by S2/S4.
- Read-only events after tick commit: `try_awarded`, `conversion_resolved`,
  `restart_assigned`, and `period_end_requested`. Mods cannot mutate the
  already-committed outcome through these notifications.

## 7. Explicit unknowns / deferred scope

- S2 does not yet emit legal grounding or completed goal-kick facts, and no
  S4 conversion attempt API exists; this is the immediate implementation
  blocker.
- The period-end predicate has an unknown extra second-half referee gate
  (`docs/re/05-rules.md` §7.6); expose it as unavailable until evidence resolves
  it.
- Whether scoring cut-scenes pause world time is unresolved (`§7.1`). The
  clock still advances during ordinary stoppages; do not add a pause based on
  presentation guesses.
- Exact conversion restart position/setup, goal-attempt miss classification,
  and how the conversion result is emitted from the kick subsystem must come
  from S4/S2 integration.
- Advantage's comparison of repeated same-side reports and pending-stoppage
  timeout remain unresolved (`§7.3`); this slice must reuse the already
  specified tracker contract and preserve its unknown policy values.
- Second-half kickoff team, extra-time qualification, extra-time golden-point
  behavior, and shoot-out sequence are outside scope (`§7.5`, §7.11).

## 8. Evidence index

- `docs/re/05-rules.md` §2.1 report fields and §2.2 pipeline;
  `0x439550` / `ev_6d6f5a1da8ae3eaf548fe63621b942d5da0e1a815d916bc880a1ddef462ca95f`.
- `docs/re/05-rules.md` §2.3 try, goal result and kickoff behavior;
  `0x4308e0`, `0x430b30`, `0x430dd0`.
- `docs/re/05-rules.md` §§2.8 and 6 cases 4–7, 12–13;
  `0x632f10`, `0x439700` (`local:rd 0x439700`), `0x43baf0`.
- Scoreboard `0x632c60` / `ev_d3541098b1ede857809da67b8eb8eab75b7f6c8578304ed55907e83f3fbb031b`.
- Open unknowns: `docs/re/05-rules.md` §7 items 1, 3, 5, 6, 11.
