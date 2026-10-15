class_name S2RuntimeCommand
extends RefCounted
## Typed, sequence-ordered resolved action or per-tick input for the S2 runtime port.

enum Kind {
	PLAYER_TICK_INPUT,
	BALL_STATE,
	KICK,
	PASS,
	CATCH,
	FUMBLE,
	PICKUP,
	TACKLE,
	SPILL,
}
enum Phase { LOCOMOTION, BALL, INTERACTION }
enum CandidateState { UNRESOLVED, NO_CANDIDATE, SELECTED }
enum GateState { UNRESOLVED, DISABLED, ENABLED }

var kind: Kind = Kind.PLAYER_TICK_INPUT
var sequence: int = -1
var actor_id: StringName = &""
var tackling_fatigue_snapshot: PlayerFatigueSnapshot
var player_input: S2PlayerTickInput
var ball_mode: BallState.Mode = BallState.Mode.UNRESOLVED
var goal_kick_state: BallState.GoalKickState = BallState.GoalKickState.UNRESOLVED
var wind_policy: S2WindPolicy
var kick_type: int = -1
var gauge: float = NAN
var kicking_power: float = NAN
var kick_accuracy: float = NAN
var heading_radians: float = NAN
var difficulty: int = -1
var ai_place: bool = false
var has_place_meter: bool = false
var place_meter_gauge: float = NAN
var place_meter_error: float = NAN
var pass_launch: PassLaunch
var forward_assist_setting: int = -1
var attack_direction: float = NAN
var catch_candidate: CandidateState = CandidateState.UNRESOLVED
var catch_probability: float = NAN
var catch_gate: GateState = GateState.UNRESOLVED
var probability: float = NAN
var ball_held: bool = false
var pickup_vertical_separation_m: float = NAN
var hand_capsule_intersects: bool = false
var defender_tackling: int = -1
var defender_has_tackle: bool = false
var carrier_strength: int = -1
var carrier_strength_ability: bool = false
var relative_angle_degrees: float = NAN
var carrier_break_modifier: float = NAN
var out_of_position: bool = false


## Creates an owner-resolved player update for one tick.
static func player_tick_input(value: S2PlayerTickInput) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.PLAYER_TICK_INPUT
	command.player_input = value
	return command


