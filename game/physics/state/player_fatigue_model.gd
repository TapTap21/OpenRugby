class_name PlayerFatigueModel
extends RefCounted
## Owns deterministic per-player match fatigue and produces S2 fatigue snapshots.

const SNAPSHOT_VERSION: int = 1

var params: PlayerFatigueParams

var _entries: Dictionary[StringName, PlayerFatigueEntry] = {}


func _init(p_params: PlayerFatigueParams = null) -> void:
	params = p_params if p_params != null else _default_params()


## Adds one configured match player. All inputs, including initial sprint energy, are caller-owned.
func add_player(
	team_id: StringName,
	player_id: StringName,
	shirt_number: int,
	stamina: int,
	passing: int,
	tackling: int,
	fatigue_time_s: float,
	on_pitch: bool,
	initial_sprint_energy: float
) -> bool:
	if (
		team_id == &""
		or player_id == &""
		or shirt_number < 1
		or shirt_number > 22
		or not _valid_stat(stamina)
		or not _valid_stat(passing)
		or not _valid_stat(tackling)
		or not is_finite(fatigue_time_s)
		or fatigue_time_s < 0.0
		or not is_finite(initial_sprint_energy)
		or initial_sprint_energy < -1.0
		or params == null
		or not params.validate().is_empty()
		or _entries.has(_key(team_id, shirt_number))
	):
		return false
	var entry: PlayerFatigueEntry = PlayerFatigueEntry.new()
	entry.team_id = team_id
	entry.player_id = player_id
	entry.shirt_number = shirt_number
	entry.stamina = stamina
	entry.passing = passing
	entry.tackling = tackling
	entry.fatigue_time_s = fatigue_time_s
	entry.on_pitch = on_pitch
	entry.initial_sprint_energy = initial_sprint_energy
	_entries[_key(team_id, shirt_number)] = entry
	return true


## Changes only the pitch-presence input; substitutions remain caller-owned.
func set_on_pitch(team_id: StringName, shirt_number: int, value: bool) -> bool:
	var entry: PlayerFatigueEntry = _entry(team_id, shirt_number)
	if entry == null:
		return false
	entry.on_pitch = value
	return true


## Adds the injected match-clock delta to on-pitch players only.
func advance_frame(dt_match: float) -> bool:
	if not is_finite(dt_match) or dt_match < 0.0:
		return false
	for entry: PlayerFatigueEntry in _ordered_entries():
		if entry.on_pitch:
			entry.fatigue_time_s += dt_match
	return true


## Applies the observed 300-second recovery to shirts 1..22 for every registered team.
func recover_at_halftime() -> void:
	if params == null or not params.validate().is_empty():
		return
	for entry: PlayerFatigueEntry in _ordered_entries():
		entry.fatigue_time_s = maxf(0.0, entry.fatigue_time_s - params.halftime_recovery_s)


## Builds the immutable pre-advance fatigue view consumed by S2.
## Passing follows S2's documented zero clamp; Tackling preserves RE 09's raw subtraction.
func fatigue_snapshot(team_id: StringName, shirt_number: int) -> PlayerFatigueSnapshot:
	var entry: PlayerFatigueEntry = _entry(team_id, shirt_number)
	if entry == null or params == null or not params.validate().is_empty():
		return null
	var energy_cap: float = energy(entry.stamina, entry.fatigue_time_s)
	var percent: int = energy_percent(energy_cap)
	var snapshot_value: PlayerFatigueSnapshot = PlayerFatigueSnapshot.new()
	snapshot_value.team_id = entry.team_id
	snapshot_value.player_id = entry.player_id
	snapshot_value.shirt_number = entry.shirt_number
	snapshot_value.fatigue_time_s = entry.fatigue_time_s
	snapshot_value.energy_cap = energy_cap
	snapshot_value.energy_percent = percent
	snapshot_value.effective_passing = maxi(0, entry.passing - floori(float(100 - percent) / 3.0))
	snapshot_value.effective_tackling = entry.tackling - floori(float(100 - percent) / 2.0)
	snapshot_value.initial_sprint_energy = entry.initial_sprint_energy
	return snapshot_value if snapshot_value.is_valid() else null


## Computes the observed RE 09 energy curve for a stamina value and match-clock time.
func energy(stamina: int, fatigue_time_s: float) -> float:
	if (
		params == null
		or not params.validate().is_empty()
		or not _valid_stat(stamina)
		or not is_finite(fatigue_time_s)
		or fatigue_time_s < 0.0
	):
		return NAN
	var stamina_factor: float = maxf(
		0.0,
		(float(stamina) - params.stamina_floor) / (params.stamina_ceiling - params.stamina_floor)
	)
	var fatigue_fraction: float = clampf(fatigue_time_s / params.full_fatigue_time_s, 0.0, 1.0)
	var fatigue_curve: float = pow(fatigue_fraction, params.fatigue_exponent)
	var low_energy: float = (
		params.energy_floor_at_low_stamina
		+ (
			(params.energy_floor_at_high_stamina - params.energy_floor_at_low_stamina)
			* stamina_factor
		)
	)
	return clampf(
		low_energy + (params.energy_ceiling - low_energy) * (1.0 - fatigue_curve),
		params.energy_floor_at_low_stamina,
		params.energy_ceiling
	)


