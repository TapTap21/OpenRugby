# 06 — Ball and contact physics

Status: Phase 1, first full pass. Target: the SecuROM-repaired unpacked image
`Rugby08_unpacked.exe` (sha256 `aba7a647…`), Ghidra 12.1.4 via REA. Each claim
is tagged **[O]** (observed in decompiled code or data), **[I]** (inferred
from observed facts) or **[U]** (unknown). Evidence IDs are REA Evidence IDs,
shortened to their first 8 hex digits after `ev_`. "local" means that the
claim was read from our own disassembly of the same image (`.omc/research/phys/`)
and does not have an REA Evidence ID yet. This file contains no decompiled code.

Ownership boundaries: the rules lead (05) decides infringements, the set-piece
lead (07) owns scrum, lineout, ruck and maul mechanics and the goal-kick meter,
the players lead (09) owns attributes, fatigue and injuries, and the motion
lead (12) owns animation clips. This file owns the physical and numeric models
that those systems use.

---

## 1. Scope and entry points

All addresses are virtual addresses in the image. Names are applied in the
shared REA session (`set_addresses_names`, Evidence `ev_0837fb56`) and
recorded in `.omc/research/functions/phys.tsv`.

| Area | Address | Name | Evidence |
|---|---|---|---|
| Frame update (dt × speed scale) | 0x421ed0 | `ai_FrameUpdate_ScaledDt` (MovementMode slot 3; named by the AI lead) | ev_8d11a3c8 |
| Unlockable modifiers: gravity and slow motion | 0x4f4040 / 0x4f40a0 | `phys_ResetPlayNowModifiers` / `phys_ApplyPlayNowModifiers` | local / ev_01118989 |
| Rigid-body world update (fixed sub-steps) | 0x4b9450 | `phys_DynSim_Update` | local, ev_b38863b5 (step constant) |
| One sub-step | 0x4b9bf0 | `phys_DynSim_Step` | local |
| Contact detection (ellipsoid vs ground plane and stadium mesh) | 0x4b4ed0 | `phys_DynSim_DetectContacts` | ev_7aed4b04 |
| Contact solver (LCP, restitution, friction) | 0x4b6920 | `phys_DynSim_SolveContacts` | ev_e4d8b68a |
| Ball rigid-body set-up (mass, inertia, spin) | 0x4b3c00 | `phys_DynBody_InitBall` | ev_1a9f12a8 |
| Aerodynamic force | 0x4b6190 | `phys_Aero_DragForce` | ev_40007ba0 |
| Ball acceleration (gravity + aero / mass) | 0x622a90 | `phys_Ball_ComputeAcceleration` | ev_97f2f6b5 |
| Gravity force on ball | 0x623ca0 | `phys_Ball_GravityForce` | local |
| Drag / wind switches | 0x624090 / 0x6240b0 | `phys_BallManager_SetDragEnabled` / `SetWindEnabled` | local |
| Goal-kick state enter / exit (switches drag and wind) | 0x68c4d0 / 0x68c530 | `phys_GoalKickState_Enter` / `Exit` | ev_34f726f5 / local |
| Surface (pitch condition) parameters | 0x4ba6f0 | `phys_PitchSurface_GetParams` | ev_95ba8a18, table ev_ae86498d |
| Analytic ball-path predictor with bounces | 0x6217f0 | `phys_BallPath_Advance` | ev_95b99e84 |
| Predict ball position after t | 0x623f10 | `phys_BallManager_PredictPosition` | local |
| Post / crossbar hit classifier | 0x4a8340 | `phys_BallMonitor_CheckPostHit` | ev_d5e56fb2 |
| Goal-plane crossing events | 0x4a80f0 | `phys_BallMonitor_CheckGoalPlane` | local |
| Kick object (CKick) and per-type tables | 0x7418c0, 0x743e20, 0x7493b0, 0x749770, 0x8c62c0..0x8c64f0 | `phys_Kick_*` (24 names, see phys.tsv) | see §2.6 |
| Player top speed | 0x655f70 | `phys_Player_GetMaxSpeed` | ev_8e6158b1 |
| Sprint speed table | 0x655e30 | `phys_Player_SprintSpeedFromStat` | ev_890a05bd |
| Acceleration increment | 0x655b40 | `phys_Player_AccelIncrement` | ev_fc311b1c |
| Run / sprint selection | 0x6123e0, 0x656350, 0x656160 | `phys_Player_SelectRunOrSprint`, `CanSprint`, `AccelFactor` | ev_fc7fa590, local, ev_73f486db |
| Player per-frame update (sprint energy) | 0x60cfe0 | `phys_Player_Update` | ev_41b7d91b |
| Passing, catching, pickup | see §2.7 | `phys_Pass_*`, `phys_Catch_*`, `phys_Pickup_*` | see §2.7 |
| Tackle and contact | see §2.8 | `phys_Tackle_*` | see §2.8 |

---

## 2. Behaviour

### 2.1 Units, axes and pitch geometry

* **Units [O].** Gameplay code works in metres, seconds and kilograms.
  Evidence: air density 1.29 kg/m³, ball mass 0.435 kg, gravity −9.8 m/s²
  (ev_40007ba0, ev_97f2f6b5). Render models use a second unit,
  1 model unit = 0.01905 m (¾ inch, the FIFA engine unit). The game converts
  with the constant 1/0.01905 (local: static initialiser 0x8b73d0; constant
  block ev_fdabdb0b).
* **Axes [O].** y is up. The pitch length runs along z and the width along x.
  The origin is the centre spot.
* **Pitch constants [O].** A shared header constant block is compiled into
  several translation units (ev_fdabdb0b; static initialisers 0x8b2400–0x8b2c70,
  local). Values are in metres:

