# S2: ball physics, locomotion and contact primitives

- Slice: S2. Depends on S1 core, S1 mod loader, S9 input, and Phase 1 specs
  [06 physics](../re/06-physics.md) and [09 players](../re/09-players-teams-db.md).
- Architecture: [ADR-001](../adr/ADR-001-fixed-tick.md),
  [ADR-004](../adr/ADR-004-core-architecture.md).
- Reimplementation: carry over observable behaviour and numeric constants only. Do not mirror
  original names, layouts, update order, or engine internals.
- Defaults: Classic parameters and behavior are the base Resources (“mod zero”). Mods may patch
  those Resources or register declared hooks. Both modes instantiate and tick the same S2 systems.

This brief separates the 60 Hz match clock from the 200 Hz ball solver. It includes physical
tackle contest/break/spill outcomes because the PLAN Phase 3 table assigns “Opus (tackle
resolution)” to S2. S3 owns legality, infringement classification, advantage, whistle and restart
decisions; S2 reports a physical contact result and does not decide whether the tackle was legal.

## 1. Scope and dependencies

### In scope

- Ball rigid-body state, 200 Hz substep scheduling, gravity, goal-kick-only aero, contacts,
  surface response, post-hit classification, kicks, pass flight, catch/fumble, and pickup.
- Ball path prediction used by AI/catching, kept distinct from the rigid-body model.
- Player run/sprint speed, acceleration, heading/desired-speed state required by the RE model,
  and the match-local sprint-energy pool. The player/match layer supplies fatigue time and
  fatigue-adjusted skill inputs.
- Physical tackle contest outcomes, break chance, big-hit eligibility, and ball spill.
- Typed Resources for every gameplay tuning value; stable, deterministic simulation snapshots.
- S2 extension points for the behaviors named in RE 06 §5.

### Not in scope

- Referee laws, tackle legality, high-tackle penalty/card decisions, knock-on classification,
  offside/interference decisions, scoring, or restart selection (S3).
- Ruck/maul/scrum/lineout mechanics and goal-kick meter (S4).
- AI decisions, camera/presentation, animation clip selection, or stadium asset decoding.
- Out-of-bounds decisions (S3).
- Exact actor PID gains and unresolved physical mappings listed in §8. No guessed numeric behavior
  may be presented as recovered Classic behavior.

### Inputs and ownership

- `MatchSim` supplies integer match tick, current `InputFrame`, previous-frame-derived edges, its
  seeded `SimRng`, and ordered `SimSystem` calls. S2 reads no `Input`, `Time`, global RNG, autoload,
  scene tree or wall clock.
- S2 reads `PlayerProfile`/`PlayerAttributeSchema`, `Team`, deterministic collision geometry,
  `RulesConfig`, and `MatchConfig` resources from S1. For each player, the player/match layer also
  supplies the authoritative read-only fatigue time keyed by team and shirt, plus fatigue-adjusted
  skill inputs for pass/tackle queries. Its immutable per-player fatigue snapshot contains
  `fatigue_time`, fatigue-derived energy cap and energy percent, and the effective Passing/Tackling
  values for that tick. The owner computes effective Passing as `max(0, base_passing -
  floor((100-P)/3))` and effective Tackling as `base_tackling - floor((100-P)/2)`, where `P` is RE
  09's energy percent, applying the owning query's clamp if any. S2 consumes these query values as-is
  and does not reapply penalties.
  Fatigue time advances only in its owning layer by `dt_match`; S2 neither stores nor advances a
  second fatigue timer. S2 owns a separate match-local sprint-energy pool, updated by its locomotion
  model and capped using the injected fatigue-derived energy limit. Match-local mutable state
  belongs to S2 systems/state objects, never to shared profile Resources.
- S2 emits typed results through system output/queued match triggers. It does not call the EventBus;
  `MatchRunner` relays cross-feature events after the full tick.
- Each player-owned interaction command carries a stable `actor_id` supplied by the owner. Tackle
  and spill use the action owner/initiating tackler. Interactions are ordered by actor ID, then
  unique global enqueue sequence; locomotion and ball commands remain sequence ordered.
- The owner-supplied `PlayerFatigueSnapshot.effective_tackling` is the fatigue-adjusted Tackling
  query input. `S2RuntimeCommand.tackle()` requires that typed snapshot and checks the serialized
  effective value and stable `player_id` against the action owner, so the S2 resolver consumes the
  adjusted value once and rejects missing or mismatched provenance.