## Converts energy to the observed integer percentage using truncation toward zero.
func energy_percent(energy_value: float) -> int:
	if params == null or not params.validate().is_empty() or not is_finite(energy_value):
		return -1
	var energy_fraction: float = (
		(energy_value - params.energy_floor_at_low_stamina)
		/ (params.energy_ceiling - params.energy_floor_at_low_stamina)
	)
	var percent: float = (
		params.energy_percent_floor + (100.0 - params.energy_percent_floor) * energy_fraction
	)
	return int(clampf(percent, params.energy_percent_floor, 100.0))


## Returns a stable deep snapshot containing all state that affects future fatigue queries.
func snapshot() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry: PlayerFatigueEntry in _ordered_entries():
		entries.append(entry.snapshot())
	return {
		"version": SNAPSHOT_VERSION,
		"params": _params_snapshot(),
		"entries": entries,
	}


## Replaces the complete state only when the versioned snapshot is valid.
func restore_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 3
		or typeof(value.get("version")) != TYPE_INT
		or value.get("version") != SNAPSHOT_VERSION
		or params == null
		or not params.validate().is_empty()
		or typeof(value.get("params")) != TYPE_DICTIONARY
		or value.get("params") != _params_snapshot()
	):
		return false
	var raw_entries: Variant = value.get("entries")
	if typeof(raw_entries) != TYPE_ARRAY:
		return false
	var restored: Dictionary[StringName, PlayerFatigueEntry] = {}
	for raw_entry: Variant in raw_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return false
		@warning_ignore("unsafe_cast")
		var entry: PlayerFatigueEntry = _restore_entry(raw_entry as Dictionary)
		if entry == null:
			return false
		var entry_key: StringName = _key(entry.team_id, entry.shirt_number)
		if restored.has(entry_key):
			return false
		restored[entry_key] = entry
	_entries = restored
	return true


func _restore_entry(value: Dictionary) -> PlayerFatigueEntry:
	if value.size() != 9:
		return null
	if (
		typeof(value.get("team_id")) != TYPE_STRING_NAME
		or typeof(value.get("player_id")) != TYPE_STRING_NAME
		or typeof(value.get("shirt")) != TYPE_INT
		or typeof(value.get("stamina")) != TYPE_INT
		or typeof(value.get("passing")) != TYPE_INT
		or typeof(value.get("tackling")) != TYPE_INT
		or typeof(value.get("fatigue_time_s")) != TYPE_FLOAT
		or typeof(value.get("on_pitch")) != TYPE_BOOL
		or typeof(value.get("initial_sprint_energy")) != TYPE_FLOAT
	):
		return null
	var entry: PlayerFatigueEntry = PlayerFatigueEntry.new()
	entry.team_id = value["team_id"]
	entry.player_id = value["player_id"]
	entry.shirt_number = value["shirt"]
	entry.stamina = value["stamina"]
	entry.passing = value["passing"]
	entry.tackling = value["tackling"]
	entry.fatigue_time_s = value["fatigue_time_s"]
	entry.on_pitch = value["on_pitch"]
	entry.initial_sprint_energy = value["initial_sprint_energy"]
	if (
		entry.team_id == &""
		or entry.player_id == &""
		or entry.shirt_number < 1
		or entry.shirt_number > 22
		or not _valid_stat(entry.stamina)
		or not _valid_stat(entry.passing)
		or not _valid_stat(entry.tackling)
		or not is_finite(entry.fatigue_time_s)
		or entry.fatigue_time_s < 0.0
		or not is_finite(entry.initial_sprint_energy)
		or entry.initial_sprint_energy < -1.0
	):
		return null
	return entry


func _params_snapshot() -> Dictionary:
	return {
		"stamina_floor": params.stamina_floor,
		"stamina_ceiling": params.stamina_ceiling,
		"energy_floor_at_low_stamina": params.energy_floor_at_low_stamina,
		"energy_floor_at_high_stamina": params.energy_floor_at_high_stamina,
		"energy_ceiling": params.energy_ceiling,
		"full_fatigue_time_s": params.full_fatigue_time_s,
		"fatigue_exponent": params.fatigue_exponent,
		"energy_percent_floor": params.energy_percent_floor,
		"halftime_recovery_s": params.halftime_recovery_s,
	}


func _ordered_entries() -> Array[PlayerFatigueEntry]:
	var result: Array[PlayerFatigueEntry] = []
	result.assign(_entries.values())
	result.sort_custom(
		func(left: PlayerFatigueEntry, right: PlayerFatigueEntry) -> bool:
			if left.team_id == right.team_id:
				return left.shirt_number < right.shirt_number
			return String(left.team_id) < String(right.team_id)
	)
	return result


func _entry(team_id: StringName, shirt_number: int) -> PlayerFatigueEntry:
	return _entries.get(_key(team_id, shirt_number))


func _key(team_id: StringName, shirt_number: int) -> StringName:
	return StringName("%s:%d" % [team_id, shirt_number])


func _valid_stat(value: int) -> bool:
	return value >= 0 and value <= 100


func _default_params() -> PlayerFatigueParams:
	return load("res://game/physics/resources/default_player_fatigue.tres") as PlayerFatigueParams
