class_name BallState
extends RefCounted
## Match-local ball state owned by [BallPhysicsSystem].

enum Mode { UNRESOLVED, HELD, ATTACHED, FROZEN, FREE_FLIGHT, ROLLING }
enum GoalKickState { UNRESOLVED, OFF, ACTIVE }

var position_m: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY
var linear_velocity_m_s: Vector3 = Vector3.ZERO
var angular_velocity_rad_s: Vector3 = Vector3.ZERO
var mode: Mode = Mode.UNRESOLVED
var goal_kick_state: GoalKickState = GoalKickState.UNRESOLVED
var solver_accumulator: int = 0


## Returns all mutable fields in a stable, serialization-friendly structure.
func snapshot() -> Dictionary:
	return {
		"position": [position_m.x, position_m.y, position_m.z],
		"orientation": [orientation.x, orientation.y, orientation.z, orientation.w],
		"linear_velocity": [linear_velocity_m_s.x, linear_velocity_m_s.y, linear_velocity_m_s.z],
		"angular_velocity":
		[angular_velocity_rad_s.x, angular_velocity_rad_s.y, angular_velocity_rad_s.z],
		"mode": mode,
		"goal_kick_state": goal_kick_state,
		"solver_accumulator": solver_accumulator,
	}
