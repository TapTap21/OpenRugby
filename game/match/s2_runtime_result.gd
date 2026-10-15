class_name S2RuntimeResult
extends RefCounted
## Typed S2 command result tied to the input command sequence.

enum Status { SUCCEEDED, REJECTED, UNRESOLVED }

var command_sequence: int = -1
var command_kind: S2RuntimeCommand.Kind = S2RuntimeCommand.Kind.PLAYER_TICK_INPUT
var status: Status = Status.UNRESOLVED
var kick_launch: KickLaunch
var pass_launch: PassLaunch
var catch_result: CatchResult
var pickup_result: PickupResult
var tackle_result: TackleResult
var detail: String = ""


## True when the typed action completed and its state commit succeeded.
func is_success() -> bool:
	return status == Status.SUCCEEDED


## Stable serialization for match snapshots and replay outputs.
func snapshot() -> Dictionary:
	return {
		"command_sequence": command_sequence,
		"command_kind": command_kind,
		"status": status,
		"kick_launch": kick_launch.snapshot() if kick_launch != null else {},
		"pass_launch": pass_launch.snapshot() if pass_launch != null else {},
		"catch_result": catch_result.snapshot() if catch_result != null else {},
		"pickup_result": pickup_result.snapshot() if pickup_result != null else {},
		"tackle_result": tackle_result.snapshot() if tackle_result != null else {},
		"detail": detail,
	}


## Reconstructs an output record from a replay or transaction snapshot.
static func from_snapshot(data: Dictionary) -> S2RuntimeResult:
	var required: PackedStringArray = PackedStringArray(
		[
			"command_sequence",
			"command_kind",
			"status",
			"kick_launch",
			"pass_launch",
			"catch_result",
			"pickup_result",
			"tackle_result",
			"detail"
		]
	)
	if data.size() != required.size():
		return null
	for key: String in required:
		if not data.has(key):
			return null
	if (
		not data.has("command_sequence")
		or typeof(data["command_sequence"]) != TYPE_INT
		or not data.has("command_kind")
		or typeof(data["command_kind"]) != TYPE_INT
		or not data.has("status")
		or typeof(data["status"]) != TYPE_INT
		or data["command_sequence"] < 0
		or data["command_kind"] < S2RuntimeCommand.Kind.PLAYER_TICK_INPUT
		or data["command_kind"] > S2RuntimeCommand.Kind.SPILL
		or data["status"] != Status.SUCCEEDED
		or typeof(data["detail"]) != TYPE_STRING
		or typeof(data["kick_launch"]) != TYPE_DICTIONARY
		or typeof(data["pass_launch"]) != TYPE_DICTIONARY
		or typeof(data["catch_result"]) != TYPE_DICTIONARY
		or typeof(data["pickup_result"]) != TYPE_DICTIONARY
		or typeof(data["tackle_result"]) != TYPE_DICTIONARY
	):
		return null
	var result: S2RuntimeResult = S2RuntimeResult.new()
	result.command_sequence = data["command_sequence"]
	result.command_kind = data["command_kind"]
	result.status = data["status"]
	result.detail = data.get("detail", "")
	result.kick_launch = _restore_kick(data.get("kick_launch", {}))
	result.pass_launch = _restore_pass(data.get("pass_launch", {}))
	result.catch_result = _restore_catch(data.get("catch_result", {}))
	result.pickup_result = _restore_pickup(data.get("pickup_result", {}))
	result.tackle_result = _restore_tackle(data.get("tackle_result", {}), result.command_kind)
	var kick_data: Dictionary = data["kick_launch"]
	var pass_data: Dictionary = data["pass_launch"]
	var catch_data: Dictionary = data["catch_result"]
	var pickup_data: Dictionary = data["pickup_result"]
	var tackle_data: Dictionary = data["tackle_result"]
	if (
		(not kick_data.is_empty() and result.kick_launch == null)
		or (not pass_data.is_empty() and result.pass_launch == null)
		or (not catch_data.is_empty() and result.catch_result == null)
		or (not pickup_data.is_empty() and result.pickup_result == null)
		or (not tackle_data.is_empty() and result.tackle_result == null)
		or not result._payload_matches_kind()
	):
		return null
	return result