- `PlayerMotionState.on_pitch` is the explicit active-player boundary. On-pitch initialized players
  require per-tick locomotion snapshots; off-pitch initialized players keep stable setup identity
  but do not require a per-tick update or receive locomotion advancement.
- The S2 integrator owns the ball state and runs after deterministic input/state preparation. S2
  must document the concrete system registration order in its implementation PR. No separate S2
  system may depend on incidental insertion order within a single tick.

## 2. Public typed data and simulation boundary

Use typed GDScript and custom Resources following CONVENTIONS. Names below specify the public
contract; implementers may split private helpers without changing behavior.

### Tunable Resources

`BallPhysicsParams` contains units-labelled exported fields for mass (0.435 kg), ellipsoid
semi-axes (0.095, 0.145, 0.095 m), isotropic inertia (0.006097 kg·m²), gravity (0, −9.8, 0
m/s²), solver step numerator/denominator (1/200 s), drag scope, density (1.29 kg/m³), Cd curve
(0.5 at ≤15 m/s to 0.2 at ≥20.5 m/s), initial angular velocity jitter (up to 0.05 rad/s per axis
on new body creation), and predictor constants. Gravity and all such values remain patchable
Resources. Initial spin jitter uses `sim.rng`; the observed compiled-out random bounce term stays
off in Classic.

`PitchSurfaceParams` / `PitchSurfaceTable` represent each row of RE 06 §2.4 with named fields
`bounce_side_on`, `bounce_end_on`, `unused_bounce_randomness`, `friction`, and `rolling_resistance`.
Preserve the six numeric rows verbatim. `get_for(condition, stadium_id)` returns row 2 for stadium
ids 0x19 and 0x1d, regardless of condition.

`KickProfile` and `KickTable` hold each observed type’s speed and elevation range, accuracy/power
formula parameters, spin, and the goal-kick settings. `PassParams` holds type timing, lead offsets,
forward-assist settings, catch/fumble tables and radii. `LocomotionParams` contains run/sprint and
acceleration tables, sprint-drain option scaling, drain/regeneration, and sprint gates; it does not
own the player fatigue-time curve. `TackleParams` contains
the documented strength bands/bonuses, contact-type bases, power coefficients, big-hit gates,
spill chances/range, and tunable inputs for unresolved carrier/action modifiers. Each Resource must
be exported and patchable, with units and Classic provenance in `##` comments.

Known, observed values from RE 06 are represented in Classic Resources. A Resource field is
eligible for a Classic value only when RE 06 identifies that value as observed; formulas and
numeric tables retain their cited provenance. Unknown inputs are required, typed injected values
with an explicit `provisional`/`unresolved` marker and provenance comment, not guessed defaults.
This applies in particular to catch candidate scoring/gating and settings, pass type/target mapping,
tackle modifier/helper bindings and control gates, wind derivation/enablement, PID gains, and
place-kick meter output until its owning slice supplies a resolved result.
Classic construction must fail validation or require the owning system to inject these values
before a behavior that needs them runs; it must not silently substitute zero, neutral, or another
plausible value. The explicit zero carrier modifier in T-02 is an acceptance-fixture injection
only. Test fixtures may inject provisional values to isolate known formulas, but may not label
those fixtures as recovered Classic defaults. No complete `.tres` set may claim Classic behavior
for an unresolved path merely because the required fields are populated.

### Runtime data

- `BallState` is a sim-owned typed state value: position, orientation, linear/angular velocity,
  held/goal-kick flags, and solver accumulator numerator. Its numeric state is included in
  deterministic snapshots.
- `PlayerMotionState` is match-local per player: position, heading, desired heading/speed,
  current mode, acceleration increment, run/sprint speed cache, sprint energy, and stagger timer.
  It does not contain fatigue time. Each tick receives a read-only fatigue snapshot from the
  player/match layer keyed by team and shirt, and fatigue-adjusted skill values for applicable
  pass/tackle queries. Persistent profile attributes and the injected fatigue snapshot remain
  read-only to S2.
- `ContactResult`, `KickLaunch`, `PassLaunch`, `CatchResult`, `PickupResult`, and `TackleResult`
  are typed result values with stable fields; use enums for outcomes, never stringly typed tags.
