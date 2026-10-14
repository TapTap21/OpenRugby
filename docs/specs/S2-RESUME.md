# S2 implementation resume

## Current contract decisions

- **Fatigue snapshot timing:** S2 consumes the owning player/match layer's immutable fatigue snapshot captured at the beginning of the 60 Hz tick, before that owner advances its fatigue time for the tick. This is an S2 integration contract, not a recovered caller order. It follows RE 09 §2.3's per-frame `fatigue += dt_match` and the S2 ordered tick contract's “capture” before movement; the owner must publish the next value only after S2 has consumed the current one. S2 never advances fatigue time.
- **Initial sprint energy:** no standalone numeric Classic default is assigned. The owner must inject an initial fatigue snapshot before locomotion is usable, including energy cap and starting energy. RE 06 §2.9 clamps the pool to `[−1, E_max]`; RE 09 §2.3 supplies `E_max` as a function of Stamina and fatigue time. At a new match, the owning layer must initialize fatigue time to its observed new-player value and calculate the corresponding energy; without that injection, S2 reports the player state as unresolved and does not fabricate a value.
- **Clock boundary:** locomotion integrates at S1's 60 Hz (`dt=1/60`) using per-second rates derived from RE 06's 50 Hz actor model. The separate set-piece 50 Hz / 60 Hz motion playback question remains open (RE review C11); S2 does not convert it.
- **Ball solver:** integer accumulator adds 200 against threshold 60 only when the post-action ball is free-flight/rolling and match lifecycle is active. Held/attached/frozen paths leave ball state and accumulator unchanged. This is the explicit provisional S2 policy from S2 spec §3–4, not recovered Classic gating.
- **Mod composition:** Classic defaults and modded matches instantiate the same S2 system set. S2 data is supplied through typed Resource references; no alternate Classic/mod implementation path.

## Progress

- Read root `AGENTS.md`, PLAN §§2b/4, conventions, ADR-001/004, S2 spec, RE 06, and RE 09.
- Confirmed S1 provides ordered `SimSystem` registration, deterministic per-system snapshots, `MatchRunner` composition hooks, and typed extension point registry. S1 has no player fatigue snapshot service yet.
- Next: add typed S2 runtime values, parameter Resources and deterministic systems; wire extension points and the mandatory S2 system bundle into MatchRunner; then run format/lint/hygiene gates (never Godot without safety script).

## Unresolved implementation gaps to track

- S1 has no player/team roster match-state or fatigue owner yet. S2 inputs must remain typed/injected; no profiles or fatigue values are fabricated.
- PID gains, pass/catch candidate policy and mappings, wind policy, several tackle action bindings, place-kick meter, and contact geometry provider remain unresolved per S2 spec §8. Dependent paths must report unavailable until injected.
- Deterministic geometry input is synthetic/injected; stadium collision mesh integration is outside this slice's available S1 state.

## Implemented checkpoint

- Added S2 typed Resources and Classic `.tres` defaults for ball, kicks, locomotion, passes, catches, tackle values and pitch-surface rows.
- Added `MatchStateDef.simulation_active`; the Classic flow marks kickoff/in-play/stoppage simulation-active. The flow owner decides lifecycle activity through data. S2 solver still gates on free-flight/rolling ball mode after earlier systems have run.
- `MatchRunner` registers S2 in this fixed tail order after caller base systems and declared provider systems: `s2_locomotion` → `s2_ball_physics` → `s2_interactions`. The base/provider systems therefore prepare inputs/actions before the ball solver; interactions publish typed outcomes after it. Both Classic and modded runs use this same tail.
- The accumulator starts at 0, adds 200 only at the active/free-ball gate, subtracts threshold 60 per 0.005 s step, and is included in the ball system snapshot. Ball pose, velocities, mode, tuning values, wind inputs, pitch selection, pending contacts, outputs and diagnostics are snapshotted. MatchSim already snapshots its shared RNG state.
- Added force/drag, orientation-projected ellipsoid area, ground-plane contact, deterministic contact ordering/cap, pitch restitution/friction, predictor, kick/pass builders, pickup/fumble formulas, standard tackle/break and big-hit formulas, spill results, and declared extension points. Hooks validate result types and bounds before use.

## Remaining integration gaps

- `BallContactSource` is the typed deterministic mesh-contact interface; the stadium mesh decoder/provider is absent. Only ground-plane ellipsoid contact is detected in this slice. Callers may inject deterministic contacts; no PhysicsServer/Jolt queries are used.
- Contact response currently resolves translational normal and Coulomb friction impulses. The full multi-contact LCP and angular impulse solve are not implemented. Rolling/twist torque is left visibly unresolved because RE 06 does not recover its form.
- No S1 roster/fatigue owner exists. Locomotion requires per-player stats, sprint request/urgency, fatigue snapshot (captured pre-advance), fatigue option and pitch condition. Until injected, it records unresolved inputs and does not update that player. Turn PID gains and the S9 action-to-motion mapping remain unresolved.
- Ball mode and goal-kick state, locomotion initial state and sprint request, environment pitch/stadium values, fatigue option and player fatigue snapshots begin explicitly unresolved. Their owners must inject these before dependent behavior runs.
- The pure kick/pass builders and ball commit methods are available, but no S1/S9 action queue currently connects user actions to them. Unknown pass type/target-height mappings, catch gate/candidate selection, place-kick meter output and tackle action mappings remain unavailable until owning callers inject them.
- The initial sprint-energy rule is injection-only. RE 06 establishes the runtime cap/clamp; RE 09 gives the energy curve, but neither spec establishes initial fatigue-time initialization at match construction. S2 does not infer a full-energy start.
- The 50 Hz set-piece / 60 Hz motion playback relationship (RE review C11) remains open. S2 uses 1/60 s rates for locomotion and does not translate the other clock.

## Verification status

- `gdlint`, `gdformat --check --line-length 100` and `scripts/hygiene.sh` passed.
- After `scripts/check-godot-safe.sh`, a Godot 4.7.2 headless editor scan reported no script parse errors. It did log existing missing `localization/translations.en.translation`, socket creation failures, and an unwritable global editor settings path; the editor could not save those global settings.
- No tests were authored or read. The test suite was not run.
