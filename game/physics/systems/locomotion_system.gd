class_name LocomotionSystem
extends SimSystem
## S2 60 Hz locomotion and sprint-energy updates from injected player/match data.

const MATCH_DT: float = 1.0 / 60.0

var params: LocomotionParams
var players: Array[PlayerMotionState] = []
var pitch_condition: int = -1
var fatigue_option: int = -1
var unresolved_inputs: PackedStringArray = []
var runtime_port: S2RuntimePort
var _initial_inputs_available: bool = true
var _updated_player_ids: Dictionary[StringName, bool] = {}


func _init(p_params: LocomotionParams = null) -> void:
	params = p_params


## Orders injected players by stable team/shirt/player identity before tick one.
func setup(_sim: MatchSim) -> void:
	players.sort_custom(_player_less)


func system_id() -> StringName:
	return &"s2_locomotion"


## Updates players in stable team/shirt/player-id order, only with valid injected snapshots.
func tick(sim: MatchSim) -> void:
	unresolved_inputs.clear()
	_process_player_commands()
	if runtime_port != null and not runtime_port.tick_succeeded():
		return
	if not sim.is_simulation_active():
		return
	if params == null or not params.validate().is_empty():
		unresolved_inputs += PackedStringArray(["locomotion parameters missing or invalid"])
		return
	if pitch_condition < 0 or pitch_condition > 5 or fatigue_option < 0 or fatigue_option > 100:
		unresolved_inputs += PackedStringArray(["pitch condition or fatigue option is unresolved"])
		return
	if not _initial_inputs_available:
		for player: PlayerMotionState in players:
			if player.on_pitch and not _updated_player_ids.has(player.player_id):
				var detail: String = (
					"missing per-tick fatigue/movement input for %s" % player.player_id
				)
				unresolved_inputs += PackedStringArray([detail])
				if runtime_port != null:
					runtime_port.fail_tick(detail)
				return
	var fatigue_multiplier: float = params.fatigue_multiplier(fatigue_option)
	players.sort_custom(_player_less)
	var seen_player_ids: Dictionary[StringName, bool] = {}
	for player: PlayerMotionState in players:
		if not player.on_pitch:
			continue
		if player.player_id == &"" or seen_player_ids.has(player.player_id):
			unresolved_inputs += PackedStringArray(
				["locomotion player ids must be nonempty and unique"]
			)
			continue
		seen_player_ids[player.player_id] = true
		if not player.initialized or player.sprint_request < 0 or player.sprint_request > 1:
			unresolved_inputs += PackedStringArray(
				["missing initial motion/sprint request for %s" % player.player_id]
			)
			continue
		if player.fatigue_snapshot == null or not player.fatigue_snapshot.is_valid():
			unresolved_inputs += PackedStringArray(
				["missing valid pre-advance fatigue snapshot for %s" % player.player_id]
			)
			continue
		if not player.sprint_energy_initialized:
			player.sprint_energy = player.fatigue_snapshot.initial_sprint_energy
			player.sprint_energy_initialized = true
		if (
			not is_finite(player.speed_stat)
			or not is_finite(player.acceleration_stat)
			or not is_finite(player.urgency)
		):
			unresolved_inputs += PackedStringArray(
				["missing locomotion stats or urgency for %s" % player.player_id]
			)
			continue
		player.run_speed_m_s = params.run_speed(player.speed_stat)
		player.sprint_speed_m_s = params.sprint_speed(player.speed_stat)
		var sprint_allowed: bool = can_sprint(player.sprint_energy, player.sprinting)
		var accel_factor: float = (
			1.0
			- clampf(player.acceleration_stat, params.attribute_min, params.attribute_max) / 100.0
		)
		player.sprinting = (
			player.sprint_request == 1 and sprint_allowed and accel_factor < player.urgency
		)
		player.desired_speed_m_s = (
			player.sprint_speed_m_s if player.sprinting else player.run_speed_m_s
		)
		var below_run_speed: bool = player.speed_m_s < player.run_speed_m_s
		var accel_time: float = params.run_accel_time_s
		var speed_delta: float = player.run_speed_m_s
		if not below_run_speed and player.sprinting:
			accel_time = params.acceleration_time(player.acceleration_stat)
			speed_delta = player.sprint_speed_m_s - player.run_speed_m_s
		var instant_acceleration: bool = (
			player.sprinting
			and not below_run_speed
			and accel_time < params.instant_acceleration_time_threshold_s
		)
		var speed_rate: float = speed_delta if instant_acceleration else speed_delta / accel_time
		player.acceleration_increment_m_s_per_tick = speed_rate * MATCH_DT
		if instant_acceleration:
			player.speed_m_s = player.desired_speed_m_s
		else:
			player.speed_m_s = move_toward(
				player.speed_m_s,
				player.desired_speed_m_s,
				player.acceleration_increment_m_s_per_tick
			)
		var energy_rate: float = params.energy_rate(
			player.speed_m_s, player.run_speed_m_s, pitch_condition, fatigue_multiplier
		)
		player.sprint_energy = clampf(
			player.sprint_energy + energy_rate * MATCH_DT,
			params.energy_minimum,
			player.fatigue_snapshot.energy_cap
		)
		player.stagger_timer_s = maxf(0.0, player.stagger_timer_s - MATCH_DT)
	_initial_inputs_available = false