- Mutable state and any state affecting future behavior or randomness must be represented in the
  owning `SimSystem.snapshot()` output in deterministic order. No Nodes, physics server queries,
  or engine rigid-body simulation decide game outcomes.

### S2 system contract

Implement ball, player locomotion, and contact/pass-catch components as `SimSystem` implementations
owned by `MatchSim` setup. They accept S1’s `MatchConfig` and resolved Resources before tick 1,
consume one quantized input frame and seeded RNG only during their registered tick, and expose typed
simulation results. Ball collision geometry is passed as deterministic data; do not query a physics
server from `MatchSim`.

## 3. Ordered S2 tick and event contract

One S1 match tick is exactly 1/60 s. Its registration order and S2 internal phases are fixed:

1. **Input/state capture:** read current `InputFrame`, player/team state, pitch condition and
   current ball mode. Do not sample devices here.
2. **Player movement and energy:** capture the read-only fatigue-time snapshot and fatigue-adjusted
   skill inputs supplied by the player/match layer. Derive run/sprint mode and desired speed/heading,
   update speed and S2's sprint-energy pool with `dt = 1/60`, using the injected fatigue-derived
   energy cap. Do not advance fatigue here: the owner advances each on-pitch player's team/shirt
   value by `dt_match` and applies its half-time recovery per RE 09 §2.3. Use RE 06 §2.9 for
   locomotion and sprint-energy behavior. The original movement equations' 50 Hz constants are
   converted to rates per second, then integrated with the fixed S1 tick duration; never use
   renderer frame delta. This 60 Hz locomotion math does not reconcile set-piece 50-tick animation
   time with motion's 60 Hz playback clock. Their relationship remains unresolved pending caller
   tracing (Phase 1 review C11); do not convert one clock into the other by assumption.
3. **Action construction:** resolve requested action data against current typed state. For a kick,
   construct the Classic launch and consume every draw that launch requires before invoking
   `physics.kick_launch`; for a pass, resolve the pass path and consume its prescribed draws before
   invoking `physics.pass_launch`. Pass filters run only after that resolved path has consumed its
   prescribed draws; where RE does not establish their ordering, this contract does not prescribe
   an order. Filters run before launch state is committed and cannot add, remove, reorder, or rewind
   the resolved path's draws. Pass/catch/tackle unknown inputs must be injected as specified in §2;
   do not manufacture a Classic result when a required input is absent.
4. **Ball solver:** evaluate solver activity after action/state changes for this tick have been
   committed. Under the provisional S2 policy, add the tick's exact 1/60 s equivalent only if the
   match lifecycle is active and the ball is then in free-flight/rolling solver mode. Thus a held
   ball launched into free flight earlier in the same tick is eligible on that tick; a ball still
   held/attached/frozen at this gate is not. See §4 for the provisional status and its evidence
   limit. On an eligible tick, add its exact 1/60 s equivalent to the
   rational accumulator and execute zero or more 1/200 s solver steps (see §4). Within every
   substep, use stable order: integrate forces, detect contacts,
   sort contacts by the deterministic total key in §5, solve contacts in that order, then
   classify post/crossbar contact. Cap stored contacts at 16 as the RE does. No hook may reorder
   contacts or consume randomness.
5. **Pass/catch/pickup and tackle resolution:** resolve queued interactions in stable player id,
   then action sequence order. Apply chance hooks immediately before the corresponding seeded roll.
   All random rolls use `sim.rng`; use strict `<` against probability as described in RE.
6. **Publish results:** store typed outcomes on the system for downstream systems (S3/S4), and
   queue externally visible match events for `MatchRunner` to relay after the whole `MatchSim.tick`.
   Hook observers and presentation listeners never run mid-tick.

If system composition separates these phases across instances, registration must preserve this
order and tests must assert it. A missing S2 component is a construction/configuration error;
there is no alternate mod-only code path.

## 4. 60 Hz match tick and 200 Hz ball solver

Do not change ADR-001’s 60 Hz `MatchSim` tick. Do not run Godot/Jolt physics at 200 Hz or let frame
rate determine ball advancement. The S2 ball system uses an integer rational accumulator, avoiding
floating accumulation and platform-dependent threshold comparisons:

