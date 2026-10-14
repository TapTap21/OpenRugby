class_name PlayerMotionState
extends RefCounted
## Match-local mutable locomotion state; fatigue remains owned by the player/match layer.

var player_id: StringName
var initialized: bool = false
var team_id: StringName
var shirt_number: int = 0
var position_m: Vector3 = Vector3.ZERO
var heading_turns: float = 0.0
var desired_heading_turns: float = 0.0
var speed_m_s: float = 0.0
var desired_speed_m_s: float = 0.0
var acceleration_increment_m_s_per_tick: float = 0.0
var run_speed_m_s: float = 0.0
var sprint_speed_m_s: float = 0.0
var sprint_energy: float = NAN
var speed_stat: float = NAN
var acceleration_stat: float = NAN
var urgency: float = NAN
var sprint_request: int = -1
var sprint_energy_initialized: bool = false
var sprinting: bool = false
var stagger_timer_s: float = 0.0
var fatigue_snapshot: PlayerFatigueSnapshot


## Stable mutable state representation.
func snapshot() -> Dictionary:
	return {
		"player_id": player_id,
		"initialized": initialized,
		"team_id": team_id,
		"shirt": shirt_number,
		"position": [position_m.x, position_m.y, position_m.z],
		"heading": heading_turns,
		"desired_heading": desired_heading_turns,
		"speed": speed_m_s,
		"desired_speed": desired_speed_m_s,
		"acceleration_increment": acceleration_increment_m_s_per_tick,
		"run_speed": run_speed_m_s,
		"sprint_speed": sprint_speed_m_s,
		"sprint_energy": sprint_energy,
		"speed_stat": speed_stat,
		"acceleration_stat": acceleration_stat,
		"urgency": urgency,
		"sprint_request": sprint_request,
		"energy_initialized": sprint_energy_initialized,
		"sprinting": sprinting,
		"stagger_timer_s": stagger_timer_s,
		"fatigue": fatigue_snapshot.snapshot() if fatigue_snapshot != null else {},
	}