## Confirms a successful result carries only the payload owned by its command kind.
func _payload_matches_kind() -> bool:
	var present: int = 0
	var matches: bool = false
	for payload: RefCounted in [
		kick_launch, pass_launch, catch_result, pickup_result, tackle_result
	]:
		if payload != null:
			present += 1
	if (
		command_kind == S2RuntimeCommand.Kind.PLAYER_TICK_INPUT
		or command_kind == S2RuntimeCommand.Kind.BALL_STATE
	):
		matches = present == 0
	elif present == 1:
		match command_kind:
			S2RuntimeCommand.Kind.KICK:
				matches = kick_launch != null and not kick_launch.unresolved
			S2RuntimeCommand.Kind.PASS:
				matches = pass_launch != null and not pass_launch.unresolved
			S2RuntimeCommand.Kind.CATCH:
				matches = (
					catch_result != null
					and catch_result.resolved
					and (
						catch_result.outcome == CatchResult.Outcome.CAUGHT
						or catch_result.outcome == CatchResult.Outcome.DROPPED
					)
				)
			S2RuntimeCommand.Kind.FUMBLE:
				matches = (
					catch_result != null
					and catch_result.resolved
					and is_finite(catch_result.probability)
					and (
						catch_result.outcome == CatchResult.Outcome.CAUGHT
						or catch_result.outcome == CatchResult.Outcome.FUMBLED
					)
				)
			S2RuntimeCommand.Kind.PICKUP:
				matches = (
					pickup_result != null
					and pickup_result.outcome != PickupResult.Outcome.UNRESOLVED
				)
			S2RuntimeCommand.Kind.TACKLE, S2RuntimeCommand.Kind.SPILL:
				matches = tackle_result != null and not tackle_result.unresolved
	return matches


static func _restore_kick(data: Variant) -> KickLaunch:
	if not data is Dictionary:
		return null
	var value: Dictionary = data
	if value.is_empty():
		return null
	var velocity: Variant = value.get("velocity", [])
	var spin: Variant = value.get("spin", [])
	if (
		value.size() != 4
		or typeof(value.get("kick_type")) != TYPE_INT
		or typeof(value.get("unresolved")) != TYPE_BOOL
	):
		return null
	if not velocity is Array:
		return null
	var velocity_values: Array = velocity
	if velocity_values.size() != 3:
		return null
	if not spin is Array:
		return null
	var spin_values: Array = spin
	if (
		spin_values.size() != 3
		or not _number_array(velocity_values)
		or not _number_array(spin_values)
	):
		return null
	var result: KickLaunch = KickLaunch.new()
	result.velocity_m_s = _vector3_from_number_array(velocity_values)
	result.spin_rad_s = _vector3_from_number_array(spin_values)
	result.kick_type = value["kick_type"]
	result.unresolved = value["unresolved"]
	if (
		not result.velocity_m_s.is_finite()
		or not result.spin_rad_s.is_finite()
		or result.kick_type < 0
	):
		return null
	return result


static func _restore_pass(data: Variant) -> PassLaunch:
	if not data is Dictionary:
		return null
	var value: Dictionary = data
	if value.is_empty():
		return null
	var velocity: Variant = value.get("velocity", [])
	var target: Variant = value.get("target", [])
	if (
		value.size() != 4
		or typeof(value.get("flight_time_s")) != TYPE_FLOAT
		or typeof(value.get("unresolved")) != TYPE_BOOL
	):
		return null
	if not velocity is Array:
		return null
	var velocity_values: Array = velocity
	if velocity_values.size() != 3 or not _number_array(velocity_values):
		return null
	if not target is Array:
		return null
	var target_values: Array = target
	if target_values.size() != 3 or not _number_array(target_values):
		return null
	var result: PassLaunch = PassLaunch.new()
	result.velocity_m_s = _vector3_from_number_array(velocity_values)
	result.target_m = _vector3_from_number_array(target_values)
	result.flight_time_s = value["flight_time_s"]
	result.unresolved = value["unresolved"]
	if (
		not result.velocity_m_s.is_finite()
		or not result.target_m.is_finite()
		or not is_finite(result.flight_time_s)
		or result.flight_time_s < 0.0
	):
		return null
	return result


static func _restore_catch(data: Variant) -> CatchResult:
	if not data is Dictionary:
		return null
	var value: Dictionary = data
	if value.is_empty():
		return null
	if (
		value.size() != 3
		or typeof(value.get("outcome")) != TYPE_INT
		or typeof(value.get("probability")) != TYPE_FLOAT
		or typeof(value.get("resolved")) != TYPE_BOOL
	):
		return null
	var result: CatchResult = CatchResult.new()
	var probability: float = value["probability"]
	var resolved: bool = value["resolved"]
	if (
		value["outcome"] <= CatchResult.Outcome.UNRESOLVED
		or value["outcome"] > CatchResult.Outcome.FUMBLED
		or not resolved
		or (
			is_nan(probability)
			and value["outcome"] != CatchResult.Outcome.DROPPED
			and value["outcome"] != CatchResult.Outcome.CAUGHT
		)
		or (is_finite(probability) and (probability < 0.0 or probability > 1.0))
		or (not is_finite(probability) and not is_nan(probability))
	):
		return null
	result.outcome = value["outcome"]
	result.probability = probability
	result.resolved = resolved
	return result