## Creates an explicit ball mode and goal-kick state command.
static func ball_state(
	mode: BallState.Mode, goal_kick_state: BallState.GoalKickState, wind: S2WindPolicy = null
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.BALL_STATE
	command.ball_mode = mode
	command.goal_kick_state = goal_kick_state
	command.wind_policy = wind
	return command


## Creates a kick action from the owner's resolved action inputs.
static func kick(
	p_kick_type: int,
	p_gauge: float,
	p_kicking_power: float,
	p_kick_accuracy: float,
	p_heading_radians: float,
	p_difficulty: int,
	p_ai_place: bool = false,
	p_place_meter: PlaceKickMeterResult = null
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.KICK
	command.kick_type = p_kick_type
	command.gauge = p_gauge
	command.kicking_power = p_kicking_power
	command.kick_accuracy = p_kick_accuracy
	command.heading_radians = p_heading_radians
	command.difficulty = p_difficulty
	command.ai_place = p_ai_place
	command.has_place_meter = p_place_meter != null
	if p_place_meter != null:
		command.place_meter_gauge = p_place_meter.raw_gauge
		command.place_meter_error = p_place_meter.needle_error
	return command


## Creates a pass action with the caller-resolved ballistic path and explicit assist inputs.
static func pass_ball(
	launch: PassLaunch, assist_setting: int, direction: float
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.PASS
	command.pass_launch = _copy_pass(launch)
	command.forward_assist_setting = assist_setting
	command.attack_direction = direction
	return command


## Creates a catch command with already selected candidate and gate values.
static func catch(
	actor: StringName, candidate: CandidateState, failure_probability: float, gate: GateState
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.CATCH
	command.actor_id = actor
	command.catch_candidate = candidate
	command.catch_probability = failure_probability
	command.catch_gate = gate
	return command


## Creates a resolved fumble chance command.
static func fumble(actor: StringName, p_probability: float) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.FUMBLE
	command.actor_id = actor
	command.probability = p_probability
	return command


## Creates a pickup command from caller-resolved physical intersection inputs.
static func pickup(
	actor: StringName, p_ball_held: bool, vertical_separation_m: float, capsule_intersects: bool
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.PICKUP
	command.actor_id = actor
	command.ball_held = p_ball_held
	command.pickup_vertical_separation_m = vertical_separation_m
	command.hand_capsule_intersects = capsule_intersects
	return command


## Creates a tackle command with owner-resolved mappings and modifier.
static func tackle(
	p_actor_id: StringName,
	fatigue: PlayerFatigueSnapshot,
	p_defender_has_tackle: bool,
	p_carrier_strength: int,
	p_carrier_strength_ability: bool,
	p_relative_angle_degrees: float,
	p_carrier_break_modifier: float,
	p_out_of_position: bool = false
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.TACKLE
	command.actor_id = p_actor_id
	command.tackling_fatigue_snapshot = _copy_fatigue(fatigue)
	command.defender_tackling = fatigue.effective_tackling if fatigue != null else -1
	command.defender_has_tackle = p_defender_has_tackle
	command.carrier_strength = p_carrier_strength
	command.carrier_strength_ability = p_carrier_strength_ability
	command.relative_angle_degrees = p_relative_angle_degrees
	command.carrier_break_modifier = p_carrier_break_modifier
	command.out_of_position = p_out_of_position
	return command


## Creates a ball spill command with the caller-resolved base probability.
static func spill(actor: StringName, p_probability: float) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = Kind.SPILL
	command.actor_id = actor
	command.probability = p_probability
	return command


## Creates a tackle using the initiating tackler's owner-adjusted Tackling value.
static func tackle_from_fatigue(
	p_actor_id: StringName,
	fatigue: PlayerFatigueSnapshot,
	p_defender_has_tackle: bool,
	p_carrier_strength: int,
	p_carrier_strength_ability: bool,
	p_relative_angle_degrees: float,
	p_carrier_break_modifier: float,
	p_out_of_position: bool = false
) -> S2RuntimeCommand:
	var command: S2RuntimeCommand = tackle(
		p_actor_id,
		fatigue,
		p_defender_has_tackle,
		p_carrier_strength,
		p_carrier_strength_ability,
		p_relative_angle_degrees,
		p_carrier_break_modifier,
		p_out_of_position
	)
	return command


## Returns the fixed S2 phase in which this command executes.
func phase() -> Phase:
	if kind == Kind.PLAYER_TICK_INPUT:
		return Phase.LOCOMOTION
	if kind == Kind.BALL_STATE or kind == Kind.KICK or kind == Kind.PASS:
		return Phase.BALL
	return Phase.INTERACTION


## Validates required values before command execution can mutate simulation state.
func validate() -> PackedStringArray:
	var detail: String = ""
	if phase() == Phase.INTERACTION and actor_id == &"":
		return PackedStringArray(["player-owned interaction requires stable actor id"])
	if phase() != Phase.INTERACTION and actor_id != &"":
		return PackedStringArray(["non-interaction command cannot carry an actor id"])
	if not _nested_payload_matches_kind():
		return PackedStringArray(["nested command payload does not match command kind"])
	match kind:
		Kind.PLAYER_TICK_INPUT:
			if player_input == null or not player_input.is_valid():
				detail = "player tick input is unresolved or invalid"
		Kind.BALL_STATE:
			if ball_mode < BallState.Mode.HELD or ball_mode > BallState.Mode.ROLLING:
				detail = "ball mode is unresolved"
			elif (
				goal_kick_state < BallState.GoalKickState.OFF
				or goal_kick_state > BallState.GoalKickState.ACTIVE
			):
				detail = "goal-kick state is unresolved"
			elif (
				goal_kick_state == BallState.GoalKickState.ACTIVE
				and (wind_policy == null or not wind_policy.is_valid())
			):
				detail = "active goal kick requires a resolved wind policy"
		Kind.KICK:
			if (
				kick_type < 0
				or not is_finite(gauge)
				or gauge < 0.0
				or gauge > 1.0
				or not is_finite(kicking_power)
				or kicking_power < 0.0
				or kicking_power > 100.0
				or not is_finite(kick_accuracy)
				or kick_accuracy < 0.0
				or kick_accuracy > 100.0
				or not is_finite(heading_radians)
				or difficulty < 0
				or (
					has_place_meter
					and (
						not is_finite(place_meter_gauge)
						or place_meter_gauge < 0.0
						or place_meter_gauge > 1.0
					)
				)
				or (has_place_meter and not is_finite(place_meter_error))
			):
				detail = "kick command has unresolved launch inputs"
		Kind.PASS:
			if (
				pass_launch == null
				or pass_launch.unresolved
				or not pass_launch.velocity_m_s.is_finite()
				or not pass_launch.target_m.is_finite()
				or not is_finite(pass_launch.flight_time_s)
				or forward_assist_setting < 0
				or not is_finite(attack_direction)
			):
				detail = "pass command requires a resolved caller-built path"
		Kind.CATCH:
			if (
				catch_candidate < CandidateState.NO_CANDIDATE
				or catch_candidate > CandidateState.SELECTED
				or catch_gate < GateState.DISABLED
				or catch_gate > GateState.ENABLED
			):
				detail = "catch selection and gate must be owner-resolved"
			elif (
				catch_candidate == CandidateState.SELECTED
				and not _probability_valid(catch_probability)
			):
				detail = "selected catch requires a valid failure probability"
		Kind.FUMBLE, Kind.SPILL:
			if not _probability_valid(probability):
				detail = "command probability must be finite and in [0,1]"
		Kind.PICKUP:
			if not is_finite(pickup_vertical_separation_m):
				detail = "pickup vertical separation must be finite"
		Kind.TACKLE:
			if (
				actor_id == &""
				or defender_tackling < 0
				or defender_tackling > 100
				or carrier_strength < 0
				or carrier_strength > 100
				or not is_finite(relative_angle_degrees)
				or relative_angle_degrees < 0.0
				or relative_angle_degrees > 180.0
				or not is_finite(carrier_break_modifier)
				or tackling_fatigue_snapshot == null
				or not tackling_fatigue_snapshot.is_valid()
				or tackling_fatigue_snapshot.player_id != actor_id
				or defender_tackling != tackling_fatigue_snapshot.effective_tackling
			):
				detail = "tackle inputs must be explicitly resolved"
		_:
			detail = "command kind is not recognized"
	return PackedStringArray([detail]) if not detail.is_empty() else PackedStringArray()


func _nested_payload_matches_kind() -> bool:
	match kind:
		Kind.PLAYER_TICK_INPUT:
			return (
				player_input != null
				and wind_policy == null
				and pass_launch == null
				and tackling_fatigue_snapshot == null
			)
		Kind.BALL_STATE:
			return (
				player_input == null and pass_launch == null and tackling_fatigue_snapshot == null
			)
		Kind.PASS:
			return (
				player_input == null
				and wind_policy == null
				and pass_launch != null
				and tackling_fatigue_snapshot == null
			)
		Kind.TACKLE:
			return (
				player_input == null
				and wind_policy == null
				and pass_launch == null
				and tackling_fatigue_snapshot != null
			)
		_:
			return (
				player_input == null
				and wind_policy == null
				and pass_launch == null
				and tackling_fatigue_snapshot == null
			)


## Snapshot of the complete queued command, including its stable sequence.
func snapshot() -> Dictionary:
	return {
		"kind": kind,
		"sequence": sequence,
		"actor_id": actor_id,
		"player_input": player_input.snapshot() if player_input != null else {},
		"ball_mode": ball_mode,
		"goal_kick_state": goal_kick_state,
		"wind_policy": wind_policy.snapshot() if wind_policy != null else {},
		"kick_type": kick_type,
		"gauge": gauge,
		"kicking_power": kicking_power,
		"kick_accuracy": kick_accuracy,
		"heading_radians": heading_radians,
		"difficulty": difficulty,
		"ai_place": ai_place,
		"has_place_meter": has_place_meter,
		"place_meter_gauge": place_meter_gauge,
		"place_meter_error": place_meter_error,
		"pass_launch": pass_launch.snapshot() if pass_launch != null else {},
		"forward_assist_setting": forward_assist_setting,
		"attack_direction": attack_direction,
		"catch_candidate": catch_candidate,
		"catch_probability": catch_probability,
		"catch_gate": catch_gate,
		"probability": probability,
		"ball_held": ball_held,
		"pickup_vertical_separation_m": pickup_vertical_separation_m,
		"hand_capsule_intersects": hand_capsule_intersects,
		"defender_tackling": defender_tackling,
		"defender_has_tackle": defender_has_tackle,
		"carrier_strength": carrier_strength,
		"carrier_strength_ability": carrier_strength_ability,
		"relative_angle_degrees": relative_angle_degrees,
		"carrier_break_modifier": carrier_break_modifier,
		"out_of_position": out_of_position,
		"tackling_fatigue":
		tackling_fatigue_snapshot.snapshot() if tackling_fatigue_snapshot != null else {},
	}


## Reconstructs a queued command from a versioned replay record.
static func from_snapshot(data: Dictionary) -> S2RuntimeCommand:
	var required: PackedStringArray = PackedStringArray(
		[
			"kind",
			"sequence",
			"actor_id",
			"player_input",
			"ball_mode",
			"goal_kick_state",
			"wind_policy",
			"kick_type",
			"gauge",
			"kicking_power",
			"kick_accuracy",
			"heading_radians",
			"difficulty",
			"ai_place",
			"has_place_meter",
			"place_meter_gauge",
			"place_meter_error",
			"pass_launch",
			"forward_assist_setting",
			"attack_direction",
			"catch_candidate",
			"catch_probability",
			"catch_gate",
			"probability",
			"ball_held",
			"pickup_vertical_separation_m",
			"hand_capsule_intersects",
			"defender_tackling",
			"defender_has_tackle",
			"carrier_strength",
			"carrier_strength_ability",
			"relative_angle_degrees",
			"carrier_break_modifier",
			"out_of_position",
			"tackling_fatigue"
		]
	)
	if data.size() != required.size():
		return null
	for key: String in required:
		if not data.has(key):
			return null
	if (
		typeof(data["kind"]) != TYPE_INT
		or typeof(data["sequence"]) != TYPE_INT
		or typeof(data["actor_id"]) != TYPE_STRING_NAME
		or typeof(data["player_input"]) != TYPE_DICTIONARY
		or typeof(data["wind_policy"]) != TYPE_DICTIONARY
		or typeof(data["pass_launch"]) != TYPE_DICTIONARY
		or typeof(data["tackling_fatigue"]) != TYPE_DICTIONARY
	):
		return null
	for key: String in [
		"ball_mode",
		"goal_kick_state",
		"kick_type",
		"difficulty",
		"forward_assist_setting",
		"catch_candidate",
		"catch_gate",
		"defender_tackling",
		"carrier_strength"
	]:
		if typeof(data[key]) != TYPE_INT:
			return null
	for key: String in [
		"ai_place",
		"has_place_meter",
		"ball_held",
		"hand_capsule_intersects",
		"defender_has_tackle",
		"carrier_strength_ability",
		"out_of_position"
	]:
		if typeof(data[key]) != TYPE_BOOL:
			return null
	for key: String in [
		"gauge",
		"kicking_power",
		"kick_accuracy",
		"heading_radians",
		"place_meter_gauge",
		"place_meter_error",
		"attack_direction",
		"catch_probability",
		"probability",
		"pickup_vertical_separation_m",
		"relative_angle_degrees",
		"carrier_break_modifier"
	]:
		if typeof(data[key]) != TYPE_FLOAT:
			return null
	if not data.has("kind") or typeof(data["kind"]) != TYPE_INT:
		return null
	if data["kind"] < Kind.PLAYER_TICK_INPUT or data["kind"] > Kind.SPILL:
		return null
	if not data.has("sequence") or typeof(data["sequence"]) != TYPE_INT:
		return null
	var kind_value: int = data["kind"]
	var ball_mode_value: Variant = data.get("ball_mode", BallState.Mode.UNRESOLVED)
	var goal_kick_state_value: Variant = data.get(
		"goal_kick_state", BallState.GoalKickState.UNRESOLVED
	)
	var catch_candidate_value: Variant = data.get("catch_candidate", CandidateState.UNRESOLVED)
	var catch_gate_value: Variant = data.get("catch_gate", GateState.UNRESOLVED)
	if (
		not ball_mode_value is int
		or not goal_kick_state_value is int
		or not catch_candidate_value is int
		or not catch_gate_value is int
	):
		return null
	var ball_mode_int: int = ball_mode_value
	var goal_kick_state_int: int = goal_kick_state_value
	var catch_candidate_int: int = catch_candidate_value
	var catch_gate_int: int = catch_gate_value
	var command: S2RuntimeCommand = S2RuntimeCommand.new()
	command.kind = kind_value
	command.sequence = data["sequence"]
	command.actor_id = data["actor_id"]
	if command.sequence < -1:
		return null
	command.ball_mode = ball_mode_int
	command.goal_kick_state = goal_kick_state_int
	command.kick_type = data.get("kick_type", -1)
	command.gauge = data.get("gauge", NAN)
	command.kicking_power = data.get("kicking_power", NAN)
	command.kick_accuracy = data.get("kick_accuracy", NAN)
	command.heading_radians = data.get("heading_radians", NAN)
	command.difficulty = data.get("difficulty", -1)
	command.ai_place = data.get("ai_place", false)
	command.has_place_meter = data.get("has_place_meter", false)
	command.place_meter_gauge = data.get("place_meter_gauge", NAN)
	command.place_meter_error = data.get("place_meter_error", NAN)
	command.forward_assist_setting = data.get("forward_assist_setting", -1)
	command.attack_direction = data.get("attack_direction", NAN)
	command.catch_candidate = catch_candidate_int
	command.catch_probability = data.get("catch_probability", NAN)
	command.catch_gate = catch_gate_int
	command.probability = data.get("probability", NAN)
	command.ball_held = data.get("ball_held", false)
	command.pickup_vertical_separation_m = data.get("pickup_vertical_separation_m", NAN)
	command.hand_capsule_intersects = data.get("hand_capsule_intersects", false)
	command.defender_tackling = data.get("defender_tackling", -1)
	command.defender_has_tackle = data.get("defender_has_tackle", false)
	command.carrier_strength = data.get("carrier_strength", -1)
	command.carrier_strength_ability = data.get("carrier_strength_ability", false)
	command.relative_angle_degrees = data.get("relative_angle_degrees", NAN)
	command.carrier_break_modifier = data.get("carrier_break_modifier", NAN)
	command.out_of_position = data.get("out_of_position", false)
	command.tackling_fatigue_snapshot = _restore_fatigue(data["tackling_fatigue"])
	var player_input_data: Dictionary = data["player_input"]
	var wind_policy_data: Dictionary = data["wind_policy"]
	var pass_launch_data: Dictionary = data["pass_launch"]
	var tackling_fatigue_data: Dictionary = data["tackling_fatigue"]
	command.player_input = _restore_player_input(player_input_data)
	command.wind_policy = _restore_wind_policy(wind_policy_data)
	command.pass_launch = _restore_pass_launch(pass_launch_data)
	if (
		(not player_input_data.is_empty() and command.player_input == null)
		or (not wind_policy_data.is_empty() and command.wind_policy == null)
		or (not pass_launch_data.is_empty() and command.pass_launch == null)
		or (not tackling_fatigue_data.is_empty() and command.tackling_fatigue_snapshot == null)
	):
		return null
	return command if command.validate().is_empty() else null


static func _probability_valid(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


static func _copy_pass(source: PassLaunch) -> PassLaunch:
	if source == null:
		return null
	var copy: PassLaunch = PassLaunch.new()
	copy.velocity_m_s = source.velocity_m_s
	copy.target_m = source.target_m
	copy.flight_time_s = source.flight_time_s
	copy.unresolved = source.unresolved
	return copy


static func _copy_fatigue(source: PlayerFatigueSnapshot) -> PlayerFatigueSnapshot:
	if source == null:
		return null
	var copy: PlayerFatigueSnapshot = PlayerFatigueSnapshot.new()
	copy.team_id = source.team_id
	copy.player_id = source.player_id
	copy.shirt_number = source.shirt_number
	copy.fatigue_time_s = source.fatigue_time_s
	copy.energy_cap = source.energy_cap
	copy.energy_percent = source.energy_percent
	copy.effective_passing = source.effective_passing
	copy.effective_tackling = source.effective_tackling
	copy.initial_sprint_energy = source.initial_sprint_energy
	return copy


static func _restore_player_input(data: Variant) -> S2PlayerTickInput:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var input_data: Dictionary = data
	if input_data.is_empty():
		return null
	var fatigue: PlayerFatigueSnapshot = _restore_fatigue(input_data.get("fatigue", {}))
	if fatigue == null:
		return null
	var result: S2PlayerTickInput = S2PlayerTickInput.new()
	var has_move_x: bool = input_data.has("move_x_q")
	var has_move_z: bool = input_data.has("move_z_q")
	var legacy_shape: bool = input_data.size() == 4 and not has_move_x and not has_move_z
	var direction_shape: bool = input_data.size() == 6 and has_move_x and has_move_z
	if not legacy_shape and not direction_shape:
		return null
	if (
		not input_data.has("player_id")
		or typeof(input_data["player_id"]) != TYPE_STRING_NAME
		or typeof(input_data.get("sprint_request")) != TYPE_INT
		or typeof(input_data.get("urgency")) != TYPE_FLOAT
		or (has_move_x and typeof(input_data.get("move_x_q")) != TYPE_INT)
		or (has_move_z and typeof(input_data.get("move_z_q")) != TYPE_INT)
		or typeof(input_data.get("fatigue")) != TYPE_DICTIONARY
	):
		return null
	result.player_id = input_data["player_id"]
	result.sprint_request = input_data["sprint_request"]
	result.urgency = input_data["urgency"]
	if has_move_x:
		result.move_x_q = input_data["move_x_q"]
	if has_move_z:
		result.move_z_q = input_data["move_z_q"]
	result.fatigue_snapshot = fatigue
	return result


static func _restore_fatigue(data: Variant) -> PlayerFatigueSnapshot:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var fatigue_data: Dictionary = data
	if fatigue_data.size() != 9:
		return null
	if (
		typeof(fatigue_data.get("team_id")) != TYPE_STRING_NAME
		or typeof(fatigue_data.get("player_id")) != TYPE_STRING_NAME
		or typeof(fatigue_data.get("shirt")) != TYPE_INT
		or typeof(fatigue_data.get("fatigue_time_s")) != TYPE_FLOAT
		or typeof(fatigue_data.get("energy_cap")) != TYPE_FLOAT
		or typeof(fatigue_data.get("energy_percent")) != TYPE_INT
		or typeof(fatigue_data.get("effective_passing")) != TYPE_INT
		or typeof(fatigue_data.get("effective_tackling")) != TYPE_INT
		or typeof(fatigue_data.get("initial_sprint_energy")) != TYPE_FLOAT
	):
		return null
	var result: PlayerFatigueSnapshot = PlayerFatigueSnapshot.new()
	result.team_id = fatigue_data.get("team_id", &"")
	result.player_id = fatigue_data.get("player_id", &"")
	result.shirt_number = fatigue_data.get("shirt", 0)
	result.fatigue_time_s = fatigue_data.get("fatigue_time_s", NAN)
	result.energy_cap = fatigue_data.get("energy_cap", NAN)
	result.energy_percent = fatigue_data.get("energy_percent", -1)
	result.effective_passing = fatigue_data.get("effective_passing", -1)
	result.effective_tackling = fatigue_data.get("effective_tackling", -1)
	result.initial_sprint_energy = fatigue_data.get("initial_sprint_energy", NAN)
	return result


static func _restore_wind_policy(data: Variant) -> S2WindPolicy:
	if not data is Dictionary:
		return null
	var wind_data: Dictionary = data
	if wind_data.is_empty():
		return null
	var raw_vector: Variant = wind_data.get("vector_km_h", [])
	if not raw_vector is Array:
		return null
	var vector: Array = raw_vector
	if (
		wind_data.size() != 3
		or typeof(wind_data.get("resolved")) != TYPE_BOOL
		or typeof(wind_data.get("enabled")) != TYPE_BOOL
		or vector.size() != 3
		or not _number_array(vector)
	):
		return null
	var result: S2WindPolicy = S2WindPolicy.new()
	result.resolved = wind_data.get("resolved", false)
	result.enabled = wind_data.get("enabled", false)
	result.vector_km_h = _vector3_from_number_array(vector)
	if not result.is_valid():
		return null
	return result


static func _restore_pass_launch(data: Variant) -> PassLaunch:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var pass_data: Dictionary = data
	if pass_data.is_empty():
		return null
	var raw_velocity: Variant = pass_data.get("velocity", [])
	var raw_target: Variant = pass_data.get("target", [])
	if not raw_velocity is Array or not raw_target is Array:
		return null
	var velocity: Array = raw_velocity
	var target: Array = raw_target
	if (
		pass_data.size() != 4
		or typeof(pass_data.get("flight_time_s")) != TYPE_FLOAT
		or typeof(pass_data.get("unresolved")) != TYPE_BOOL
		or velocity.size() != 3
		or not _number_array(velocity)
		or target.size() != 3
		or not _number_array(target)
	):
		return null
	var result: PassLaunch = PassLaunch.new()
	result.velocity_m_s = _vector3_from_number_array(velocity)
	result.target_m = _vector3_from_number_array(target)
	result.flight_time_s = pass_data["flight_time_s"]
	result.unresolved = pass_data["unresolved"]
	if (
		not result.velocity_m_s.is_finite()
		or not result.target_m.is_finite()
		or not is_finite(result.flight_time_s)
		or result.flight_time_s < 0.0
	):
		return null
	return result


static func _number_array(value: Array) -> bool:
	for component: Variant in value:
		if typeof(component) != TYPE_FLOAT and typeof(component) != TYPE_INT:
			return false
	return true


static func _vector3_from_number_array(value: Array) -> Vector3:
	var x: float = _number_as_float(value[0])
	var y: float = _number_as_float(value[1])
	var z: float = _number_as_float(value[2])
	return Vector3(x, y, z)


static func _number_as_float(value: Variant) -> float:
	if value is float:
		var float_value: float = value
		return float_value
	if value is int:
		var int_value: int = value
		return int_value
	return NAN
