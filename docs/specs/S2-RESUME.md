# S2 implementation resume

## Current contract decisions

- **Fatigue snapshot timing:** S2 consumes the owning player/match layer's immutable fatigue snapshot captured at the beginning of the 60 Hz tick, before that owner advances its fatigue time for the tick. This is an S2 integration contract, not a recovered caller order. It follows RE 09 §2.3's per-frame `fatigue += dt_match` and the S2 ordered tick contract's “capture” before movement; the owner must publish the next value only after S2 has consumed the current one. S2 never advances fatigue time.
- **Initial sprint energy:** no standalone numeric Classic default is assigned. The owner must inject an initial fatigue snapshot before locomotion is usable, including energy cap and starting energy. RE 06 §2.9 clamps the pool to `[−1, E_max]`; RE 09 §2.3 supplies `E_max` as a function of Stamina and fatigue time. At a new match, the owning layer must initialize fatigue time to its observed new-player value and calculate the corresponding energy; without that injection, S2 reports the player state as unresolved and does not fabricate a value.
- **Clock boundary:** locomotion integrates at S1's 60 Hz (`dt=1/60`) using per-second rates derived from RE 06's 50 Hz actor model. The separate set-piece 50 Hz / 60 Hz motion playback question remains open (RE review C11); S2 does not convert it.
- **Ball solver:** integer accumulator adds 200 against threshold 60 only when the post-action ball is free-flight/rolling and match lifecycle is active. Held/attached/frozen paths leave ball state and accumulator unchanged. This is the explicit provisional S2 policy from S2 spec §3–4, not recovered Classic gating.
- **Mod composition:** Classic defaults and modded matches instantiate the same S2 system set. S2 data is supplied through typed Resource references; no alternate Classic/mod implementation path.

## Progress

- Read root `AGENTS.md`, PLAN §§2/2b/4, conventions, ADR-001/004, S2 spec, RE 06, and RE 09.
- Confirmed S1 provides ordered `SimSystem` registration, deterministic per-system snapshots, `MatchRunner` composition hooks, and typed extension point registry. S1 has no player fatigue snapshot service yet.
- S2 runtime values, parameter Resources, deterministic systems and extension points are implemented at the requested baseline; this blocker-fix round leaves Classic contact unavailable behind required geometry/solver injection.

## Unresolved implementation gaps to track

- S1 has no player/team roster match-state or fatigue owner yet. S2 inputs must remain typed/injected; no profiles or fatigue values are fabricated.
- PID gains, pass/catch candidate policy and mappings, wind policy, several tackle action bindings, place-kick meter, and stadium contact geometry remain unresolved per S2 spec §8. Dependent paths must report unavailable until injected.

## Implemented checkpoint

- Added S2 typed Resources and Classic `.tres` defaults for ball, kicks, locomotion, passes, catches, tackle values and pitch-surface rows.
- Added `MatchStateDef.simulation_active`; the Classic flow marks kickoff/in-play/stoppage simulation-active. The flow owner decides lifecycle activity through data. S2 solver still gates on free-flight/rolling ball mode after earlier systems have run.
- `MatchRunner` registers S2 in this fixed tail order after caller base systems and declared provider systems: `s2_locomotion` → `s2_ball_physics` → `s2_interactions`. The base/provider systems therefore prepare inputs/actions before the ball solver; interactions publish typed outcomes after it. Both Classic and modded runs use this same tail.
- The accumulator starts at 0, adds 200 only at the active/free-ball gate, subtracts threshold 60 per 0.005 s step, and is included in the ball system snapshot. Ball pose, velocities, mode, tuning values, wind inputs, pitch selection, pending contacts, outputs and diagnostics are snapshotted. MatchSim already snapshots its shared RNG state.
- Added force/drag, orientation-projected ellipsoid area, ground-plane contact, deterministic contact ordering/cap, pitch response inputs, predictor, kick/pass builders, pickup/fumble formulas, standard tackle/break and big-hit formulas, spill results, and declared extension points. Hooks validate result types and bounds before use.

## Current blocker-fix status

- `BallPathPredictor` now selects the later/descending root, repeats bounce segments while time remains, switches to rolling only after the first segment when hop time is below 0.01 s, and caps rolling advancement at `min(remaining, 1.25)`. This remains separate from the rigid-body solver.
- The public hook payload is `ContactResult`; detector identity/geometry lives in `BallContact`, while the result carries separate restitution, friction and rolling-response values. Hook attempts to change identity are rejected; response values are checked against S2 §5 bounds.
- Pending contact snapshots now include exact point, normal and penetration values plus every stable identity field, alongside the quantized sort key and derived restitution, friction and rolling response. Surface and solver inputs are snapshotted separately.
- `MatchRunner.start()` requires injected, available `BallContactSource` and `BallContactSolver`; missing or base-unimplemented dependencies return `ERR_UNCONFIGURED`. No Classic stadium mesh provider or justified LCP solver exists here. Contact steps roll back their state and accumulator if an injected solver declines the rows. The Classic contact path is unavailable until both owners are supplied; scalar reflection/damping has been removed.
- Contact processing follows sort → response construction/hook → injected solve → post/crossbar classification. Classifier gates use the RE envelope (within 5 m of either goal line and |x| < 5 m); crossbar uses |y−3| < 0.3 m and |x| < 2.5 m, then pad/upright split at y=2.26 m.
- Catch selection remains unavailable until the interaction owner injects typed selected/no-candidate and gate states to `resolve_catch`; the system does not select a candidate or infer the unresolved gate. Provisional values remain caller/fixture supplied.