- Let `solver_accumulator` be an integer in `[0, 59]`, initially 0.
- Add 200 only on a **physics-active match tick**: a `MatchSim` tick during the match's active
  gameplay state (not paused, in a cut-scene/non-simulating transition, or after match completion)
  on which the ball is in free-flight/rolling solver mode. Under this **provisional S2 rebuild
  policy**, a held, attached, or explicitly frozen ball does not accumulate solver time. RE 06 §4
  confirms that an attached keyframed path overrides the rigid body and the body follows sampled
  positions; it does not confirm held/attached/frozen solver gating. This is a deterministic S2
  architecture choice pending caller/state-predicate evidence, not recovered game behavior. The
  match lifecycle and post-action ball mode supply this state as deterministic tick input; the ball
  system does not infer it from wall time, scene visibility, or animation. Ticks that do not meet
  this provisional condition leave both accumulator and ball solver state unchanged.
- While the accumulator is at least 60, subtract 60 and execute one solver step with `dt = 1/200`
  exactly.
- This gives a repeating 3, 3, 4 substep pattern and exactly 10 substeps over every 3
  physics-active match ticks; after N physics-active ticks total substeps are `floor(N*10/3)`,
  with no lost or duplicated time. Inactive ticks do not count toward N.
- Serialize the accumulator and each solver state field in `snapshot()`. The same config, mod set,
  seed and input log must reproduce the same state hash after every 60 Hz tick.
- RE 06 mentions a “flush” flag that may force an extra step consuming the remainder, but does not
  recover its activation conditions. Do not activate this in Classic. Leave an explicit typed,
  deterministic extension point only if needed; do not invent a trigger or alter Classic cadence.

## 5. Mod data and hooks

All observed numeric fields above are data overrides with base Classic values. Unresolved fields
remain required injected inputs as specified in §2; `BaseExtensionPoints` gains these declared
points. Add exact typed argument/result wrappers and validate returned values before
using them:

| Point | Kind | Call position and contract |
|---|---|---|
| `physics.ball_contact` | FILTER | After deterministic contact geometry is computed and before response is applied; value is `ContactResult`; filter may replace only documented response values (bounce/restitution, friction, and rolling resistance) within bounds, not contact identity/order or any detected post-hit classification. |
| `physics.kick_launch` | FILTER | After Classic kick launch is constructed, including its prescribed seeded draws, and before state commit; value is `KickLaunch`; may replace velocity and spin within §5 validation bounds. |
| `physics.pass_launch` | FILTER | After Classic pass solution and its prescribed draws are constructed and before state commit; value is `PassLaunch`; outputs use §5 validation bounds. |
| `physics.catch_resolve` | FILTER | After deterministic candidate selection and base probability computation, immediately before roll; value is `CatchResult` with probability override. |
| `physics.tackle_resolve` | FILTER | After base contact/break probability is computed, before roll; value is `TackleResult` with probability override. |
| `physics.fumble_resolve` | FILTER | Immediately before fumble roll; value carries probability. |
| `physics.ball_spill` | FILTER | Immediately before spill roll; value carries probability and allowed velocity scale range. |
| `physics.wind_provider` | PROVIDER | Called once when constructing match-local wind setup; argument is typed match/config context; non-null return is an explicit `S2WindPolicy` with enablement and finite `Vector3` km/h. Resolve one provider by declared deterministic precedence and document conflicts. |

The RE notes label the first seven script hooks as callable hooks and names a provider for wind;
S1’s `ExtensionPoints` supports observer/filter/provider only. This brief standardizes them as filters
or a provider to fit that API; an implementer must add them to `BaseExtensionPoints`, not invent a
parallel hook registry. For multiple FILTER hooks, S1 order applies: ascending priority, then mod
load/registration order, with each returned value passed to the next hook. For the wind provider,
take the first non-null result in that same order. Do not infer that no provider means Classic wind
is zero for every match: zero is the observed default vector in RE 06 §2.3, but mapping and
enablement are unresolved. Require an injected Classic wind policy/value for wind-enabled paths;
otherwise the path is unavailable and must be reported as unresolved, not silently run with zero.
Validate finite values and bounded probabilities, preserve the seed stream, and report invalid
results as a mod issue rather than silently coercing non-finite data.

Hooks and data patches apply identically whether no script mods are enabled or mods are present.
No script hooks means the Classic code path still runs unchanged. Every hook executes at its one
declared deterministic phase and can affect only the typed value it receives; it cannot directly
mutate `MatchSim` or reach the scene tree.