| Constant | Value | Meaning | Tag |
|---|---|---|---|
| `try_line_z` | 50.0 | try (goal) line at z = ±50, so the field of play is 100 m long | [O] value, [I] meaning (agrees with the pitch-line model: lines at ±2624 model units = ±49.99 m) |
| `in_goal_depth` | 14.1 | dead-ball line at z = ±64.1 | [O] |
| `twenty_two_z` | 28.0 | 22 m lines at z = ±28 | [O] value; the model has lines at ±1468 units = ±27.97 m |
| `crossbar_height` | 3.0 | top of the crossbar | [O] |
| `goal_width` | 5.6 | between the posts (half 2.8) | [O] |
| `post_low_zone_height` | 2.26 | below this height a post hit is classed as "low" (see §2.4) | [O] |
| `goal_line_inset` | 49.8 | 50 − 0.2 (used by set-piece code) | [O] value, [U] use |

* **Touchlines [I].** The code has no touch half-width constant in the
  shared header. In the pitch-line model of stadium bundle
  `006f3744…big`, the touchlines are at x = ±1764–1774 units, or about ±33.7 m.
  That makes the pitch about 67.4 m wide. The rules lead owns the
  out-of-bounds test. Treat this value as unconfirmed.
* **Goal-post and perimeter geometry [O].** This geometry is data, not code.
  Every stadium bundle has a `Stadium.collision` triangle mesh, which the
  contact detector reads (ev_7aed4b04). In bundle `006f3744…`, decoded with a
  throwaway parser:
  * Each upright is an octagonal prism centred at x = ±2.845, z = ±50.0, with
    radius about 0.045 m (faces at 2.80–2.89). It runs from y = 2.0 to 13.41 m.
  * The crossbar is an octagonal prism with centre height about 2.955 m and
    radius 0.045 m, so its top is at 3.0 m.
  * Each post pad is a box with |x| from 2.60 to 3.09, |z| from 49.755 to
    50.245, and y from 0 to 2.0 m.
  * The perimeter boards are at |x| ≈ 39.45 and |z| ≈ 68.55–69.45. They are
    sloped boards 0.9 m high.

  Mesh layout:
  * 570 triangles of 16 bytes each: a plane index followed by 3 vertex indices.
  * 381 planes of 16 bytes each: the normal and d.
  * 464 vertices of 16 bytes each: xyz plus w = 1.
  * About 20 KB of trailing data with unknown layout, probably a spatial grid.

  The data-formats lead should own a proper decoder.

### 2.2 Simulation timing

* **Frame dt [O/U].** The match update `ai_FrameUpdate_ScaledDt` (0x421ed0)
  runs the simulation with `dt_sim = dt_frame × speed_scale`. A fixed 1/60 s
  branch exists, but its predicate (0x581990) always returns false in the PC
  build (ev_8d11a3c8, local). So the original sim is **variable-step**, driven
  by frame time. The source of `dt_frame` and any cap on it are unknown
  (unk_a9fd88e9).
* **Speed scale [O].** `speed_scale` (global 0x99683c) = `base_speed`
  (0x9917b8) × difficulty speed. Difficulty speed is 1.10 for Club, 1.10 for
  Pro and 1.15 for Elite (AI lead, `ai_Difficulty_SetGameSpeed` 0x632c10). The
  game therefore runs 10–15 % faster than real time. `base_speed` is 1.0. The
  "slow motion" unlock (bit 0x80) sets it to 0.5 (ev_01118989).
* **Ball rigid body sub-steps [O].** The rigid-body world, which contains the
  ball, adds the incoming dt to an accumulator. It then runs as many fixed
  **0.005 s (200 Hz)** steps as fit and keeps the remainder for the next frame
  (0x4b9450 local; constant ev_b38863b5; the step value is loaded by the
  relocated stub at 0x40c860, ev_1864330c). A flush flag can force one extra
  step that consumes the remainder.
* **Rebuild decision.** ADR-001 should pin the Godot physics tick. The ball
  model below is tick-agnostic, but it was tuned at 200 Hz sub-steps.
  Recommendation: run the ball at a 200 Hz internal sub-step inside a 50 or
  60 Hz `_physics_process`, or accept small numeric drift.

### 2.3 Ball flight

**Ball body [O]** (0x4b3c00, ev_1a9f12a8; axes ev_40007ba0):
* mass 0.435 kg;
* shape is an ellipsoid with semi-axes (0.095, 0.145, 0.095) m. The long axis
  is body y;
* inertia is isotropic: I = ⅔ · m · 0.145² ≈ 0.006097 kg·m² on every axis. This
  is a hollow-sphere formula using the long semi-axis;
* a new body gets a random angular velocity of up to 0.05 rad/s per axis and
  starts 10 m up (debug and initial placement only).

**Forces [O]:**
* Gravity is `g` = (0, −9.8, 0) m/s². It is a global (0x98ddac), set to −9.8 on
  match reset. The "High Gravity" unlock (bit 0x800) sets it to −30 and the
  "Low Gravity" unlock (bit 0x1000) sets it to −5 (ev_01118989, local
  0x4f4040). Every gravity user reads the global, including kick and catch
  predictors, so the cheats change all trajectories consistently.
* Aerodynamic force is `phys_Aero_DragForce` (ev_40007ba0). It is **only
  active while the goal-kick state is active** (conversions and penalty kicks
  at goal). `phys_GoalKickState_Enter` turns drag on, and turns wind on as well
  when the kick qualifies (ev_34f726f5). Exit turns both off. In open play the
  ball flies in a vacuum under gravity only [O].
  * Let `u` be the air velocity relative to the ball: `u = W/3.6 − v` when
    wind is on, otherwise `u = −v`. W is the match wind vector in km/h
    (match + 0x18e0). Its default is (0,0,0).
  * Let `s` be `|u|`.
  * `Cd = 0.5 + (0.2 − 0.5) · clamp((s − 15)/(20.5 − 15), 0, 1)`. This is a
    drag-crisis style drop from 0.5 below 15 m/s to 0.2 above 20.5 m/s.
  * Reference area `A`:
    * If s ≤ 0.01, A = 0.045 m².
    * Otherwise take the flow direction in the ball's body frame. Build two
      unit vectors perpendicular to it. Each is the cross product with body x
      or body y, whichever is longer.
    * For each unit vector u, r = 1/√(Σ uᵢ²/aᵢ²), where a is the semi-axis
      vector.
    * Then A = π · r₁ · r₂. The projected area therefore depends on the
      ball's attitude [O].
  * The force is applied **per axis**: Fᵢ = ½ · ρ · Cd · A · |uᵢ| · uᵢ, with
    ρ = 1.29 kg/m³. Without wind this is −½ρCdA·|vᵢ|·vᵢ. Note that this is
    per-component quadratic drag, not |u|·u. Keep it for fidelity.
  * Acceleration is `a = g + F/m` (0x622a90, ev_97f2f6b5).