## Remaining integration gaps

- The stadium collision mesh decoder/provider and a behaviorally justified normal/friction/rolling LCP solver are absent. The new runner dependencies are injection points, not claims of Classic fidelity. No PhysicsServer/Jolt queries are used.
- No S1 roster/fatigue owner exists. Locomotion requires per-player stats, sprint request/urgency, fatigue snapshot (captured pre-advance), fatigue option and pitch condition. Until injected, it records unresolved inputs and does not update that player. Turn PID gains and the S9 action-to-motion mapping remain unresolved.
- Ball mode and goal-kick state, locomotion initial state and sprint request, environment pitch/stadium values, fatigue option and player fatigue snapshots begin explicitly unresolved. Their owners must inject these before dependent behavior runs.
- The pure kick/pass builders and ball commit methods are available, but no S1/S9 action queue currently connects user actions to them. Unknown pass type/target-height mappings, catch gate/candidate selection, place-kick meter output and tackle action mappings remain unavailable until owning callers inject them.
- The initial sprint-energy rule is injection-only. RE 06 establishes the runtime cap/clamp; RE 09 gives the energy curve, but neither spec establishes initial fatigue-time initialization at match construction. S2 does not infer a full-energy start.
- The 50 Hz set-piece / 60 Hz motion playback relationship (RE review C11) remains open. S2 uses 1/60 s rates for locomotion and does not translate the other clock.

## Verification status

- `gdlint .`: PASS — `Success: no problems found`.
- Targeted `gdformat --check --line-length 100` on 30 changed GDScript files: PASS — `30 files would be left unchanged`.
- `scripts/hygiene.sh`: PASS — `hygiene: ok`.
- `git diff --check`: PASS — exit 0, no output. New files also passed `git diff --no-index --check /dev/null <file>` with no output.
- Git staging was unavailable: `git add -A` could not create `.git/worktrees/s2-implementation/index.lock` because the filesystem is read-only; an orchestrator with writable Git metadata must commit this slice.
- No tests or Godot commands were run. Independent test API reconciliation is still incomplete.
- No Godot invocation was made, so no safety-gate/invocation pair applies.

## Runtime composition and replay update

- `MatchCompositionBuilder.build()` is the shared entry point for `MatchRunner.start()` and
  `MatchReplay.run()`. It applies the same extension setup and system order: caller systems,
  extension systems, `s2_locomotion`, `s2_ball_physics`, then `s2_interactions`.
- `MatchBuildResult` carries a typed `MatchReadinessReport`. Missing match setup, stadium geometry,
  contact solver, wind policy, ball initialization, player/fatigue inputs, replay-safe hooks, or
  restorable systems/dependencies remain start blockers. `MatchRunner` and `Main` expose the report.
- Callers inject setup and enqueue `S2RuntimeCommand` values through `S2RuntimePort`; outputs are
  `S2RuntimeResult` values tied to command sequence numbers. The port has no scene or `Node` API.
  S2 accepts already-resolved owner values and does not infer action mappings, pass paths, catch
  selection, fatigue, weather policy, or goal-kick rules.
- A caller must initialize ball body pose, `BallMode`, and `GoalKickState` before the first tick.
  Ordinary play is explicitly supplied as `GoalKickState.OFF`; an active goal kick needs an explicit
  wind policy. No default state is applied to unblock launch.
- Replay format v2 stores per-frame command inputs and typed outputs and adds a setup fingerprint
  to `ReplayHeader`. The fingerprint covers effective config/resources, caller and extension system
  setup, ordered extension configuration, action-layout and mod hashes, ball/player/environment
  setup, contact providers, resolved wind policy, and tick rate. Replay rejects older headers and
  mismatched fingerprints.
- Tick execution checkpoints every injected system, contact source and contact solver, ball and
  player state, `SimRng`, queued commands, prior outputs and sequence state. A rejected command or
  failed later solver substep restores the complete pre-tick state. Injected dependencies must
  explicitly declare statelessness or implement complete snapshot/checkpoint/restore contracts.
- This is runtime composition plumbing, not a complete runnable Classic match. The Classic stadium
  geometry provider and contract-complete normal/friction/rolling LCP solver remain unavailable.
  Player/fatigue/action-owner inputs also must be supplied, and no fallback contact or damping path
  is provided. Tests remain unrun until independent test API reconciliation is complete.

These checks do not establish merge readiness. The geometry provider, contract-complete LCP solver,
and caller-owned action/player inputs remain unavailable, and tests are still gated on independent
test API reconciliation.
