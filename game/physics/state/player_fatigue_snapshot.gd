class_name PlayerFatigueSnapshot
extends RefCounted
## Immutable player/match-owned fatigue inputs captured before that layer advances this tick.

var team_id: StringName
var player_id: StringName
var shirt_number: int = 0
var fatigue_time_s: float = NAN
var energy_cap: float = NAN
var energy_percent: int = -1
var effective_passing: int = -1
var effective_tackling: int = -1
var initial_sprint_energy: float = NAN


## True only when all required owner values have been injected as finite data.
func is_valid() -> bool:
	return (
		team_id != &""
		and player_id != &""
		and shirt_number >= 0
		and is_finite(fatigue_time_s)
		and fatigue_time_s >= 0.0
		and is_finite(energy_cap)
		and is_finite(initial_sprint_energy)
		and energy_cap >= 40.0
		and energy_cap <= 100.0
		and initial_sprint_energy >= -1.0
		and initial_sprint_energy <= energy_cap
		and energy_percent >= 0
		and energy_percent <= 100
		and effective_passing >= 0
		and effective_passing <= 100
		and effective_tackling >= -45
		and effective_tackling <= 100
	)


## Stable snapshot for replay state.
func snapshot() -> Dictionary:
	return {
		"team_id": team_id,
		"player_id": player_id,
		"shirt": shirt_number,
		"fatigue_time_s": fatigue_time_s,
		"energy_cap": energy_cap,
		"energy_percent": energy_percent,
		"effective_passing": effective_passing,
		"effective_tackling": effective_tackling,
		"initial_sprint_energy": initial_sprint_energy,
	}