* Wind qualification [I]. Wind is on only if a goal-kick object exists, a
  goal-kick predicate (0x44fbb0, obfuscated) is false, and the kicker's
  controller type is 2 (0x40bd40, inferred to mean human). How W is produced
  from the wind level (match + 0x18d8, 0..3; 0 = no wind) is unknown
  (unk_21095a01). The in-game help text says goal-kickers must "adjust your
  kick according to the direction and strength of the wind".
* Unused debug switches [O]. Bytes 0x9ba864, 0x9ba865 (force drag/wind) and
  0xa31990 (an analytic "RUCK PHYSICS!" ball override) are never written. They
  are off in the shipped game.

### 2.4 Ground, post and board contact (bounce, roll, posts)

The ball is a rigid ellipsoid in the Hbs Dynamics world. It has no scripted
bounce. **The "oval-ball random bounce" emerges from ellipsoid contact
geometry plus the spin that kicks impart** (see §2.6) [O/I].

* **Detection [O]** (0x4b4ed0, ev_7aed4b04):
  * the ground plane y = 0 is tested against the ellipsoid in the ellipsoid's
    scaled frame. A contact exists when the scaled plane distance d′ lies in
    (0, 1). Penetration is (1 − d′) · |n′|;
  * triangles of `Stadium.collision` within 0.145 m are tested by face, edge
    and vertex cases;
  * at most 16 contacts are kept per step.
* **Response [O]** (0x4b6920, ev_e4d8b68a). This is a Dantzig/Baraff-style
  LCP. Each contact contributes three rows: a normal row, a friction row and a
  rolling/twist row. Surface parameters come from `phys_PitchSurface_GetParams`
  (ev_95ba8a18). They are five floats [f0, f1, f2, f3, f4] chosen by pitch
  condition. The same set is used for ground, post and board contacts [I].
  * **Bounce factor** k = clamp(f1 + (1 − c²)(f0 − f1), 1, 2), where c is the
    body-frame long-axis (y) component of the contact direction. A belly-on
    impact (c ≈ 0) gives k = f0. A point-on impact (|c| ≈ 1) gives k = f1. The
    normal impulse uses k as (1 + e), so restitution e = k − 1 [I for the
    1 + e reading].
  * A random term ±f2/2 added to k exists in the code but is **compiled out**
    (a constant-false branch) [O]. Do not add randomness here.
  * **Friction**: |λ_t| ≤ f3 · λ_n (Coulomb) [O].
  * **Rolling/twist resistance**: |λ_r| ≤ 10 · f4 (a constant bound). The
    ground contact also applies a −f4 term to angular velocity [O for the
    values; the exact torque form is I].
  * The solver aborts on oscillation, with the warnings "Aborting constraint
    %i due to oscillation" and "Aborting constraint solver" [O].
* **Surface table [O]** (0x98e100, stride 20 bytes, ev_ae86498d). The index is
  the match pitch condition (match + 0x18d0, default 2; the missions' WEATHER
  `pitch` attribute also defaults to 2). Stadium ids 0x19 and 0x1d always use
  entry 2.

| Pitch cond | f0 bounce side-on | f1 bounce end-on | f2 (unused) | f3 friction μ | f4 rolling |
|---|---|---|---|---|---|
| 0 | 1.6 | 1.5 | 0.2 | 0.7 | 0.06 |
| 1 | 1.6 | 1.5 | 0.2 | 0.7 | 0.06 |
| 2 (default) | 1.5 | 1.4 | 0.15 | 0.7 | 0.06 |
| 3 | 1.3 | 1.2 | 0.1 | 0.6 | 0.07 |
| 4 | 1.4 | 1.4 | 0.2 | 0.8 | 0.07 |
| 5 | 1.4 | 1.5 | 0.2 | 0.6 | 0.04 |

  Condition names are [U]. Condition 4 doubles sprint-energy drain (§2.9), so
  it is a heavy pitch [I]. Condition 3 has the deadest bounce [O]. The pitch
  texture names (`Reg*_hard/normal/muddy/soggy/snow/dry`) hint at the set
  [I].
* **Post and crossbar events [O]** (0x4a8340, ev_d5e56fb2). On a ball
  collision near a goal (|z| within 5 m of 50 and |x| < 5), the ball monitor
  raises `GEVENT_GM_BALL_HIT_POSTS` (0x111) with a part id:
  * 2 (crossbar) if |y − 3.0| < 0.3 and |x| < 2.8 − 0.3;
  * otherwise 3 if y < 2.26 (low or padded part);
  * otherwise 1 (upright).

  The physical rebound itself is the ordinary mesh contact above.
  `phys_BallMonitor_CheckGoalPlane` (0x4a80f0, local) raises events 0x10e
  (`GEVENT_GM_BALL_BELOW_CROSSBAR`), 0x10f and 0x110 when the ball crosses the
  goal plane. The rules lead decides scoring.

### 2.5 Analytic ball-path predictor (AI and catch prediction)

AI, catching and camera code predict where the ball will be using an
analytic path, not the rigid body. `phys_BallManager_PredictPosition`
(0x623f10) always takes the analytic branch; the rigid-body branch is dead
(local). The path advance is `phys_BallPath_Advance` (0x6217f0, ev_95b99e84):

1. Treat the ball centre as resting at y = 0.1. Let h = y − 0.1, clamped to
   ≥ 0. Acceleration a = F/m, where F is the external force callback. That
   callback is normally gravity only; an optional extra controller force is
   0.4·v², capped (0x623d90, local).
2. Find the time of ground contact. Solve h + v_y t + ½ a_y t² = 0 for the
   later root t = (−v_y − √(v_y² − 2 a_y h)) / a_y, or t = −h/v_y when a_y = 0.
   A non-finite t logs "infinite BP loop!" and stops.
