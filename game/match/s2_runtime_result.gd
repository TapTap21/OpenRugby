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
	if (
		not data.has("command_sequence")
		or typeof(data["command_sequence"]) != TYPE_INT
		or not data.has("command_kind")
		or typeof(data["command_kind"]) != TYPE_INT
		or not data.has("status")
		or typeof(data["status"]) != TYPE_INT
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
	result.tackle_result = _restore_tackle(data.get("tackle_result", {}))
	return result


static func _restore_kick(data: Variant) -> KickLaunch:
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return null
	var value: Dictionary = data
	var velocity: Variant = value.get("velocity", [])
	var spin: Variant = value.get("spin", [])
	if typeof(velocity) != TYPE_ARRAY or velocity.size() != 3:
		return null
	if typeof(spin) != TYPE_ARRAY or spin.size() != 3:
		return null
	var result: KickLaunch = KickLaunch.new()
	result.velocity_m_s = Vector3(velocity[0], velocity[1], velocity[2])
	result.spin_rad_s = Vector3(spin[0], spin[1], spin[2])
	result.kick_type = value.get("kick_type", -1)
	result.unresolved = value.get("unresolved", true)
	return result


static func _restore_pass(data: Variant) -> PassLaunch:
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return null
	var value: Dictionary = data
	var velocity: Variant = value.get("velocity", [])
	var target: Variant = value.get("target", [])
	if typeof(velocity) != TYPE_ARRAY or velocity.size() != 3:
		return null
	if typeof(target) != TYPE_ARRAY or target.size() != 3:
		return null
	var result: PassLaunch = PassLaunch.new()
	result.velocity_m_s = Vector3(velocity[0], velocity[1], velocity[2])
	result.target_m = Vector3(target[0], target[1], target[2])
	result.flight_time_s = value.get("flight_time_s", NAN)
	result.unresolved = value.get("unresolved", true)
	return result


static func _restore_catch(data: Variant) -> CatchResult:
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return null
	var value: Dictionary = data
	var result: CatchResult = CatchResult.new()
	result.outcome = value.get("outcome", CatchResult.Outcome.UNRESOLVED)
	result.probability = value.get("probability", NAN)
	result.resolved = value.get("resolved", false)
	return result


static func _restore_pickup(data: Variant) -> PickupResult:
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return null
	var value: Dictionary = data
	var result: PickupResult = PickupResult.new()
	result.outcome = value.get("outcome", PickupResult.Outcome.UNRESOLVED)
	result.accepted = value.get("accepted", false)
	return result


static func _restore_tackle(data: Variant) -> TackleResult:
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return null
	var value: Dictionary = data
	var result: TackleResult = TackleResult.new()
	result.outcome = value.get("outcome", TackleResult.Outcome.NONE)
	result.break_probability = value.get("break_probability", NAN)
	result.spill_probability = value.get("spill_probability", NAN)
	result.broke_tackle = value.get("broke_tackle", false)
	result.spilled_ball = value.get("spilled_ball", false)
	result.ball_velocity_scale = value.get("ball_velocity_scale", 1.0)
	result.spill_velocity_min = value.get("spill_velocity_min", NAN)
	result.spill_velocity_max = value.get("spill_velocity_max", NAN)
	result.unresolved = value.get("unresolved", false)
	return result