Contact sorting uses this total key, ascending: `(body_id, feature_id, contact_kind,
quantized_point_x, quantized_point_y, quantized_point_z, quantized_normal_x,
quantized_normal_y, quantized_normal_z, source_subfeature_id, detection_ordinal)`. IDs and kind are
stable integer values supplied by deterministic body/geometry data; point components are quantized
to integer micrometres and unit-normal components to integer millionths before comparison.
`detection_ordinal` is the deterministic detector emission index and is only the final discriminator
for otherwise identical contacts. This fully orders ties without relying on container iteration or
floating-point sort behavior. A geometry provider that cannot supply stable IDs/order is invalid.

### Classic launch draw order and hook validation

RE 06 §2.6 observes aim yaw, grubber elevation jitter, randomized spin for up-and-under/chip,
AI place-kick spread, and other random kick behavior; §5 requires all such draws to use the seeded
match RNG. It does **not** establish the exact order that launch components are assigned or the
order of all launch draws (`unk_79dddbbb`; RE 06 §7). Until that evidence is recovered, this spec
sets one **provisional deterministic contract**, not a recovered Classic fact: draw aim yaw first
when applicable, then grubber elevation jitter when applicable, then randomized spin components
when applicable, then any AI-specific spread. Draw only values applicable to that launch. Construct
the complete Classic `KickLaunch`, invoke filters, then commit it. This gives filters no effect on
the Classic RNG stream. T- and B-acceptance fixtures must assert this chosen stream contract while
the open question remains; when evidence resolves the order, update the contract and fixtures
together. New-body initial-spin jitter is a separate body-construction draw (RE 06 §2.3), not a
launch draw.

All hook outputs must be finite and within explicit bounds before use. These are API safety bounds,
not recovered Classic limits: launch/pass linear-velocity components in `[-100, 100] m/s`, angular
velocity components in `[-100, 100] rad/s`; probabilities in `[0,1]`; spill velocity scale in
`[0,2]`. Contact hooks may change only documented response values: restitution in `[0,1]`, friction
coefficient in `[0,2]`, and rolling resistance in `[0,1]`. Contact identity, point, normal,
body/feature ids, sorted position, and detected post classification are immutable. Invalid values
reject the hook result and surface a mod issue; they are not clamped into a seemingly valid value.
These provisional ceilings may be narrowed by an ADR or implementation contract, but widening
them requires updating validation and acceptance criteria explicitly.

Place-kick meter ownership stays with S4 (RE 06 §2.6). S4 supplies a typed
`PlaceKickMeterResult` with the **raw, unadjusted gauge** in `[0,1]` and signed needle error `e`;
it does not supply already needle-adjusted power. S2 computes the RE 06 needle multiplier from
`|e|` and applies it to the raw gauge exactly once when building launch power, then builds
velocity/spin, consumes applicable S2 launch draws, runs `physics.kick_launch`, and commits the
result. S2 must not reimplement the meter, and S4 must not duplicate launch construction or apply
the needle multiplier before returning the result.

## 6. Implementation tasks

1. Add typed S2 parameter Resources and Classic `.tres` defaults; validate ranges and required
   fields at setup. Retain unresolved fields as explicitly provisional/injected inputs.
2. Add ball state and pure force/drag, path predictor, kick launch, pass launch, catch/fumble and
   pickup calculations from RE 06 §§2.3–2.7. Keep predictor arithmetic separate from body solver.
3. Add deterministic 200 Hz accumulator and ball substep integration, contact detection/response,
   pitch surface selection, contact cap, and post-hit classifier. Geometry must be passed in as
   deterministic data from S1/S6/S7 integration rather than fetched from a PhysicsServer.
4. Add player motion state and locomotion formulas: run/sprint selection, top-speed tables,
   acceleration, sprint drain/regeneration, and energy gate. Consume the player/match layer's
   fatigue-time snapshot and fatigue-derived energy cap; do not integrate fatigue in S2. Consume
   fatigue-adjusted Passing/Tackling inputs supplied by that layer without applying their penalty
   a second time. Leave exact PID turning behavior behind a typed injected tuning interface until
   RE provides gains.
5. Add physical tackle resolver and spill behavior. Separate its result from legality/infringement;
   produce a typed result that S3 can consume without reaching into S2 internals.
6. Add the declared S2 extension points to `BaseExtensionPoints`; wire calls in the order of §3 and
   §5. Ensure provider/filter selection is deterministic and bounded.