3. If t is longer than the remaining time, advance ballistically by the
   remaining time and stop.
4. If t < 0.01 s and this is not the first segment, the ball is **rolling**:
   * set v_y = 0 and a_y = 0;
   * set a_xz = −0.8 · v_xz;
   * advance for min(remaining, 1/0.8 = 1.25 s) and stop.
5. Otherwise advance ballistically by t and **bounce**:
   * v_y ← −0.55 · v_y (vertical restitution 0.55);
   * v_x and v_z ← 0.885 × their value (horizontal retention).

   Then subtract t from the remaining time and repeat.

This predictor is deliberately simpler than the real contact model. The
rebuild must keep **both**: the real model for the ball, and this exact
predictor for AI, so that AI misjudgements of bounces are reproduced. The kick
landing predictor (0x746320) uses the vacuum flight time T = 2·v_y/9.8 and the
same 0.1 m rest height (kick notes, ev_96447e5c).

### 2.6 Kicking

Source: `.omc/research/phys/kick-notes.md` (sub-agent p1-phys-kick) plus
`.omc/research/setpiece/goalkick-meter-notes.md` (set-piece lead) for the
goal-kick meter.

* **Kick types [O/I].** These are the codes stored in the kick object:

| Code | Kick |
|---|---|
| 1 | punt; also the default |
| 2 | up-and-under |
| 3 | grubber |
| 4, 5 | place kicks at goal |
| 6 | chip |
| 7, 10 | kick-off / restart |
| 8 | drop kick |
| 9 | scrum-half box kick |
| 11, 12 | other restarts |
| 13 | quick-tap penalty |

  The AI kick actions 6..11 map to types {1, 1, 3, 1, 8, 2} (ev_54e761c7,
  ev_93f613c7).
* **Launch** (ev_d943b4b8, ev_b90e0ccd):
  * Speed `v = v_lo + (v_hi − v_lo) · r · g`, where g is the power gauge in
    [0,1] and r is the kicker PowerRating. r applies to types 1, 2, 4, 5, 8
    and 9 only; it is 1 for the other types.
  * Elevation `e = e_lo + (e_hi − e_lo) · g`. It uses the gauge only.
  * The grubber adds U(−5°, +5°) to the elevation.
  * The launch vector is a **velocity** (m/s) set on the ball, not an
    impulse.

| Type | v_lo – v_hi (m/s) | e_lo – e_hi (°) | Evidence |
|---|---|---|---|
| Punt | 16.081 – 22.304 | 42.316 – 42.5 | ev_358f3e29 |
| Up-and-under | 14.5 – 22.175 | 68.478 – 76.064 | ev_19c16bae |
| Grubber | 9.79 – 16.0 | 2.019 – 10.8 | ev_8e0d6631 |
| Drop kick | 12.998 – 21.0 | 45.0 – 50.87 | ev_7ea55f3e |
| Scrum-half box kick | 13.0 – 20.1 | 50.416 – 50.489 | ev_f439f450 |
| Restarts (7, 10, 11, 12) | 10 – 20 | 40 – 80 | ev_51c68ea0 |
| Place kick (4, 5) | MinPower – MaxPower from GoalKickSettings, 10 – 33 at every difficulty | 30 – 60 | ev_1e55bc1e, ev_5877ed71 |
| Chip (6) | 12.2 (constant) | 10 (constant) | ev_d943b4b8, ev_b90e0ccd |

* **Gauge fill [O].** The gauge rises linearly while the button is held, at
  1/T per second (`m_rPowerPerSecond`). T is the wind-up length of the chosen
  kick animation, in frames/50 s (ev_035b9584). When the gauge exceeds 1 it is
  clamped to 1 with the warning "KICK POWER IS TOO LARGE" (ev_38cb3d19). The
  T values per animation have not been extracted (unk_796e3e94). Place kicks
  use the goal-kick meter instead (set-piece lead):
  * power and needle accelerate together;
  * the needle position inside the kicker-class zone gives error e;
  * angle error comes from PrimaryAngle, SecondaryAngle and RedZoneMultiply.
* **Kicker stats** (ev_54e761c7, ev_76188f23, ev_61b6c536):
  * Accuracy index `a = (Kick − 50)/50`. It is not clamped, so the range is
    −1..1. Place kicks use GoalKicking.
  * PowerRating `r = (25 + 0.75·KickingPower)/100`, range 0.25..1.0.
  * Aim error half-width `A = (1 − a) · 8.294°`, applied as a uniform yaw
    offset U(−A, A) for punts, up-and-unders, box kicks, drop kicks and
    restarts.
  * For drop kicks, A is multiplied by 1.5, 2.0 or 3.0 at difficulty settings
    1, 2 or 3.
  * The AI kick-off adds a spread of ± (100 − Kick)/200 to the launch
    components.
* **Goal-kick needle penalty [O]** (ev_61b6c536). With needle error |e|, the
  gauge is multiplied by:
  * 1 if |e| ≤ 1;
  * 0.75 + 0.25·(2 − |e|) if 1 < |e| ≤ 2;
  * 0.75 if |e| > 2.

  An AI place kick also multiplies impulse.x by 1.05 or 0.95, chosen at
  random. A place kick therefore reaches at most 10 + 23 = 33 m/s.
* **Spin at launch [O]** (0x7448b0, ev_3940c1ad). Spin is set in the kicker
  frame, assumed rad/s:

| Kick | Spin |
|---|---|
| Up-and-under, chip | each axis U(−15, 15) |
| Place, drop, kick-off / restart (4, 5, 7, 8, 10) | (0, 1.5, 0), i.e. about the long axis |
| Grubber | (0, −0.5, 0) |
| Quick tap (13) | z = 5 |
| Punt, box kick | none set |

  Together with the ellipsoid contact (§2.4), this spin produces the
  unpredictable bounce of up-and-unders and chips and the end-over-end roll of
  grubbers [I].
