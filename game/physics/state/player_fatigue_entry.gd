class_name PlayerFatigueEntry
extends RefCounted
## Match-local fatigue data for one team/shirt identity.

var team_id: StringName
var player_id: StringName
var shirt_number: int = 0
var stamina: int = 0
var passing: int = 0
var tackling: int = 0
var fatigue_time_s: float = 0.0
var on_pitch: bool = false
var initial_sprint_energy: float = -1.0


## Returns a detached, stable dictionary for replay snapshots.
func snapshot() -> Dictionary:
	return {
		"team_id": team_id,
		"player_id": player_id,
		"shirt": shirt_number,
		"stamina": stamina,
		"passing": passing,
		"tackling": tackling,
		"fatigue_time_s": fatigue_time_s,
		"on_pitch": on_pitch,
		"initial_sprint_energy": initial_sprint_energy,
	}


## Returns a copy so state never aliases a shared player profile.
func duplicate_entry() -> PlayerFatigueEntry:
	var copy: PlayerFatigueEntry = PlayerFatigueEntry.new()
	copy.team_id = team_id
	copy.player_id = player_id
	copy.shirt_number = shirt_number
	copy.stamina = stamina
	copy.passing = passing
	copy.tackling = tackling
	copy.fatigue_time_s = fatigue_time_s
	copy.on_pitch = on_pitch
	copy.initial_sprint_energy = initial_sprint_energy
	return copy