7. Register the S2 systems through the S1 composition path for all runs. Add every mutable field,
   accumulator, random state dependency, and pending typed result to deterministic snapshots.
8. Document each unresolved decision in the implementation’s resume/spec note. Required unknowns
   must be injected or make the dependent Classic path unavailable; a neutral value is valid only
   when a RE acceptance case explicitly injects it. Do not turn unknowns into claimed Classic facts.

## 7. Acceptance criteria

These numeric behavior checks are taken from RE 06 §6. Tests must not use extracted/original game
assets. For every randomized case, use injected `SimRng` state and assert strict comparison
boundaries. S1 replay/determinism architecture also applies: identical config, mod set, seed and
input frames must hash identically after every tick, and a modded run with no effective S2 changes
must exercise the same S2 systems.

### Ball / predictor / kick

- **B-01** Gravity-only launch: 20 m/s at 45° from y=0.1 m returns to y=0.1 after 2.886 s ±0.01
  and travels 40.82 m ±0.1.
- **B-02** Predictor from (0,2.1,0), v=(5,0,0), gravity: first contact at 0.639 s; post-bounce
  `v_y=3.444 m/s`, `v_x=4.425 m/s`.
- **B-03** Predictor changes to rolling below 0.01 s hop time; horizontal acceleration is
  `−0.8*v_xz`.
- **B-04** Aero force is zero outside the goal-kick state for any velocity.
- **B-05** Goal-kick aero: specified 10 m/s, Cd 0.5 case gives Fz=−1.395 N ±0.01; at 25 m/s,
  Cd=0.2.
- **B-06** Wind 3.6 km/h along +x with stationary ball gives +x aero force of the documented
  magnitude.
- **B-07** Condition 2 bounce restitution is 0.5 side-on and 0.4 end-on in friction-free cases.
- **B-08** Surface lookup matches all six RE table rows; stadium ids 0x19 and 0x1d always use row
  2.
- **B-09** Ball kick launch table: punt gauge/stat endpoints produce 22.304 and 17.637 m/s,
  elevation 42.5°; chip always produces 12.2 m/s, 10°.
- **B-10** Aim error: Kick 100 -> 0°, Kick 50 -> 8.294°, Kick 0 -> 16.588°; drop-kick
  difficulty 3 multiplies by 3.
- **B-11** Place kick at full gauge/power and zero needle error is 33.0 m/s; error 1.5 gives
  30.125 m/s.
- **B-12** Contact classifier returns crossbar/upright/pad part ids for all four RE 06 §6 test
  coordinates.
- **B-13** One physics-active solver tick adds 200 numerator units against a 60-unit threshold,
  runs the resulting 3/3/4 cadence over three such ticks, and preserves remainder. After N
  physics-active ticks, total executed
  substeps equals `floor(N*10/3)`; repeated replay hashes include the same accumulator and ball
  state.
- **B-14 (provisional policy, not recovered behavior)** On an active match tick where an action
  changes the ball from held to free flight before the solver gate, the gate sees the post-action
  mode and adds 200. If the ball remains held/attached/frozen at the gate, neither accumulator nor
  solver state changes. This locks the documented S2 tick contract pending RE caller evidence.

### Passing / catching / pickup

- **P-01** Normal/lead pass uses 0.5/0.9 s; for 10 m horizontal offset and equal heights, normal
  horizontal speed is 20 m/s; lead target adds 3 m rather than 2 m.
- **P-02** Passing 0/100 gives 1.5/0.55 s; fixed-time types remain 0.5 or 0.7 s.
- **P-03** Forward assist setting 3 flattens a 10 m/s forward pass with probability 0.7, always
  flattens 7 m/s, and setting 0 leaves both unchanged.
- **P-04** Average quality, Handling 85 fumble probability before settings scale is 0.0125 dry
  and 0.025 slippery; Handling 39 selects the `<40` column (0.25 before scaling).
- **P-05** Pickup rejects held ball, vertical separation 1.01 m, or failed 0.1 m hand capsule;
  accepts the 0.99 m case when capsule intersects. Reach exactly 1.0 m / 2.0 m is within the
  respective catch segment; just beyond is not selected.
- **P-06** For a pass path fixture that prescribes N seeded draws, `physics.pass_launch` runs only
  after all N draws have been consumed. The fixture verifies the hook boundary without asserting
  an ordering for unresolved pass-path draws.

### Locomotion / contact

