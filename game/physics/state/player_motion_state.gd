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


## Returns a detached copy for transaction checkpoints and caller injection.
func duplicate_state() -> PlayerMotionState:
	var copy: PlayerMotionState = PlayerMotionState.new()
	copy.player_id = player_id
	copy.initialized = initialized
	copy.team_id = team_id
	copy.shirt_number = shirt_number
	copy.position_m = position_m
	copy.heading_turns = heading_turns
	copy.desired_heading_turns = desired_heading_turns
	copy.speed_m_s = speed_m_s
	copy.desired_speed_m_s = desired_speed_m_s
	copy.acceleration_increment_m_s_per_tick = acceleration_increment_m_s_per_tick
	copy.run_speed_m_s = run_speed_m_s
	copy.sprint_speed_m_s = sprint_speed_m_s
	copy.sprint_energy = sprint_energy
	copy.speed_stat = speed_stat
	copy.acceleration_stat = acceleration_stat
	copy.urgency = urgency
	copy.sprint_request = sprint_request
	copy.sprint_energy_initialized = sprint_energy_initialized
	copy.sprinting = sprinting
	copy.stagger_timer_s = stagger_timer_s
	copy.fatigue_snapshot = _duplicate_fatigue(fatigue_snapshot)
	return copy


func _duplicate_fatigue(source: PlayerFatigueSnapshot) -> PlayerFatigueSnapshot:
	if source == null:
		return null
	var copy: PlayerFatigueSnapshot = PlayerFatigueSnapshot.new()
	copy.team_id = source.team_id
	copy.shirt_number = source.shirt_number
	copy.fatigue_time_s = source.fatigue_time_s
	copy.energy_cap = source.energy_cap
	copy.energy_percent = source.energy_percent
	copy.effective_passing = source.effective_passing
	copy.effective_tackling = source.effective_tackling
	copy.initial_sprint_energy = source.initial_sprint_energy
	return copy