* **Drop-goal action speed [O]** (ev_2037da4b). The drop-kick action
  progresses at a rate multiplier
  m = clamp(1/a^DropGoalSpeedExponent, 1, DropGoalMaxSpeed); if a ≤ 0, m is
  the maximum. The values are:

| Difficulty | DropGoalSpeedExponent | DropGoalMaxSpeed |
|---|---|---|
| Easy | 1.25 | 2.0 |
| Normal | 1.3 | 2.5 |
| Hard | 1.32 | 3.0 |

  In a shootout or a standing drop kick, the duration is multiplied by
  DropGoalShootoutModifier: 4.5 on Easy, 4.0 otherwise.
* **Not covered [U]:**
  * the exact rotation order that builds the velocity from heading, aim offset
    and elevation (unk_c58b9c6d);
  * the kick-off landing-target search;
  * whether the punt "wobble" draws reach the ball: half-width 12, 7, 3 or 0 by
    Kick stat band.

### 2.7 Passing, catching and pickup

PENDING: merge from `.omc/research/phys/pass-notes.md` (sub-agent p1-phys-pass, which was running when Claude quota ran out). Anchors: CPass vtable 0x8f68bc; launcher 0x621b20; CCatch 0x8f591c; CPickup 0x8f6cc8; players_PassQualityWithFatigue 0x608b70.

### 2.8 Tackling and contact

PENDING: merge from `.omc/research/phys/tackle-notes.md` (sub-agent p1-phys-tackle, which was running when Claude quota ran out). Anchors: CTackle vtables 0x8f7614/0x8f7620; code 0x754f00–0x75b000; CRun 0x8f70f8 (sidestep/hand-off); CDive 0x8f5fd8; string 0x8f74f8 (broken-tackle chance).

### 2.9 Player locomotion

* **Movement modes [O].** Mode 2 is "run" and mode 3 is "sprint". The mode
  selector (0x6123e0, ev_fc7fa590) picks sprint when both of these hold:
  * the player can sprint;
  * the acceleration factor `1 − Accel/100` (0x656160, ev_73f486db) is below
    the requested urgency.

  Otherwise it picks run. Mode changes log "changing MODE %s".
* **Top speed** `phys_Player_GetMaxSpeed(player, mode)` (0x655f70,
  ev_8e6158b1), with Spd = the Speed attribute (code index 2, 0..100):
  * Run: `v_run = 4.5 + 3.5 · Spd/100` m/s, i.e. 4.5–8.0. The match update
    (0x62ed50) recomputes it every frame for shirts 1–15 of both teams and
    caches it (0x655a40, ev_278292e9). Other callers read the cache
    (0x655ae0 / 0x656cf0).
  * Sprint: a piecewise-linear table (0x655e30, ev_890a05bd). Within each band
    the speed interpolates linearly from the band's lower stat to the next
    band's lower stat (100 for the top band).

| Speed stat | 0–54 | 55–64 | 65–74 | 75–84 | 85–94 | 95–100 |
|---|---|---|---|---|---|---|
| Sprint speed (m/s) | 7.0 → 7.5 | 7.5 → 8.0 | 8.0 → 8.5 | 8.5 → 9.0 | 9.0 → 9.5 | 9.5 |

  * Modifiers, applied in order [O]:
    1. If the override object flags the player (0x69baf0/0x69bb10 key 0x1f;
       drill or created-player overrides [I]), Spd = max(Spd, 80).
    2. If the player's current task type is 3 or 0x21, Spd = 100.
    3. While player + 0xd4 ≥ 0, Spd = Spd/2 (integer). This is a countdown
       decremented by dt in `phys_Player_Update`; it is a stagger or injury
       timer [I].
    4. If the task type is 3, add +2.0 m/s to the result.
    5. A negative result becomes 5.0.
  * In tutorials, run is fixed at 7.5 and sprint at 9.0.
* **Acceleration** `phys_Player_AccelIncrement` (0x655b40, ev_fc311b1c). The
  result is written to actor + 0x10c (0x60cfe0) as a per-step speed increment
  Δv = Δ/(T·50):
  * Below run speed, Δ = v_run and T = 1.0 s.
  * At or above run speed in sprint mode, Δ = v_sprint − v_run (≥ 0), and T
    comes from the Acceleration stat (byte +0x24):

| Accel stat | ≥ 90 | 75–89 | 65–74 | 40–64 | < 40 |
|---|---|---|---|---|---|
| T to go from run to sprint (s) | 0 → 1 | 1 → 2 | 2 → 3 | 3 → 4 | 5 |

    T rises linearly within each band as the stat falls from the band's top.
    If T < 0.01, the increment is 1.0, which means instant.
  * The Accel stat is forced to max(·, 90) by the same override flag, and to
    100 for task types {1, 2, 3, 10, 14, 0x21} or in tutorials.
  * Within 0.5 m/s of the actor's current top speed, the increment becomes
    min(2·previous, 0.1).
  * How the actor consumes the increment, in particular whether "/50" means a
    50 Hz step, is unknown (unk_ed64a5d8). Rebuild assumption [I]: speed rises
    by Δ/T m/s per second.
* **Sprint energy** (player + 0x3c) in `phys_Player_Update` (0x60cfe0,
  ev_41b7d91b). Each frame, with current speed s and run speed v_run:
  * **Drain.** If s > 1.05 · v_run, energy −= s · dt · f_pitch · f_fatigue.
    f_pitch = 2 on pitch condition 4, otherwise 1. f_fatigue is 0 when the
    Fatigue option is 0, otherwise it maps option 0..100 onto 0.75..1.5
    (0x60ccd0, local).
  * **Regeneration**, applied every frame and also while sprinting: +10/s if
    s ≤ 0.8 · v_run, otherwise +5/s.
  * **Clamp** to [−1, E_max]. E_max is `players_EnergyCurve` (Stamina, match
    fatigue time) (0x656190, players lead): 40..100.
  * Task type 0x14 holds energy at ≥ 15.
  * Sprint gating (0x656350, local): starting a sprint needs energy > 8;
    continuing needs energy > 0.
  * Worked example: sprinting at 9 m/s with fatigue factor 1 nets −4/s, so a
    full 100-point bar lasts about 25 s.