- **L-01** Sprint speed values: stat 55 -> 7.5, 60 -> 7.75, 90 -> 9.25, 99 -> 9.5 m/s; run
  speed at stat 50 is 6.25 m/s.
- **L-02** Run-to-sprint acceleration times: stat 100 -> 0 s, 90 -> 1.0, 75 -> 2.0, 52.5 ->
  3.5, 30 -> 5.0 s.
- **L-03** At 9 m/s with run speed 7 and fatigue factor 1, energy changes −4/s; at 5 m/s it
  changes +10/s; condition 4 at 9 m/s changes −13/s. Here “fatigue factor” is RE 06's sprint-drain
  option multiplier (not player fatigue time); the fixture injects energy cap and fatigue-adjusted
  skills from the player/match layer.
- **L-04** Energy 5 cannot start sprint but an active sprint continues at energy 5.
- **T-01** Tackle strength bonus is 0 at carrier Strength 90, 15 at 89, 10 at 74, 20 at 59;
  relative 136° adds 10 head-on points, 135° does not.
- **T-02** Defender: Tackling 90 and defender Tackle ability bit set. Carrier: Strength 90 and
  carrier Strength-category ability bit 6 set (the separate carrier bit required for the ≥90
  category in RE 06 §2.8). With no head-on angle, effective defender skill is 90 and skill-derived
  break chance is 0.10 when the unresolved carrier break modifier is explicitly injected as zero.
- **T-03** Charge/hand-off/sidestep bases are 0.4/0.5/0.2 before power ratio and modifiers.
- **T-04** Spill bases are 0.25 for qualifying head-on dive, 0.05 big hit and 0.02 ordinary
  eligible tackle. Seeded range endpoints yield velocity scales 0.75 and 1.25.
- **T-05** Big-hit gates match 50% energy plus stats 80 or Tackle ability, alternate 35% energy
  plus Aggression/Tackling 70; values below the relevant threshold fail.

## 8. Open questions and bounded unknowns

The following behavior gaps remain unresolved. Entries carrying `unk_` IDs are registered in RE 06
§7. Keep them visible in task estimates and tests:

- **Blocking for exact Classic contact fidelity:** carrier break modifier at player +0xd0 and
  precise stat bindings for special-action power helpers (`unk_8e0586d0`). Keep modifier injectable;
  neutral zero is valid only in the RE acceptance fixture, not an asserted production value.
- **Kick RNG order:** RE 06 §2.6 and §5 identify the applicable aim, grubber, spin, AI-spread and
  body-initialization draws, but `unk_79dddbbb` does not establish the exact order among launch
  assignments/draws. §5 defines a deterministic provisional order for implementation and tests;
  it remains unresolved evidence, not recovered Classic order.
- **Pass RNG order:** the evidence does not establish a recovered ordering of pass-path draws.
  The pass resolver consumes its path-prescribed draws before `physics.pass_launch`; S2 does not
  assert an ordering beyond that hook boundary. The caller supplies the resolved pass path and its
  prescribed draws; do not invent or label an ordering as recovered.
- **Blocking for complete tackle controls:** dive reach/trigger, meanings of contact types 3/9/10,
  charge/hand-off mapping, big-hit cost and state gate (`unk_7348ff64`, `unk_07c49a89`). Implement
  observed outcomes and formula branches; omit unsupported control mapping pending S3/input owner.
- **Pass/catch:** complete pass-type mapping, target height/spin (`unk_a3a09d95`); catch gate and
  candidate score (`unk_412edd03`, `unk_76396ae9`); settings bytes and pitch-condition names
  (`unk_61fc9441`). Preserve observed base formulas but require explicit injected values for
  unknown gate/target/selection fields; do not invent a Classic selection score or claim a complete
  Classic pass/catch resource while those fields are absent.
- **Wind:** wind vector derivation and enable predicate (`unk_80525c5d`). Zero wind is the observed
  default vector, but mapping/enablement for nonzero wind is unresolved; require an injected policy
  for any path that evaluates nonzero wind, and do not infer an enable predicate.
- **Movement:** actor turn-controller PID gains (`unk_0c291a7f`) are unknown. Do not claim exact
  heading fidelity; keep gain parameters injected and document any provisional values.