## Captures all mutable locomotion state for an S2 tick transaction.
func transaction_checkpoint() -> SimDependencyCheckpoint:
	var checkpoint: SimDependencyCheckpoint = SimDependencyCheckpoint.new()
	checkpoint.complete = true
	var player_copies: Array[PlayerMotionState] = []
	for player: PlayerMotionState in players:
		player_copies.append(player.duplicate_state())
	checkpoint.state = {
		"players": player_copies,
		"pitch_condition": pitch_condition,
		"fatigue_option": fatigue_option,
		"unresolved_inputs": unresolved_inputs.duplicate(),
		"initial_inputs_available": _initial_inputs_available,
		"updated_player_ids": _updated_player_ids.duplicate(),
	}
	return checkpoint


## Restores all mutable locomotion state from an S2 tick transaction.
func restore_transaction_checkpoint(checkpoint: SimDependencyCheckpoint) -> bool:
	if checkpoint == null or not checkpoint.complete:
		return false
	var saved: Dictionary = checkpoint.state
	var unresolved_value: Variant = saved.get("unresolved_inputs")
	if not unresolved_value is PackedStringArray:
		return false
	var restored_unresolved_inputs: PackedStringArray = unresolved_value
	var updated_ids_value: Variant = saved.get("updated_player_ids")
	if not updated_ids_value is Dictionary:
		return false
	var restored_updated_player_ids: Dictionary[StringName, bool] = {}
	for player_id: Variant in updated_ids_value:
		var is_updated: Variant = updated_ids_value[player_id]
		if not player_id is StringName or not is_updated is bool:
			return false
		restored_updated_player_ids[player_id] = is_updated
	players.clear()
	for player: PlayerMotionState in saved["players"]:
		players.append(player.duplicate_state())
	pitch_condition = saved["pitch_condition"]
	fatigue_option = saved["fatigue_option"]
	unresolved_inputs = restored_unresolved_inputs.duplicate()
	_initial_inputs_available = saved["initial_inputs_available"]
	_updated_player_ids = restored_updated_player_ids
	return true


func snapshot() -> Dictionary:
	var player_data: Array[Dictionary] = []
	for player: PlayerMotionState in players:
		player_data += [player.snapshot()]
	return {
		"params": _resource_snapshot(params),
		"pitch_condition": pitch_condition,
		"fatigue_option": fatigue_option,
		"players": player_data,
		"unresolved_inputs": Array(unresolved_inputs),
		"initial_inputs_available": _initial_inputs_available,
		"updated_player_ids": _updated_ids_snapshot(),
	}


## Declares that [method snapshot] includes all future-affecting locomotion state.
func snapshot_is_complete() -> bool:
	return true


## Returns whether an energy level may begin or continue sprinting.
func can_sprint(energy: float, already_sprinting: bool) -> bool:
	if params == null:
		return false
	return (
		energy > params.sprint_continue_energy_strict
		if already_sprinting
		else energy > params.sprint_start_energy_strict
	)


func _player_less(left: PlayerMotionState, right: PlayerMotionState) -> bool:
	if left.team_id != right.team_id:
		return String(left.team_id) < String(right.team_id)
	if left.shirt_number != right.shirt_number:
		return left.shirt_number < right.shirt_number
	return String(left.player_id) < String(right.player_id)


func _updated_ids_snapshot() -> Array[StringName]:
	var ids: Array[StringName] = []
	for player_id: StringName in _updated_player_ids:
		ids.append(player_id)
	ids.sort_custom(_string_name_less)
	return ids


func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


func _process_player_commands() -> void:
	if runtime_port == null:
		return
	_updated_player_ids.clear()
	for command: S2RuntimeCommand in runtime_port.commands_for_phase(
		S2RuntimeCommand.Phase.LOCOMOTION
	):
		var result: S2RuntimeResult = S2RuntimeResult.new()
		if command.validate().is_empty() and _apply_player_input(command.player_input):
			result.status = S2RuntimeResult.Status.SUCCEEDED
		else:
			result.status = S2RuntimeResult.Status.REJECTED
			result.detail = "player tick input did not match a composed player"
		runtime_port.complete_command(command, result)
		if not runtime_port.tick_succeeded():
			return


func _apply_player_input(input: S2PlayerTickInput) -> bool:
	if input == null or not input.is_valid():
		return false
	for index: int in players.size():
		var player: PlayerMotionState = players[index]
		if player.player_id != input.player_id:
			continue
		if (
			player.team_id != input.fatigue_snapshot.team_id
			or player.player_id != input.fatigue_snapshot.player_id
			or player.shirt_number != input.fatigue_snapshot.shirt_number
		):
			return false
		var updated: PlayerMotionState = player.duplicate_state()
		updated.sprint_request = input.sprint_request
		updated.urgency = input.urgency
		updated.fatigue_snapshot = _copy_fatigue(input.fatigue_snapshot)
		players[index] = updated
		_updated_player_ids[input.player_id] = true
		return true
	return false


func _copy_fatigue(source: PlayerFatigueSnapshot) -> PlayerFatigueSnapshot:
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


func _property_name(property: Dictionary) -> String:
	var raw_name: Variant = property.get("name", "")
	if raw_name is String:
		var property_name: String = raw_name
		return property_name
	if raw_name is StringName:
		var property_name_value: StringName = raw_name
		return String(property_name_value)
	return ""


func _resource_snapshot(resource: Resource) -> Dictionary:
	var result: Dictionary = {}
	if resource == null:
		return result
	var names: Array[String] = []
	for property: Dictionary in resource.get_property_list():
		var usage_value: Variant = property.get("usage", 0)
		if not usage_value is int:
			continue
		var usage: int = usage_value
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names += [_property_name(property)]
	names.sort()
	for property_name: String in names:
		result[property_name] = resource.get(property_name)
	return result