* **Actor speed and turning [O/I]** (`FIFAActor::Update` 0x723f30,
  ev_6999cb56). The update parameter is in **1/50 s ticks**: it is divided by
  50 wherever seconds are needed.
  * Speed (+0x6c) moves toward the desired speed (+0x68) by at most ±(+0x10c)
    × ticks per update. The same limit applies to acceleration and
    deceleration. This resolves unk_ed64a5d8 [I]: Δv/T/50 per tick equals
    Δv/T m/s per second.
  * Heading (in turns; wrapped to [−0.5, 0.5] by 0x6be4b0) approaches the
    desired heading through a PID-style controller (0x722790). The I term is
    smoothed as (4·I + e)/5. The gains are object fields (values unknown).
  * The heading step is clamped to ±ticks × k_turn, where k_turn = 0.02
    turn/tick (= 360°/s) when speed > 4 m/s, otherwise 1.0, which is
    effectively unlimited (0x7247a0).
  * The turn-rate state is limited to a change of ±0.05 per update.
  * Clip root motion is the motion lead's (12).

---

## 3. Constants and tunables

These are proposed Godot `Resource` fields. Group them as `BallPhysicsParams`,
`PitchSurfaceParams` (one per pitch condition), `BallPredictorParams`,
`KickParams` (one per kick type), `KickerStatParams`, `LocomotionParams` and
`SimTimingParams`.

| Resource.field | Value | Unit | Where used | Evidence |
|---|---|---|---|---|
| SimTimingParams.ball_substep | 0.005 | s | 0x4b9450 | ev_b38863b5 |
| SimTimingParams.base_speed | 1.0 (0.5 slow-mo unlock) | × | 0x4f4040/0x4f40a0 | ev_01118989 |
| SimTimingParams.difficulty_speed | 1.10 / 1.10 / 1.15 | × | 0x632c10 | AI lead (08) |
| BallPhysicsParams.gravity | −9.8 (−30 high, −5 low unlock) | m/s² | global 0x98ddac | ev_01118989, ev_97f2f6b5 |
| BallPhysicsParams.mass | 0.435 | kg | 0x622a90, 0x4b3c00 | ev_97f2f6b5 |
| BallPhysicsParams.semi_axes | (0.095, 0.145, 0.095) | m | 0x4b6190, 0x4b4ed0 | ev_40007ba0, ev_7aed4b04 |
| BallPhysicsParams.inertia_factor | 2/3 × m × 0.145² | kg·m² | 0x4b3c00 | ev_1a9f12a8 |
| BallPhysicsParams.initial_spin_jitter | 0.05 | rad/s per axis | 0x4b3c00 | ev_1a9f12a8 |
| BallPhysicsParams.air_density | 1.29 | kg/m³ | 0x4b6190 | ev_40007ba0 |
| BallPhysicsParams.cd_low / cd_high | 0.5 / 0.2 | — | 0x4b6190 | ev_40007ba0 |
| BallPhysicsParams.cd_speed_lo / hi | 15.0 / 20.5 | m/s | 0x4b6190 | ev_40007ba0 |
| BallPhysicsParams.ref_area_slow | 0.045 | m² | 0x4b6190 | ev_40007ba0 |
| BallPhysicsParams.wind_kmh_to_ms | 1/3.6 | — | 0x4b6190 | ev_40007ba0 |
| BallPhysicsParams.drag_only_in_goal_kicks | true | bool | 0x68c4d0/0x68c530 | ev_34f726f5 |
| BallPhysicsParams.max_contacts | 16 | — | 0x4b6920 | ev_e4d8b68a |
| BallPhysicsParams.mesh_query_radius | 0.145 | m | 0x4b4ed0 | ev_7aed4b04 |
| BallPhysicsParams.rolling_bound_scale | 10 | × f4 | 0x4b6920 | ev_e4d8b68a |
| PitchSurfaceParams[0..5] | see §2.4 table | — | 0x98e100 | ev_ae86498d |
| PitchSurfaceParams.forced_index_stadiums | {0x19, 0x1d} → 2 | id | 0x4ba6f0 | ev_95ba8a18 |
| BallPredictorParams.rest_height | 0.1 | m | 0x6217f0, 0x746320 | ev_95b99e84 |
| BallPredictorParams.restitution_y | 0.55 (v_y ← v_y − 1.55·v_y) | — | 0x6217f0 | ev_95b99e84 |
| BallPredictorParams.bounce_xz_keep | 0.885 | — | 0x6217f0 | ev_95b99e84 |
| BallPredictorParams.roll_decel | 0.8 | 1/s | 0x6217f0 | ev_95b99e84 |
| BallPredictorParams.roll_hop_threshold | 0.01 | s | 0x6217f0 | ev_95b99e84 |
| GoalGeometry.try_line_z | 50.0 | m | header 0x8d6d3c… | ev_fdabdb0b |
| GoalGeometry.in_goal_depth | 14.1 | m | header | ev_fdabdb0b |
| GoalGeometry.twenty_two_z | 28.0 | m | header | ev_fdabdb0b |
| GoalGeometry.crossbar_height | 3.0 | m | static init 0x8b28b0 | local |
| GoalGeometry.goal_width | 5.6 | m | static init 0x8b28d0 | local |
| GoalGeometry.post_low_zone | 2.26 | m | static init 0x8b28f0, 0x4a8340 | ev_d5e56fb2 |
| GoalGeometry.post_hit_band | 5.0 (z and x), 0.3 (crossbar) | m | 0x4a8340 | ev_d5e56fb2 |
| GoalGeometry.upright_radius / top | 0.045 / 13.41 | m | Stadium.collision | data |
| GoalGeometry.pad_box | x 2.60–3.09, z ±0.245, h 2.0 | m | Stadium.collision | data |
| KickParams[type].v_lo/v_hi/e_lo/e_hi | §2.6 table | m/s, ° | 0x8c62c0–0x8c64f0 | §2.6 |
| KickParams.grubber_elev_jitter | ±5 | ° | 0x743e20 | ev_93f613c7 |
| KickParams.chip_speed / chip_elev | 12.2 / 10 | m/s, ° | 0x7493b0 / 0x749770 | ev_d943b4b8 / ev_b90e0ccd |
| KickParams.spin[type] | §2.6 | rad/s [I] | 0x7448b0 | ev_3940c1ad |
| KickerStatParams.power_rating | (25 + 0.75·KP)/100 | — | 0x7418c0 | ev_54e761c7 |
| KickerStatParams.aim_error_scale | 8.294 | ° per (1 − a) | 0x746ff0 | ev_76188f23 |
| KickerStatParams.dropkick_aim_mult | 1.5 / 2.0 / 3.0 | × | 0x747230 | ev_61b6c536 |
| KickerStatParams.needle_floor | 0.75 | × | 0x747230 | ev_61b6c536 |
| KickerStatParams.ai_impulse_x_jitter | ±0.05 | × | 0x747230 | ev_61b6c536 |
| LocomotionParams.run_speed_min/max | 4.5 / 8.0 | m/s | 0x655f70 | ev_8e6158b1 |
| LocomotionParams.sprint_table | §2.9 | m/s | 0x655e30 | ev_890a05bd |
| LocomotionParams.task3_speed_bonus | 2.0 | m/s | 0x655f70 | ev_8e6158b1 |
| LocomotionParams.override_speed_floor / accel_floor | 80 / 90 | stat | 0x655f70 / 0x655b40 | ev_8e6158b1, ev_fc311b1c |
| LocomotionParams.accel_time_table | §2.9 | s | 0x655b40 | ev_fc311b1c |
| LocomotionParams.run_accel_time | 1.0 | s | 0x655b40 | ev_fc311b1c |
| LocomotionParams.sprint_drain_threshold | 1.05 × v_run | — | 0x60cfe0 | ev_41b7d91b |
| LocomotionParams.regen_fast / slow | 10 / 5 | energy/s | 0x60cfe0 | ev_41b7d91b |
| LocomotionParams.regen_fast_threshold | 0.8 × v_run | — | 0x60cfe0 | ev_41b7d91b |
| LocomotionParams.heavy_pitch_drain_mult | 2 (pitch cond 4) | × | 0x60cfe0 | ev_41b7d91b |
| LocomotionParams.fatigue_option_range | 0.75 – 1.5 | × | 0x60ccd0 | local |
| LocomotionParams.sprint_start / keep energy | > 8 / > 0 | energy | 0x656350 | local |
| LocomotionParams.tutorial_run / sprint | 7.5 / 9.0 | m/s | 0x655f70 | ev_8e6158b1 |