- **Solver:** flush activation condition and rolling/twist torque form unknown. Classic does not
  flush; isolate rolling/twist behavior behind named parameters and test known restitution/friction
  values only. RE does not confirm whether held/attached/frozen ball states gate rigid-body solver
  advancement. The post-action free-flight/rolling predicate and same-tick launch rule in §3–4 are
  provisional S2 policy until the responsible callers/state predicate are traced.

## 9. Risks and exit criteria

### Risks

- Floating-point contact solutions may differ across OS/runtime versions. Keep solver iteration,
  contact ordering and state hashing stable; use integer/quantized decisions at probability and
  discrete-outcome boundaries where possible. Phase 4 cross-OS checks remain mandatory.
- A full LCP contact solver is the largest performance/correctness risk. Keep it pure and isolated,
  cap contacts at 16, add solver iteration guards, and profile only against synthetic geometry.
- Unresolved RE details can make plausible defaults look authoritative. All provisional values
  need names/comments and a non-Classic marker until verified.
- Hook filters can break determinism if they access time, global RNG or mutable scene state. Hooks
  must be invoked synchronously at documented tick points and receive only typed values/context.
- Ball/stadium collision data integration may not be ready from Phase 2; use hand-written synthetic
  geometry fixtures while preserving the eventual `Stadium.collision` interface.

### Exit criteria

- All RE 06 §6 behaviors in §7 pass, including the exact 200 Hz accumulator cadence and Classic
  surface/stadium exceptions.
- S2 state is part of `MatchSim.snapshot()` and reproduces identical per-tick hashes for identical
  seed, config, mod set and input log. Classic and no-op-mod paths instantiate the same S2 systems.
- S2 adds its extension points through `BaseExtensionPoints`; hook order, probability override
  point and wind-provider choice are deterministic and documented.
- S2 produces typed physical interaction results consumed by S3; no referee or legality decisions
  reside in S2.
- The author’s implementation passes project gates, then receives separate code, fidelity and
  architecture reviewers as required by PLAN. This spec author does not self-review implementation.

## 10. Runtime composition and replay implementation contract

`MatchCompositionBuilder` is the canonical composition path for live `MatchRunner` starts and
`MatchReplay` runs. Both paths register caller systems and extension-provided systems first, followed
by `s2_locomotion`, `s2_ball_physics`, and `s2_interactions`. A typed `MatchBuildResult` reports
unavailable capabilities through `MatchReadinessReport`; missing geometry or the contact solver is
a construction blocker, not a request to synthesize contacts or use scalar damping.

Callers provide ball initialization, player and fatigue setup, environment values, contact
dependencies, and sequenced `S2RuntimeCommand` inputs through `S2RuntimePort`. The port publishes
typed `S2RuntimeResult` records. It accepts resolved values only and does not implement S9 action
mapping, pass/catch selection, fatigue ownership, wind derivation, or goal-kick policy. Initial
`BallMode` and `GoalKickState` are explicit. `GoalKickState.OFF` is an owner choice; `ACTIVE` also
requires an owner-supplied wind policy. Extension wind providers also return an explicit
`S2WindPolicy`; the builder never turns a vector into an enabled/disabled decision.

Replay header format v3 stores a setup fingerprint over effective config and resources, ordered
systems, extension point and hook configuration, mod/action-layout identity, environment and player
setup, contact providers, resolved wind policy, and tick rate. Each input frame stores ordered v3
command records and their corresponding typed outputs, including the actor identity and player-bound
fatigue provenance required by S2. `MatchReplay.run()` accepts only v3 logs: S2 command/output and
setup-fingerprint semantics are defined by v3, so v1/v2 records cannot run an S2 match.

Parsing and serializing accepted historical v1/v2 structures remains supported for round-tripping.
V1 headers omit `setup_fingerprint`, and v1 logs omit runtime command/output frame data. V2 headers
include `setup_fingerprint`; v2 logs include runtime command/output frame data using the v2
structure. The fingerprint retains the same setup-identity meaning described above; this policy
does not add a migration or imply that historical v2 commands satisfy the v3 S2 contract.

Each S2 tick is transactional across all registered systems, contact source and solver, `SimRng`,
pending commands and results, players, interaction outcomes, ball pose and solver accumulator. A
dependency must explicitly declare itself stateless or provide complete snapshots and typed
checkpoint/restore methods; otherwise composition is blocked and no replay-completeness claim is
made. This contract does not make S2 runnable by itself: Classic stadium geometry, the
contract-complete LCP solver, and caller-owned player/fatigue/action inputs remain required.
