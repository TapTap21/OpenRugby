class_name S2BallInitialization
extends RefCounted
## Explicit owner-supplied initial ball body and gameplay state.

var position_m: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY
var linear_velocity_m_s: Vector3 = Vector3.ZERO
var angular_velocity_rad_s: Vector3 = Vector3.ZERO
var mode: BallState.Mode = BallState.Mode.UNRESOLVED
var goal_kick_state: BallState.GoalKickState = BallState.GoalKickState.UNRESOLVED
var wind_policy: S2WindPolicy


## Validates every value before the ball system mutates state.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if mode < BallState.Mode.HELD or mode > BallState.Mode.ROLLING:
		if not errors.push_back("owner must supply a resolved BallMode"):
			return errors
	if (
		goal_kick_state < BallState.GoalKickState.OFF
		or goal_kick_state > BallState.GoalKickState.ACTIVE
	):
		if not errors.push_back("owner must supply a resolved GoalKickState"):
			return errors
	if not position_m.is_finite() or not linear_velocity_m_s.is_finite():
		if not errors.push_back("ball position and linear velocity must be finite"):
			return errors
	if not angular_velocity_rad_s.is_finite() or not _quaternion_is_valid(orientation):
		if not errors.push_back("ball orientation and angular velocity must be finite"):
			return errors
	return errors


## Stable serialization used by replay setup compatibility.
func snapshot() -> Dictionary:
	return {
		"position_m": [position_m.x, position_m.y, position_m.z],
		"orientation": [orientation.x, orientation.y, orientation.z, orientation.w],
		"linear_velocity_m_s":
		[linear_velocity_m_s.x, linear_velocity_m_s.y, linear_velocity_m_s.z],
		"angular_velocity_rad_s":
		[angular_velocity_rad_s.x, angular_velocity_rad_s.y, angular_velocity_rad_s.z],
		"mode": mode,
		"goal_kick_state": goal_kick_state,
		"wind_policy": wind_policy.snapshot() if wind_policy != null else {},
	}


## Returns a detached setup value so later caller mutation cannot alter the match.
func duplicate_setup() -> S2BallInitialization:
	var copy: S2BallInitialization = S2BallInitialization.new()
	copy.position_m = position_m
	copy.orientation = orientation
	copy.linear_velocity_m_s = linear_velocity_m_s
	copy.angular_velocity_rad_s = angular_velocity_rad_s
	copy.mode = mode
	copy.goal_kick_state = goal_kick_state
	copy.wind_policy = wind_policy.duplicate_policy() if wind_policy != null else null
	return copy


func _quaternion_is_valid(value: Quaternion) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
		and is_finite(value.w)
		and value.length_squared() > 0.0
	)