(Pass and tackle constants pending; see §2.7 and §2.8.)

---

## 4. Data structures that matter

* **Ball state:**
  * position (vec3, m) and linear velocity (vec3, m/s);
  * orientation (3×3, body y = long axis) and angular velocity (rad/s);
  * mass and inverse inertia;
  * a contact list of up to 16 entries. Each entry holds a point, normal,
    depth and type (0 = ground, 1 = mesh);
  * an optional keyframed path. While one is attached (BallManager + 0xf8),
    it overrides the rigid body, which follows sampled positions; this is used
    for animation-held and scripted ball moves (0x621010, local);
  * a sub-step accumulator (s).
* **Ball path predictor:** position, velocity and external force (gravity ×
  mass) as plain vectors. Advancing it is stateless.
* **Match environment:**
  * pitch condition int 0..5 (default 2), which selects PitchSurfaceParams and
    the sprint-drain multiplier;
  * wind level int 0..3 (default 0) and wind vector in km/h (default 0);
  * temperature int (default 2) and sky int; these have no physics use found.

  Missions can set these through `<WEATHER pitch temp precipitation>` and
  `<WIND power x y z>` (0x4bf0d0, local).
* **Stadium collision mesh:** triangles (plane index + 3 vertex indices),
  planes (n, d) and vertices (xyz, w), plus an unknown trailing block, all in
  metres in pitch space.
* **Kick object:**
  * type code, gauge, PowerPerSecond and PowerRating;
  * accuracy index, aim offset, launch speed and elevation;
  * spin vector, state and flags.
* **Player locomotion:**
  * current mode (2 or 3) and sprint energy (float);
  * stagger/injury timer (float, ≥ 0 while active);
  * cached run speed;
  * the actor fields top speed (+0x80) and acceleration increment (+0x10c).

---

## 5. Mod hooks (PLAN §1d)

Data overrides; every one is a field above:
* gravity (the unlock modes already exist as presets);
* sim speed and difficulty speed;
* ball mass, shape, inertia and spin jitter;
* drag on/off scope (classic: goal kicks only; a "modern" mod could enable it
  for all kicks);
* Cd curve, air density and wind units;
* the PitchSurfaceParams table, including turning on the compiled-out random
  bounce term f2;
* predictor constants (AI bounce judgement);
* every per-kick-type speed and elevation range;
* spin per kick type;
* power-rating and aim-error formulas;
* the GoalKickSettings XML (already data in the original);
* run, sprint and acceleration tables;
* sprint-energy drain and regeneration;
* tackle and pass tables (§2.7, §2.8).

Script hooks:
* `on_ball_contact(contact)`, for custom bounce or post behaviour;
* `on_kick_launch(kick) -> velocity, spin`;
* `on_pass_launch`, `on_catch_resolve` and `on_tackle_resolve`, which return a
  probability override;
* `wind_provider(match) -> vec3 km/h`. This must be deterministic and is
  seeded from the match RNG.

Every random draw (grubber elevation jitter, aim offset, spin, initial spin,
AI spreads, catch, tackle and fumble rolls) must come from the seeded match RNG
so that replays stay deterministic.

---

## 6. Acceptance tests (GDScript-checkable)

1. With gravity −9.8 and drag off, a ball launched at 20 m/s and 45° from
   y = 0.1 m lands back at y = 0.1 after 2.886 s ± 0.01 s, having travelled
   40.82 m ± 0.1 m horizontally.
2. `BallPredictor.advance()` from (0, 2.1, 0) with v = (5, 0, 0) under
   gravity: the first ground contact is at t = √(2·2.0/9.8) = 0.639 s. Right
   after it, v_y = +0.55 × 6.261 = 3.444 m/s and v_x = 0.885 × 5 = 4.425 m/s.
