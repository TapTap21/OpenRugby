# S1-core: match simulation, flow, clock, pitch, data model

- Slice: S1 (core). Architecture: [ADR-004](../adr/ADR-004-core-architecture.md), ADR-001.
- Depends on: nothing game-specific. Phase 1 RE later fills data, never code.
- Reimplementation, not a port (PLAN section 4 rule 0, CONVENTIONS "Reimplementation, not a
  port"): only Rugby 08's observable behaviour and numeric constants are carried over, always
  into named Resource fields with units. Names, structure, update order and data layouts are
  ours; when RE findings land they fill data, never reshape these classes after the original.
- Out of scope: ball, players on the pitch, rules/laws, AI, rendering, mod loading
  ([S1-modloader](S1-modloader.md)), device input ([S9-input](S9-input.md)).

Words: **must** is required and tested. "PROVISIONAL" marks a field whose name, range or default
Phase 1 may change; it still exists and is tested for presence and default. "TBC-RE" marks a
default taken from real-world World Rugby law that RE must confirm against Rugby 08.

## 1. Files and classes

All scripts are typed GDScript, follow `docs/CONVENTIONS.md`, and have `class_name`.

| Path | `class_name` | Base |
|---|---|---|
| `game/match/match_sim.gd` | `MatchSim` | `RefCounted` |
| `game/match/sim_rng.gd` | `SimRng` | `RefCounted` |
| `game/match/sim_system.gd` | `SimSystem` | `RefCounted` |
| `game/match/match_clock.gd` | `MatchClock` | `RefCounted` |
| `game/match/match_config.gd` | `MatchConfig` | `Resource` |
| `game/match/match_runner.gd` | `MatchRunner` | `Node` |
| `game/match/match_replay.gd` | `MatchReplay` | `RefCounted` (static helpers) |
| `game/match/input_frame.gd` | `InputFrame` | `RefCounted` |
| `game/match/input_source.gd` | `InputSource` | `RefCounted` |
| `game/match/input_log.gd` | `InputLog` | `RefCounted` |
| `game/match/replay_header.gd` | `ReplayHeader` | `RefCounted` |
| `game/match/replay_input_source.gd` | `ReplayInputSource` | `InputSource` |
| `game/match/flow/match_state_ids.gd` | `MatchStateIds` | `RefCounted` (constants only) |
| `game/match/flow/match_triggers.gd` | `MatchTriggers` | `RefCounted` (constants only) |
| `game/match/flow/match_flow_config.gd` | `MatchFlowConfig` | `Resource` |
| `game/match/flow/match_state_def.gd` | `MatchStateDef` | `Resource` |
| `game/match/flow/match_transition_def.gd` | `MatchTransitionDef` | `Resource` |
| `game/match/flow/match_state_machine.gd` | `MatchStateMachine` | `RefCounted` |
| `game/match/flow/match_condition.gd` | `MatchCondition` | `Resource` |
| `game/match/flow/conditions/condition_ticks_in_state.gd` | `ConditionTicksInState` | `MatchCondition` |
| `game/match/flow/conditions/condition_period_expired.gd` | `ConditionPeriodExpired` | `MatchCondition` |
| `game/match/flow/conditions/condition_all.gd` | `ConditionAll` | `MatchCondition` |
| `game/match/flow/default_match_flow.tres` | (a `MatchFlowConfig`) | |
| `game/match/pitch/pitch_geometry.gd` | `PitchGeometry` | `Resource` |
| `game/match/pitch/default_pitch.tres` | (a `PitchGeometry`) | |
| `game/data/player_profile.gd` | `PlayerProfile` | `Resource` |
| `game/data/player_attribute_schema.gd` | `PlayerAttributeSchema` | `Resource` |
| `game/data/team.gd` | `Team` | `Resource` |
| `game/data/kit.gd` | `Kit` | `Resource` |
| `game/data/stadium.gd` | `Stadium` | `Resource` |
| `game/data/rules_config.gd` | `RulesConfig` | `Resource` |
| `game/data/difficulty_profile.gd` | `DifficultyProfile` | `Resource` |
| `game/data/camera_preset.gd` | `CameraPreset` | `Resource` |
| `game/data/defaults/default_rules.tres` | (a `RulesConfig`) | |
| `game/data/defaults/default_attribute_schema.tres` | (a `PlayerAttributeSchema`) | |
| `game/data/defaults/default_difficulty.tres` | (a `DifficultyProfile`) | |
| `game/data/defaults/default_camera_preset.tres` | (a `CameraPreset`) | |

Patchability rule (the mod loader depends on it): every data field is a typed `@export` var. No
data in non-exported vars, no setters with side effects on data Resources, nested data is an
exported `Resource` field or a typed `Array`/`Dictionary` of them.

## 2. Simulation

### 2.1 `SimRng`

Wraps one `RandomNumberGenerator` (PCG32).

- `_init(p_seed: int)`; read-only `seed: int` (the constructor value).
- `next_int() -> int` (unsigned 32-bit, like `randi()`), `range_int(from: int, to: int) -> int`
  (inclusive), `next_float() -> float` in [0, 1), `range_float(from: float, to: float) -> float`,
  `chance(probability: float) -> bool` (true when `next_float() < probability`).
- `get_state() -> int`, `set_state(state: int) -> void`.

### 2.2 `InputFrame` (the sim's only input)

One tick of input for every controller slot. Shape is fixed at construction.

- `const AXIS_MAX: int = 127`
- `_init(p_slot_count: int = 1, p_axes_per_slot: int = 2)`
- `var tick: int` (0-based index of the tick it belongs to)
- read-only `slot_count: int`, `axes_per_slot: int`
- `buttons: PackedInt64Array` (size `slot_count`; bit `b` of `buttons[s]` = button action `b` held)
- `axes: PackedInt32Array` (size `slot_count * axes_per_slot`, slot-major; each in [-127, 127])
- `is_held(slot: int, bit: int) -> bool`, `set_held(slot: int, bit: int, held: bool) -> void`
  (bits 0..62)
- `get_axis(slot: int, axis: int) -> int`, `set_axis(slot: int, axis: int, value: int) -> void`
  (clamps to [-127, 127])
- `clear() -> void` (all buttons 0, all axes 0, tick unchanged)
- `copy_from(other: InputFrame) -> void` (same shape required; copies tick, buttons, axes)
- `equals(other: InputFrame) -> bool` (shape, tick, buttons and axes equal)

Bit and axis meaning comes from the input action set (S9); the core never names actions.

### 2.3 `SimSystem`

Base for later subsystems (ball, players, rules, AI). Overridable methods:
`system_id() -> StringName` (default `&"system"`), `setup(sim: MatchSim) -> void`,
`tick(sim: MatchSim) -> void`, `snapshot() -> Dictionary` (default `{}`).

### 2.4 `MatchClock`

- `_init(p_period_count: int, p_period_ticks: int, p_game_seconds_per_period: int)`
- vars: `period: int` (1-based, starts 1), `period_count: int`, `period_ticks: int`,
  `elapsed_ticks: int` (in current period, starts 0), `game_seconds_per_period: int`
- `advance() -> void`: `elapsed_ticks += 1`, no cap (rugby plays past time).
- `is_period_expired() -> bool`: `elapsed_ticks >= period_ticks`.
- `is_last_period() -> bool`: `period >= period_count`.
- `start_next_period() -> void`: `period += 1`, `elapsed_ticks = 0`.
- `game_time_seconds() -> int`: displayed match time with integer maths,
  `(period - 1) * game_seconds_per_period + (elapsed_ticks * game_seconds_per_period) / period_ticks`.

### 2.5 `MatchSim`

```
class_name MatchSim extends RefCounted
signal state_changed(from_state: StringName, to_state: StringName)
signal period_started(period: int)
signal period_ended(period: int)
signal finished
const TICKS_PER_SECOND: int = 60
var config: MatchConfig      # read-only after _init
var rng: SimRng
var clock: MatchClock
var flow: MatchStateMachine
var tick_count: int          # ticks executed so far
func _init(p_config: MatchConfig)
func is_valid() -> bool
func add_system(system: SimSystem) -> void
func tick(frame: InputFrame) -> void
func raise_trigger(trigger: StringName) -> void
func current_state() -> StringName
func is_finished() -> bool
func is_held(slot: int, bit: int) -> bool
func just_pressed(slot: int, bit: int) -> bool
func just_released(slot: int, bit: int) -> bool
func get_axis(slot: int, axis: int) -> int
func snapshot() -> Dictionary
func state_hash() -> String
```

Construction: if `config.validate()` returns errors, the sim is invalid (`is_valid()` false,
`push_error` once, `tick` is a no-op). Otherwise: `rng = SimRng.new(config.seed)`;
`clock = MatchClock.new(config.rules.period_count, config.period_real_seconds * TICKS_PER_SECOND,
config.rules.period_game_seconds)`; `flow` starts in `config.flow.initial_state`; two
preallocated `InputFrame`s of shape `(config.slot_count, config.axes_per_slot)` hold the current
and previous input, both cleared.

`add_system` is allowed only before the first tick; afterwards it `push_error`s and ignores the
call. `setup(sim)` is called on each system when it is added.

`tick(frame)` does exactly this, in order:

1. If invalid or finished, return. Nothing changes.
2. `tick_count += 1` (so during the rest of the tick, `tick_count` is the 1-based number of the
   tick being executed, and every signal emitted in this tick sees that value).
3. Copy the current input into previous; copy `frame` into current (shape mismatch: `push_error`,
   treat as an all-zero frame).
4. Call `tick(self)` on every system in registration order.
5. If the current state has `clock_runs`, `clock.advance()`.
6. `flow.ticks_in_state += 1`.
7. Evaluate the current state's transitions in list order against the pending triggers; the first
   that fires is applied (2.7). At most one transition per tick.
8. Clear pending triggers (all are consumed this tick, used or not).

`raise_trigger` appends to the pending list. Triggers raised by systems in step 4 or by callers
between ticks are evaluated in step 7 of the current (or next) tick.

Input edges: `just_pressed` is held in current and not in previous; `just_released` the reverse.
Before the first tick both frames are zero.

`snapshot()` returns a `Dictionary` built in this key order: `tick`, `rng_seed`, `rng_state`,
`state`, `ticks_in_state`, `period`, `elapsed_ticks`, `finished`, `pending_triggers`
(`Array[StringName]`), `input_buttons`, `input_axes`, `systems` (array of
`{"id": system_id(), "data": snapshot()}` in registration order).
`state_hash()` is the lowercase hex SHA-256 (`HashingContext.HASH_SHA256`) of
`var_to_bytes(snapshot())`.

Purity: files under `game/match/` (except `match_runner.gd`) must not reference `EventBus`,
`Input`, `Time`, `OS.get_ticks_msec`/`OS.get_ticks_usec`, or call the global `randi`, `randf`,
`randfn`, `randi_range`, `randf_range`, `randomize` or `seed` functions. The same ban on global
random, `Time`, `OS.get_ticks_*` and `Input` applies to `game/ball/`, `game/player/`,
`game/rules/`, `game/setpiece/` and `game/ai/`.

### 2.6 Match flow data

`MatchStateIds` constants: `PRE_MATCH = &"pre_match"`, `KICK_OFF = &"kick_off"`,
`IN_PLAY = &"in_play"`, `STOPPAGE = &"stoppage"`, `HALF_TIME = &"half_time"`,
`FULL_TIME = &"full_time"`.

`MatchTriggers` constants: `KICK_OFF_TAKEN = &"kick_off_taken"`,
`WHISTLE_BLOWN = &"whistle_blown"`, `PLAY_RESUMED = &"play_resumed"`,
`RESTART_KICK_OFF = &"restart_kick_off"`.

`MatchTransitionDef` (`Resource`):
`enum PeriodEffect { NONE, START, ADVANCE }`; `@export var to: StringName`;
`@export var trigger: StringName = &""` (empty = no trigger needed);
`@export var condition: MatchCondition` (null = no condition);
`@export var period_effect: PeriodEffect = PeriodEffect.NONE`.
It fires when (`trigger` is empty or is in the pending triggers) and (`condition` is null or
`condition.is_met(sim)`).

`MatchStateDef` (`Resource`): `@export var id: StringName`, `@export var clock_runs: bool = false`,
`@export var ends_period: bool = false`, `@export var terminal: bool = false`,
`@export var transitions: Array[MatchTransitionDef] = []`.

`MatchFlowConfig` (`Resource`): `@export var initial_state: StringName = &"pre_match"`,
`@export var states: Array[MatchStateDef] = []`, `get_state(id: StringName) -> MatchStateDef`
(null if absent), `validate() -> PackedStringArray` with one error per problem: empty or duplicate
state id; `initial_state` not found; transition `to` not found; a transition with empty trigger
and null condition; no state with `terminal = true`.

`MatchCondition` (`Resource`): `is_met(sim: MatchSim) -> bool`, base returns false.
- `ConditionTicksInState`: `@export var ticks: int = 1`; met when `sim.flow.ticks_in_state >= ticks`.
- `ConditionPeriodExpired`: `enum Which { ANY, LAST, NOT_LAST }`, `@export var which: Which = ANY`;
  met when `sim.clock.is_period_expired()` and (`ANY`, or `LAST` and `is_last_period()`, or
  `NOT_LAST` and not `is_last_period()`).
- `ConditionAll`: `@export var conditions: Array[MatchCondition] = []`; met when all are met
  (empty list is met).

`MatchStateMachine` (`RefCounted`): `_init(p_config: MatchFlowConfig)`, vars `config`,
`current: StringName` (starts at `initial_state`), `ticks_in_state: int` (starts 0),
`find_transition(sim: MatchSim, triggers: Array[StringName]) -> MatchTransitionDef` (first that
fires, or null), `current_def() -> MatchStateDef`.

### 2.7 Applying a transition

In this order: set `current = to`, `ticks_in_state = 0`; emit `state_changed(from, to)`; if
`period_effect == START` emit `period_started(clock.period)`; if `ADVANCE` call
`clock.start_next_period()` then emit `period_started(clock.period)`; if the new state has
`ends_period` emit `period_ended(clock.period)`; if it has `terminal`, mark finished and emit
`finished`.

### 2.8 Default flow (`default_match_flow.tres`), placeholder until S3

Initial state `pre_match`. Transitions listed in evaluation order. Entries marked P are
placeholders so the skeleton runs without rules; S3 replaces them in data.

| State | clock_runs | ends_period | terminal | Transitions (to: trigger / condition / effect) |
|---|---|---|---|---|
| `pre_match` | no | no | no | `kick_off`: TicksInState(1), START (P) |
| `kick_off` | no (TBC-RE) | no | no | `in_play`: `kick_off_taken`; `in_play`: TicksInState(1) (P) |
| `in_play` | yes | no | no | `stoppage`: `whistle_blown`; `half_time`: PeriodExpired(NOT_LAST) (P); `full_time`: PeriodExpired(LAST) (P) |
| `stoppage` | yes (TBC-RE) | no | no | `half_time`: PeriodExpired(NOT_LAST); `full_time`: PeriodExpired(LAST); `in_play`: `play_resumed`; `kick_off`: `restart_kick_off` |
| `half_time` | no | yes | no | `kick_off`: TicksInState(1), ADVANCE (P) |
| `full_time` | no | yes | yes | none |

With period length P ticks and 2 periods, a match with no triggers runs: tick 1 to `kick_off`
(period 1 starts), tick 2 to `in_play`, clock advances on ticks 3..P+2, tick P+2 to `half_time`,
tick P+3 to `kick_off` (period 2), tick P+4 to `in_play`, tick 2P+4 to `full_time`.

## 3. Runner, input log and replay

### 3.1 `InputSource`

Base class. `fill_frame(tick: int, frame: InputFrame) -> bool` fills `frame` for `tick` and
returns true, or returns false when no more input exists (base: clears the frame, returns true).
`layout_hash() -> String` identifies the action layout (base: `""`). S9's `InputSampler` extends it.

### 3.2 `ReplayHeader` and `InputLog`

`ReplayHeader` vars: `format_version: int = 1`, `game_version: String`, `seed: int`,
`mod_set_hash: String`, `action_layout_hash: String`, `tick_rate: int = 60`, `slot_count: int = 1`,
`axes_per_slot: int = 2`. `to_dict() -> Dictionary`, `static from_dict(d: Dictionary) -> ReplayHeader`
(null when a key is missing or mistyped), `is_compatible_with(p_mod_set_hash: String,
p_action_layout_hash: String) -> bool` (both equal, and `tick_rate == MatchSim.TICKS_PER_SECOND`).

`InputLog`: `const FORMAT_VERSION: int = 1`, `var header: ReplayHeader`,
`_init(p_header: ReplayHeader)`, `append(frame: InputFrame) -> void` (frame shape must match the
header, else `push_error` and ignore; frames are stored in packed arrays, tick = index),
`frame_count() -> int`, `read_frame(index: int, into: InputFrame) -> bool` (false when out of
range; sets `into.tick = index`), `to_bytes() -> PackedByteArray`,
`static from_bytes(bytes: PackedByteArray) -> InputLog` (null when invalid or
`format_version` is newer than `FORMAT_VERSION`), `save(path: String) -> Error`,
`static load_file(path: String) -> InputLog`.

`ReplayInputSource`: `_init(p_log: InputLog)`; `fill_frame` reads frame `tick` and returns false
past the end; `layout_hash()` returns the header's `action_layout_hash`.

### 3.3 `MatchReplay`

`static run(config: MatchConfig, log: InputLog, mod_set_hash: String,
systems: Array[SimSystem] = []) -> MatchSim`. Returns null if
`log.header.is_compatible_with(mod_set_hash, log.header.action_layout_hash)` is false (that is,
the mod set differs). Otherwise duplicates `config`, sets its `seed` to `log.header.seed`,
builds a sim, adds `systems`, ticks once per logged frame (stops early if finished) and returns it.

### 3.4 `MatchRunner` (`Node`)

```
signal ticked(tick: int)
signal input_ended
var sim: MatchSim            # null until start
var input_log: InputLog
func start(config: MatchConfig, source: InputSource, systems: Array[SimSystem] = [],
		mod_set_hash: String = "") -> Error
func stop() -> void
func is_running() -> bool
func step_once() -> bool
func interpolation_fraction() -> float
```

- `start` returns `ERR_UNCONFIGURED` if `Engine.physics_ticks_per_second !=
  MatchSim.TICKS_PER_SECOND`, `ERR_INVALID_PARAMETER` if `config.validate()` is not empty;
  otherwise builds the sim, adds systems, creates `input_log` with a header (`game_version` from
  `ProjectSettings` `application/config/version`, `seed`, `mod_set_hash`,
  `source.layout_hash()`, shape from config), connects relays and returns `OK`.
- `step_once`: if not running or finished, return false. Otherwise fill the preallocated frame
  from the source with `tick = sim.tick_count`; if the source returns false, stop, emit
  `input_ended` and return false. Else `sim.tick(frame)`, `input_log.append(frame)`, emit
  `ticked(sim.tick_count)`, return true.
- `_physics_process` calls `step_once()` while running. Nothing in the runner uses `_process`
  for sim work.
- Relays (connected in `start`): `state_changed` to `EventBus.match_state_changed(from, to,
  sim.tick_count)`, `period_started` to `EventBus.match_period_started`, `period_ended` to
  `EventBus.match_period_ended`, `finished` to `EventBus.match_finished(sim.tick_count)`.
  Relays fire synchronously during the tick; listeners must not mutate the sim (ADR-004).
- `interpolation_fraction()` returns `Engine.get_physics_interpolation_fraction()` for
  presenters that interpolate manually.

## 4. Pitch geometry

`PitchGeometry` (`Resource`), metres. Coordinates: origin at the centre of the halfway line,
+Y up, X along the length (try lines at x = ±L/2; `end` is `1` for +X and `-1` for -X),
Z across (touchlines at z = ±W/2).

| Field | Type | Default | Note |
|---|---|---|---|
| `field_length` | float | 100.0 | try line to try line, TBC-RE |
| `field_width` | float | 70.0 | touchline to touchline, TBC-RE |
| `in_goal_depth` | float | 10.0 | try line to dead-ball line (law range 6..22), TBC-RE |
| `line_22_from_try` | float | 22.0 | TBC-RE |
| `line_10_from_halfway` | float | 10.0 | TBC-RE |
| `line_5_from_try` | float | 5.0 | TBC-RE |
| `line_15_from_touch` | float | 15.0 | TBC-RE |
| `line_5_from_touch` | float | 5.0 | TBC-RE |
| `goal_post_gap` | float | 5.6 | inside edges, TBC-RE |
| `crossbar_height` | float | 3.0 | TBC-RE |
| `goal_post_height` | float | 16.0 | PROVISIONAL, visual only |

Methods: `half_length() -> float`, `half_width() -> float`, `try_line_x(end: int) -> float`
(`end * L/2`), `dead_ball_line_x(end: int) -> float` (`end * (L/2 + in_goal_depth)`),
`line_22_x(end: int) -> float` (`end * (L/2 - line_22_from_try)`),
`is_in_field_of_play(p: Vector3) -> bool` (`|x| < L/2` and `|z| < W/2`),
`is_in_goal(p: Vector3, end: int) -> bool` (`L/2 <= end*x < L/2 + in_goal_depth` and `|z| < W/2`),
`is_in_touch(p: Vector3) -> bool` (`|z| >= W/2` and `|x| < L/2`),
`is_beyond_dead_ball_line(p: Vector3) -> bool` (`|x| >= L/2 + in_goal_depth`),
`validate() -> PackedStringArray` (error per non-positive length/width/in-goal/post field, and
when `line_22_from_try >= L/2` or `2 * line_15_from_touch >= W`).
The line-ownership rules above (try line belongs to in-goal, touchline is in touch) are the law;
S3 confirms them against RE.

## 5. Data resources

Every class has `class_name`, `##` docs, typed `@export` fields with the defaults below, and a
`validate() -> PackedStringArray` that returns one message per problem (empty when valid).
Display names that the UI shows as labels are translation keys (`*_key`); proper nouns from the
game database (team and player names) are data, not keys.

**`PlayerAttributeSchema`**: `attribute_ids: Array[StringName]` (PROVISIONAL list),
`position_ids: Array[StringName]` (PROVISIONAL), `min_value: int = 0`, `max_value: int = 100`,
`default_value: int = 50`; `has_attribute(id: StringName) -> bool`,
`clamp_value(value: int) -> int`. validate: `min_value < max_value`, default inside range,
no duplicate ids. `default_attribute_schema.tres` lists attributes `speed`, `acceleration`,
`agility`, `strength`, `stamina`, `handling`, `passing`, `kicking_power`, `kicking_accuracy`,
`tackling`, `breaking_tackles`, `aggression`, `discipline`, `lineout`, `scrummaging` and positions
`loosehead_prop`, `hooker`, `tighthead_prop`, `lock`, `blindside_flanker`, `openside_flanker`,
`number_eight`, `scrum_half`, `fly_half`, `wing`, `inside_centre`, `outside_centre`, `full_back`
(all PROVISIONAL until p1-players-lead reports).

**`PlayerProfile`**: `enum Foot { RIGHT, LEFT }`; `id: StringName`, `first_name: String`,
`last_name: String`, `known_as: String = ""`, `nationality: StringName`, `birth_year: int = 1980`,
`height_cm: int = 185`, `weight_kg: int = 100`, `preferred_foot: Foot = RIGHT`,
`primary_position: StringName`, `secondary_positions: Array[StringName]`,
`attributes: Dictionary[StringName, int]` (PROVISIONAL keys from the schema);
`display_name() -> String` (`known_as` if set, else `first_name + " " + last_name`, trimmed);
`get_attribute(id: StringName, schema: PlayerAttributeSchema) -> int` (value, or
`schema.default_value` if absent). `validate(schema: PlayerAttributeSchema = null)`: empty id,
height/weight not positive; with a schema, attribute keys not in the schema and values out of range.

**`Kit`**: `id: StringName`, `primary_color: Color = Color.WHITE`,
`secondary_color: Color = Color.BLACK`, `shorts_color: Color = Color.WHITE`,
`socks_color: Color = Color.WHITE`, `number_color: Color = Color.BLACK`,
`pattern: StringName = &"plain"` (PROVISIONAL), `jersey_texture_path: String = ""` (asset path,
resolved through the mod runtime). validate: empty id.

**`Stadium`**: `id: StringName`, `name: String`, `city: String`, `country: StringName`,
`capacity: int = 0`, `pitch: PitchGeometry`, `scene_path: String = ""`,
`crowd_ambience_path: String = ""`, `has_roof: bool = false` (PROVISIONAL). validate: empty id,
negative capacity, null pitch, pitch errors.

**`Team`**: `id: StringName`, `name: String`, `short_name: String` (3 letters),
`nation: StringName`, `home_kit: Kit`, `away_kit: Kit`, `home_stadium: Stadium`,
`squad: Array[PlayerProfile]`, `default_lineup: Array[StringName]` (player ids, starters first),
`captain_id: StringName`, `goal_kicker_id: StringName`, `ratings: Dictionary[StringName, int]`
(PROVISIONAL); `find_player(id: StringName) -> PlayerProfile` (null if absent). validate: empty
id, duplicate player ids in squad, lineup id not in squad, duplicate lineup ids, captain or goal
kicker set but not in squad, null home kit.

**`RulesConfig`** (law parameters; S3 extends it):

| Field | Type | Default | Note |
|---|---|---|---|
| `period_count` | int | 2 | TBC-RE |
| `period_game_seconds` | int | 2400 | displayed length of one period (40 min) |
| `players_per_side` | int | 15 | |
| `replacements_allowed` | int | 7 | PROVISIONAL |
| `points_try` | int | 5 | TBC-RE |
| `points_conversion` | int | 2 | TBC-RE |
| `points_penalty_goal` | int | 3 | TBC-RE |
| `points_drop_goal` | int | 3 | TBC-RE |
| `points_penalty_try` | int | 5 | 2007 law: try plus conversion attempt; TBC-RE |
| `penalty_try_awards_conversion` | bool | true | 2007 law; modern law is false; TBC-RE |
| `sin_bin_game_seconds` | int | 600 | TBC-RE |
| `extra` | Dictionary[StringName, float] | {} | PROVISIONAL bag for RE law parameters until promoted to fields |

validate: `period_count >= 1`, `period_game_seconds >= 1`, `players_per_side >= 1`, all points >= 0.

**`DifficultyProfile`**: `id: StringName`, `display_name_key: String`, `level: int = 0`,
`tuning: Dictionary[StringName, float]` (PROVISIONAL keys until p1-ai-lead reports). The default
resource has `id = &"normal"`, `display_name_key = "DIFFICULTY_PLACEHOLDER"`, `level = 1`.
validate: empty id.

**`CameraPreset`**: `id: StringName`, `display_name_key: String`, `fov_degrees: float = 50.0`,
`distance: float = 25.0`, `height: float = 12.0`, `pitch_degrees: float = -25.0`,
`follow_smoothing: float = 0.15`, `look_ahead: float = 3.0` (all numeric fields PROVISIONAL). The
default resource has `id = &"broadcast"`, `display_name_key = "CAMERA_PRESET_PLACEHOLDER"`.
validate: empty id, `fov_degrees` outside (1, 179), negative distance.

**`MatchConfig`**: `seed: int = 0`, `rules: RulesConfig`, `flow: MatchFlowConfig`,
`pitch: PitchGeometry`, `home_team: Team`, `away_team: Team`, `stadium: Stadium`,
`difficulty: DifficultyProfile`, `period_real_seconds: int = 300` (PROVISIONAL, the match-length
option), `slot_count: int = 1`, `axes_per_slot: int = 2`;
`static create_default() -> MatchConfig` (loads the three default resources for rules, flow and
pitch; teams, stadium and difficulty stay null). validate: null rules, flow or pitch;
`period_real_seconds < 1`; `slot_count` outside 1..8; `axes_per_slot` outside 0..16; plus the
errors of `rules`, `flow` and `pitch` validation. Teams may be null in S1.

## 6. Acceptance criteria

Tests live in `tests/unit/match/`, `tests/unit/match/flow/`, `tests/unit/match/pitch/`,
`tests/unit/data/` and `tests/sim/`. "Default config" means `MatchConfig.create_default()`.
"Tick n" means the n-th call to `MatchSim.tick` (1-based); "after tick n" means after that call
returns. The purity scan (C-43) also reads comments, so sim files must not mention the banned
names even in comments.

**RNG**
- C-01 Two `SimRng` with the same seed produce identical sequences of 1000 `next_int()` values.
- C-02 Different seeds (1 and 2) produce different first-10 sequences.
- C-03 `get_state()` then 50 draws then `set_state(saved)` reproduces the same 50 draws.
- C-04 `range_int(3, 5)` only returns 3, 4 or 5 over 1000 draws; `next_float()` is in [0, 1).

**InputFrame**
- C-05 A new `InputFrame(2, 4)` has `buttons.size() == 2`, `axes.size() == 8`, all zero.
- C-06 `set_held(1, 5, true)` makes `is_held(1, 5)` true and `is_held(0, 5)` false.
- C-07 `set_axis(0, 1, 300)` stores 127; `set_axis(0, 1, -300)` stores -127.
- C-08 `copy_from` then `equals` is true; changing one bit makes `equals` false.

**Clock**
- C-09 `MatchClock.new(2, 60, 2400)`: after 30 `advance()` calls `game_time_seconds() == 1200`;
  after 60, `is_period_expired()` is true; `start_next_period()` gives period 2, elapsed 0,
  `game_time_seconds() == 2400`, `is_last_period()` true.

**Flow and sim**
- C-10 `default_match_flow.tres` loads as a `MatchFlowConfig` and `validate()` is empty; it has the
  six states of 2.8 with the flags of 2.8.
- C-11 `validate()` reports: an unknown `to`, a duplicate state id, a missing initial state, a
  transition with no trigger and no condition, and a flow with no terminal state (one test each).
- C-12 Default config with `period_real_seconds = 1` (P = 60): state after tick 1 is `kick_off`,
  after tick 2 `in_play`, after tick 61 still `in_play`, after tick 62 `half_time`, after tick 63
  `kick_off` with `clock.period == 2`, after tick 124 `full_time` and `is_finished()`; after
  tick 123 not finished.
- C-13 Signals over that full run, in order: `state_changed` x6 with the from/to pairs of the
  trace; `period_started` with 1 then 2; `period_ended` with 1 then 2; `finished` exactly once.
- C-14 After finishing, further `tick` calls leave `tick_count` and `state_hash()` unchanged.
- C-15 In `in_play`, `raise_trigger(MatchTriggers.WHISTLE_BLOWN)` then one tick moves to
  `stoppage`; then `raise_trigger(PLAY_RESUMED)` and a tick moves back to `in_play`.
- C-16 A trigger that matches no transition of the current state is consumed: raising
  `PLAY_RESUMED` in `in_play` then ticking twice leaves the state `in_play`.
- C-17 The clock does not advance in `pre_match`, `kick_off` or `half_time`, and advances in
  `in_play` and `stoppage` (check `elapsed_ticks` across states).
- C-18 A `SimSystem` subclass that raises `WHISTLE_BLOWN` from its `tick` when the state is
  `in_play` causes the transition to `stoppage` on that same tick.
- C-19 Systems tick in registration order (two systems appending ids to a shared array).
- C-20 `add_system` after the first tick is ignored (the system's `tick` is never called).
- C-21 Edge detection: frames with bit 3 held on ticks 2..4 give `just_pressed` true only after
  tick 2 and `just_released` true only after tick 5.
- C-22 An invalid config (null rules) gives `is_valid() == false`; `tick` leaves `tick_count` at 0.
- C-23 `state_hash()` is a 64-character lowercase hex string and changes after a tick.

**Determinism (tests/sim/)**
- C-24 Same seed and the same scripted input log (at least 2 slots, 600 ticks, pseudo-random
  buttons and axes generated by a separate fixed-seed RNG, plus a `SimSystem` that consumes
  `sim.rng` and raises triggers from input) run twice give identical `state_hash()` after every
  tick.
- C-25 Changing only the seed gives a different `state_hash()` after tick 1.
- C-26 Recording with `MatchRunner` (or by hand into an `InputLog`), serialising with
  `to_bytes`/`from_bytes`, then `MatchReplay.run` gives the same final `state_hash()` as the
  original run.
- C-27 `MatchReplay.run` returns null when the given mod set hash differs from the header's.

**Input log**
- C-28 `InputLog` round-trips through `to_bytes`/`from_bytes` and `save`/`load_file`
  (`user://`) with identical header fields and frames.
- C-29 `append` with a wrong-shaped frame is ignored (`frame_count` unchanged).
- C-30 `from_bytes` returns null for garbage bytes and for a header with
  `format_version = FORMAT_VERSION + 1`.

**Runner**
- C-31 `MatchRunner.start` with the default config and a base `InputSource` returns `OK`;
  `step_once()` five times gives `sim.tick_count == 5`, `input_log.frame_count() == 5`,
  and `ticked` emitted with 1..5.
- C-32 `start` with an invalid config returns `ERR_INVALID_PARAMETER`.
- C-33 With a `ReplayInputSource` of 3 frames, the 4th `step_once` returns false, emits
  `input_ended` and `is_running()` becomes false.
- C-34 During a runner-driven run, `EventBus.match_state_changed` is emitted with the same
  from/to pairs as the sim's `state_changed`.

**Pitch**
- C-35 `default_pitch.tres` has the defaults of section 4 and `validate()` is empty.
- C-36 With defaults: `try_line_x(1) == 50`, `dead_ball_line_x(-1) == -60`, `line_22_x(1) == 28`;
  `(0,0,0)` in field of play; `(50,0,0)` in goal for end 1, not in field of play; `(49.9,0,34.9)`
  in field of play; `(10,0,35)` in touch; `(60,0,0)` beyond dead-ball line and not in goal.
- C-37 `validate()` reports `field_length = 0` and `line_22_from_try = 60`.

**Data**
- C-38 Each data class instantiates with the defaults in section 5 (one test per class).
- C-39 `Team.validate()` reports a lineup id not in the squad and duplicate squad ids;
  `find_player` returns the profile or null.
- C-40 `PlayerProfile.display_name()` uses `known_as` when set; `get_attribute` falls back to the
  schema default; `validate(schema)` reports an unknown attribute key and an out-of-range value.
- C-41 The four default `.tres` files in `game/data/defaults/` load with the right class and
  `validate()` is empty.
- C-42 `MatchConfig.create_default().validate()` is empty; setting `slot_count = 0` reports an
  error.

**Purity and conventions**
- C-43 A test scans every `.gd` under `res://game/match/` (except `match_runner.gd`) for
  `EventBus`, `Input.`, `Time.`, `OS.get_ticks` and global random calls (regex
  `(?<![\w.])(randi|randf|randfn|randi_range|randf_range|randomize|seed)\s*\(`), and the same
  folders listed in 2.5 for everything but `EventBus`; no matches.
- C-44 Every data Resource field listed in section 5 is reported by `get_property_list()` with
  `PROPERTY_USAGE_STORAGE` and `PROPERTY_USAGE_EDITOR` (so the mod loader can patch it).