static func _restore_pickup(data: Variant) -> PickupResult:
	if not data is Dictionary:
		return null
	var value: Dictionary = data
	if value.is_empty():
		return null
	if (
		value.size() != 2
		or typeof(value.get("outcome")) != TYPE_INT
		or typeof(value.get("accepted")) != TYPE_BOOL
	):
		return null
	var result: PickupResult = PickupResult.new()
	result.outcome = value["outcome"]
	result.accepted = value["accepted"]
	if (
		result.outcome < PickupResult.Outcome.UNRESOLVED
		or result.outcome > PickupResult.Outcome.ACCEPTED
		or result.accepted != (result.outcome == PickupResult.Outcome.ACCEPTED)
	):
		return null
	return result


static func _restore_tackle(data: Variant, command_kind: int) -> TackleResult:
	if not data is Dictionary:
		return null
	var value: Dictionary = data
	if value.is_empty():
		return null
	if (
		value.size() != 9
		or typeof(value.get("outcome")) != TYPE_INT
		or typeof(value.get("break_probability")) != TYPE_FLOAT
		or typeof(value.get("spill_probability")) != TYPE_FLOAT
		or typeof(value.get("broke_tackle")) != TYPE_BOOL
		or typeof(value.get("spilled_ball")) != TYPE_BOOL
		or typeof(value.get("ball_velocity_scale")) != TYPE_FLOAT
		or typeof(value.get("spill_velocity_min")) != TYPE_FLOAT
		or typeof(value.get("spill_velocity_max")) != TYPE_FLOAT
		or typeof(value.get("unresolved")) != TYPE_BOOL
	):
		return null
	var outcome: int = value["outcome"]
	var break_probability: float = value["break_probability"]
	var spill_probability: float = value["spill_probability"]
	var broke_tackle: bool = value["broke_tackle"]
	var spilled_ball: bool = value["spilled_ball"]
	var ball_velocity_scale: float = value["ball_velocity_scale"]
	var spill_velocity_min: float = value["spill_velocity_min"]
	var spill_velocity_max: float = value["spill_velocity_max"]
	var unresolved: bool = value["unresolved"]
	if (
		outcome < TackleResult.Outcome.NONE
		or outcome > TackleResult.Outcome.SPILL
		or unresolved
		or not is_finite(ball_velocity_scale)
		or ball_velocity_scale < 0.0
		or ball_velocity_scale > 2.0
	):
		return null
	if command_kind == S2RuntimeCommand.Kind.TACKLE:
		if (
			(
				outcome != TackleResult.Outcome.TACKLE
				and outcome != TackleResult.Outcome.BROKEN_TACKLE
			)
			or not is_finite(break_probability)
			or break_probability < 0.0
			or break_probability > 1.0
			or not is_nan(spill_probability)
			or not is_nan(spill_velocity_min)
			or not is_nan(spill_velocity_max)
			or broke_tackle != (outcome == TackleResult.Outcome.BROKEN_TACKLE)
			or spilled_ball
			or ball_velocity_scale != 1.0
		):
			return null
	elif command_kind == S2RuntimeCommand.Kind.SPILL:
		if (
			(outcome != TackleResult.Outcome.NONE and outcome != TackleResult.Outcome.SPILL)
			or not is_nan(break_probability)
			or not is_finite(spill_probability)
			or spill_probability < 0.0
			or spill_probability > 1.0
			or not is_finite(spill_velocity_min)
			or not is_finite(spill_velocity_max)
			or spill_velocity_min < 0.0
			or spill_velocity_max > 2.0
			or spill_velocity_min > spill_velocity_max
			or spilled_ball != (outcome == TackleResult.Outcome.SPILL)
			or broke_tackle
			or (
				spilled_ball
				and (
					ball_velocity_scale < spill_velocity_min
					or ball_velocity_scale > spill_velocity_max
				)
			)
			or (not spilled_ball and ball_velocity_scale != 1.0)
		):
			return null
	else:
		return null
	var result: TackleResult = TackleResult.new()
	result.outcome = outcome
	result.break_probability = break_probability
	result.spill_probability = spill_probability
	result.broke_tackle = broke_tackle
	result.spilled_ball = spilled_ball
	result.ball_velocity_scale = ball_velocity_scale
	result.spill_velocity_min = spill_velocity_min
	result.spill_velocity_max = spill_velocity_max
	result.unresolved = unresolved
	return result


static func _number_array(value: Array) -> bool:
	for component: Variant in value:
		if not component is float and not component is int:
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