3. When the predictor's hop time drops below 0.01 s after a bounce, the ball
   switches to rolling. Its horizontal acceleration is exactly −0.8·v_xz.
4. Drag is zero in open play: outside the goal-kick state the aero force
   returns (0,0,0) for any velocity.
5. In the goal-kick state, with v = (0, 0, 10) m/s, Cd = 0.5, and the ball long
   axis perpendicular to the flow (A = π·0.095·0.145), F_z = −½·1.29·0.5·0.04327·100
   = −1.395 N ± 0.01. With v = (0, 0, 25), Cd = 0.2.
6. With the wind on and W = (3.6, 0, 0) km/h, a stationary ball has
   u = (1, 0, 0) m/s and the aero force points +x (downwind), with
   magnitude ½·1.29·0.5·A·1.
7. With pitch condition 2, a ball dropped belly-down (long axis horizontal)
   bounces with restitution 0.5. Dropped point-down (long axis vertical), it
   bounces with restitution 0.4 (k = f0 or f1, e = k − 1, friction-free
   test).
8. `PitchSurface.get(cond)` returns the §2.4 row. Stadium ids 0x19 and 0x1d
   return row 2 for every cond.
9. A punt with gauge 1 by a KickingPower-100 kicker leaves at 22.304 m/s and
   42.5°. With KickingPower 0 and gauge 1, it leaves at
   16.081 + 6.223 × 0.25 = 17.637 m/s and still at 42.5°.
10. A chip kick always leaves at 12.2 m/s and 10° whatever the gauge or the
    stats.
11. Aim error half-width: Kick 100 → 0°, Kick 50 → 8.294°, Kick 0 → 16.588°.
    A drop kick at difficulty setting 3 triples it.
12. Place-kick power: gauge 1, KickingPower 100, needle error 0 gives
    33.0 m/s. Needle error 1.5 gives 10 + 23 × 0.875 = 30.125 m/s.
13. Sprint speed: stat 55 → 7.5, stat 60 → 7.75, stat 90 → 9.25, stat 99 →
    9.5 m/s. Run speed with stat 50 is 6.25 m/s.
14. Acceleration time from run to sprint: stat 100 → 0 s (instant), stat 90 →
    1.0 s, stat 75 → 2.0 s, stat 52.5 → 3.5 s, stat 30 → 5.0 s.
15. Sprint energy at 9 m/s with v_run = 7 m/s and fatigue factor 1 changes by
    −9 + 5 = −4 per second. At 5 m/s (≤ 0.8·7 = 5.6) it changes by +10 per
    second. On pitch condition 4 the drain is −18 + 5 = −13 per second.
16. A player whose energy is 5 and who is not sprinting cannot start a
    sprint. One who is already sprinting with energy 5 continues.
17. A ball collision at (1.0, 3.05, 50.1) raises POST_HIT with part 2
    (crossbar). One at (2.6, 3.05, 50.1) raises part 1, because |x| > 2.8 − 0.3.
    One at (2.85, 1.0, 50.0) raises part 3. One at (2.85, 6.0, 50.0) raises
    part 1.
18. The ball rigid body takes floor((acc + dt)/0.005) sub-steps per frame and
    carries the remainder over.

(Pass and tackle tests pending.)

---

## 7. Open questions and unknowns

| ID | Question | Evidence |
|---|---|---|
| unk_a9fd88e9 | Source and cap of the frame dt; is there a frame limiter? (The PC build is variable-step.) | ev_8d11a3c8 |
| unk_21095a01 | How the wind vector W (km/h) is produced from wind level 0..3 or the mission WIND tag; exact wind-enable predicate 0x44fbb0 | ev_40007ba0, ev_34f726f5 |
| unk_ed64a5d8 | Resolved [I]: actor update ticks are 1/50 s (ev_6999cb56). Still to be checked: the heading PID gains | ev_fc311b1c, ev_6999cb56 |
| unk_c58b9c6d | Kick velocity vector construction (heading, aim yaw, elevation order); kick-off target search; punt wobble | kick notes |
| unk_796e3e94 | Kick wind-up durations T per animation, which set the gauge fill time | kick notes |
| — | Names of pitch conditions 0..5 and of task types 3, 0x14, 0x21 | [U] |
| — | Touchline half-width used by the code. The stadium model suggests ±33.7 m; the rules lead to confirm | data |
| — | Layout of the trailing block of `Stadium.collision` (spatial index?) | data |
| — | Exact rolling/twist torque form for f4 in the solver | ev_e4d8b68a |

(Pass and tackle unknowns pending; see the sub-agent notes and record_unknown entries.)

---

## 8. Confidence summary

| Topic | Confidence | Basis |
|---|---|---|
| Units, axes, goal geometry | high | header constants + collision mesh + pitch-line model agree |
| Gravity and its unlock variants | high | decompiled setters |
| Ball mass, shape, inertia | high | decompiled body init and drag code |
| Aero model (Cd curve, area, per-axis form, goal-kick-only scope) | high | decompiled; wind generation unknown |
| Rigid-body sub-step 0.005 s | high | constant and accumulator loop |
| Contact restitution, friction and surface table | high for values; medium for the exact LCP rows (rolling term) | decompiled solver |
| Analytic predictor | high | fully decompiled |
| Kick launch tables, power rating, aim error, spin | high | sub-agent, decompiled |
| Kick vector construction, gauge fill seconds | low | unresolved |
| Run/sprint speeds, acceleration table, sprint energy | high for formulas; medium for how acceleration is applied | decompiled |
| Frame timing (variable dt, speed scale) | medium | dt source unknown |
| Passing / catching / pickup | pending | §2.7 |
| Tackling / contact | pending | §2.8 |

**Not covered in this pass:**
* turning and agility;
* player-versus-player collision avoidance;
* the ball held in hand (animation-attached);
* scrum, ruck and maul pushing physics (set-piece lead);
* the trailing collision-mesh block;
* kick-off target selection;
* AI kick target choice (AI lead).
