# gdlint: disable=max-public-methods
class_name S2RuntimePort
extends RefCounted
## Typed, scene-free caller port for S2 setup, sequenced commands and typed results.

# This class is the intentionally broad typed boundary shared by callers and composed systems.

var contact_source: BallContactSource
var contact_solver: BallContactSolver
var ball_initialization: S2BallInitialization
var wind_policy: S2WindPolicy
var pitch_condition: int = -1
var fatigue_option: int = -1
var player_initializations: Array[S2PlayerInitialization] = []
var failure_detail: String = ""
var failure_sequence: int = -1

var _pending_commands: Array[S2RuntimeCommand] = []
var _results: Array[S2RuntimeResult] = []
var _next_sequence: int = 0
var _consumed: Dictionary[int, bool] = {}
var _in_tick: bool = false
var _tick_failed: bool = false
var _transaction_checkpoint: SimDependencyCheckpoint
var _ball_system: BallPhysicsSystem
var _locomotion_system: LocomotionSystem
var _interaction_system: S2InteractionSystem


## Supplies deterministic geometry for the composed ball system.
func set_contact_source(source: BallContactSource) -> void:
	contact_source = source


## Supplies the required contract-complete contact solver.
func set_contact_solver(solver: BallContactSolver) -> void:
	contact_solver = solver


## Supplies an explicit wind policy; wind-level conversion remains caller-owned.
func set_wind_policy(policy: S2WindPolicy) -> bool:
	if policy == null or not policy.is_valid():
		return false
	wind_policy = policy.duplicate_policy()
	return true


## Supplies caller-owned pitch and fatigue settings without mapping input actions.
func set_locomotion_environment(p_pitch_condition: int, p_fatigue_option: int) -> bool:
	if (
		p_pitch_condition < 0
		or p_pitch_condition > 5
		or p_fatigue_option < 0
		or p_fatigue_option > 100
	):
		return false
	fatigue_option = p_fatigue_option
	pitch_condition = p_pitch_condition
	return true


## Supplies explicit ball state before the first match tick.
func initialize_ball(initialization: S2BallInitialization) -> bool:
	if initialization == null or not initialization.validate().is_empty():
		return false
	ball_initialization = initialization.duplicate_setup()
	if initialization.wind_policy != null:
		wind_policy = initialization.wind_policy.duplicate_policy()
	return true


## Supplies one owner's complete player/fatigue setup before the first tick.
func add_player(initialization: S2PlayerInitialization) -> bool:
	if initialization == null or not initialization.validate().is_empty():
		return false
	for current: S2PlayerInitialization in player_initializations:
		if current.player.player_id == initialization.player.player_id:
			return false
	var detached: S2PlayerInitialization = S2PlayerInitialization.new()
	detached.player = initialization.copy_player()
	player_initializations.append(detached)
	return true


## Adds a typed command and returns its stable sequence, or -1 when rejected.
func enqueue(command: S2RuntimeCommand) -> int:
	if _in_tick or command == null or not command.validate().is_empty():
		return -1
	var detached: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(command.snapshot())
	if detached == null:
		return -1
	detached.sequence = _next_sequence
	_next_sequence += 1
	_pending_commands.append(detached)
	return detached.sequence


## Returns defensive typed copies of all published command outputs.
func results() -> Array[S2RuntimeResult]:
	var copied: Array[S2RuntimeResult] = []
	for result: S2RuntimeResult in _results:
		var duplicate: S2RuntimeResult = S2RuntimeResult.from_snapshot(result.snapshot())
		if duplicate != null:
			copied.append(duplicate)
	return copied


## Returns output records appended after [param first_index].
func results_since(first_index: int) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	if first_index < 0 or first_index > _results.size():
		return values
	for index: int in range(first_index, _results.size()):
		values.append(_results[index].snapshot())
	return values


## Returns current queued commands with sequence values for an input-log frame.
func queued_command_snapshots() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for command: S2RuntimeCommand in _pending_commands:
		values.append(command.snapshot())
	return values


## Queues a recorded frame's commands without changing their original sequence values.
func enqueue_replay_commands(values: Array[Dictionary]) -> bool:
	if _in_tick:
		return false
	var restored: Array[S2RuntimeCommand] = []
	var next_sequence: int = _next_sequence
	for value: Dictionary in values:
		var command: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(value)
		if command == null or not command.validate().is_empty():
			return false
		if command.sequence < next_sequence:
			return false
		restored.append(command)
		next_sequence = command.sequence + 1
	for command: S2RuntimeCommand in restored:
		_pending_commands.append(command)
	_next_sequence = next_sequence
	_pending_commands.sort_custom(_command_less)
	return true


## Clears only replay runtime queues and outputs; setup dependencies remain injected.
func reset_runtime() -> bool:
	if _in_tick:
		return false
	_pending_commands.clear()
	_results.clear()
	_consumed.clear()
	_next_sequence = 0
	_tick_failed = false
	failure_detail = ""
	failure_sequence = -1
	return true


## Stable setup values included in live/replay compatibility fingerprints.
func setup_snapshot() -> Dictionary:
	var player_data: Array[Dictionary] = []
	var ordered_players: Array[S2PlayerInitialization] = player_initializations.duplicate()
	ordered_players.sort_custom(_player_initialization_less)
	for initialization: S2PlayerInitialization in ordered_players:
		player_data.append(initialization.snapshot())
	return {
		"ball_initialization":
		ball_initialization.snapshot() if ball_initialization != null else {},
		"wind_policy": wind_policy.snapshot() if wind_policy != null else {},
		"players": player_data,
		"fatigue_option": fatigue_option,
		"pitch_condition": pitch_condition,
		"contact_source": _source_setup(),
		"contact_solver": _solver_setup(),
	}


## Deterministic runtime state, including queued inputs, outputs and both sequence positions.
func snapshot() -> Dictionary:
	var commands: Array[Dictionary] = queued_command_snapshots()
	var output_data: Array[Dictionary] = []
	for result: S2RuntimeResult in _results:
		output_data.append(result.snapshot())
	return {
		"next_sequence": _next_sequence,
		"commands": commands,
		"outputs": output_data,
	}


## True when the current match tick has not rejected a command or solver operation.
func tick_succeeded() -> bool:
	return not _tick_failed


## Binds the three composed systems without exposing their Node or scene relationships.
func bind(
	ball: BallPhysicsSystem, locomotion: LocomotionSystem, interactions: S2InteractionSystem
) -> void:
	_ball_system = ball
	_locomotion_system = locomotion
	_interaction_system = interactions


## Captures command queues and outputs before a match tick.
func begin_tick() -> void:
	_in_tick = true
	_tick_failed = false
	failure_detail = ""
	failure_sequence = -1
	_consumed.clear()
	_transaction_checkpoint = SimDependencyCheckpoint.new()
	_transaction_checkpoint.complete = true
	_transaction_checkpoint.state = {
		"commands": queued_command_snapshots(),
		"outputs": _output_snapshots(),
		"next_sequence": _next_sequence,
	}
	_results.clear()


## Commits successfully consumed command sequences and publishes their outputs.
func commit_tick() -> void:
	var kept: Array[S2RuntimeCommand] = []
	for command: S2RuntimeCommand in _pending_commands:
		if not _consumed.has(command.sequence):
			kept.append(command)
	_pending_commands = kept
	_in_tick = false
	_transaction_checkpoint = null


## Restores pending commands and outputs after MatchSim restores system/provider state.
func rollback_tick() -> void:
	if _transaction_checkpoint == null:
		_in_tick = false
		return
	var state: Dictionary = _transaction_checkpoint.state
	_pending_commands.clear()
	for raw_command: Dictionary in state["commands"]:
		var command: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(raw_command)
		if command != null:
			_pending_commands.append(command)
	_restore_outputs(state["outputs"])
	_next_sequence = state["next_sequence"]
	_consumed.clear()
	_in_tick = false
	_transaction_checkpoint = null


## Returns commands in their fixed phase order while preserving sequence within that phase.
func commands_for_phase(phase: S2RuntimeCommand.Phase) -> Array[S2RuntimeCommand]:
	var commands: Array[S2RuntimeCommand] = []
	for command: S2RuntimeCommand in _pending_commands:
		if command.phase() == phase and not _consumed.has(command.sequence):
			commands.append(command)
	commands.sort_custom(_command_less)
	return commands


## Records one successful, typed command output and marks the input consumed.
func complete_command(command: S2RuntimeCommand, result: S2RuntimeResult) -> void:
	if command == null or result == null:
		fail_tick("command execution produced no typed result", -1)
		return
	result.command_sequence = command.sequence
	result.command_kind = command.kind
	if not result.is_success():
		fail_tick(result.detail, command.sequence)
		return
	_results.append(result)
	_consumed[command.sequence] = true


## Marks the whole S2 tick for rollback and retains a caller-visible diagnostic.
func fail_tick(detail: String, sequence: int = -1) -> void:
	_tick_failed = true
	failure_detail = detail
	failure_sequence = sequence


## Typed subsystem references used only by the composed S2 systems.
func ball_system() -> BallPhysicsSystem:
	return _ball_system


## Typed subsystem references used only by the composed S2 systems.
func locomotion_system() -> LocomotionSystem:
	return _locomotion_system


## Typed subsystem references used only by the composed S2 systems.
func interaction_system() -> S2InteractionSystem:
	return _interaction_system


func _output_snapshots() -> Array[Dictionary]:
	var output_data: Array[Dictionary] = []
	for result: S2RuntimeResult in _results:
		output_data.append(result.snapshot())
	return output_data


func _restore_outputs(output_data: Array[Dictionary]) -> void:
	_results.clear()
	for value: Dictionary in output_data:
		var result: S2RuntimeResult = S2RuntimeResult.from_snapshot(value)
		if result != null:
			_results.append(result)


func _command_less(left: S2RuntimeCommand, right: S2RuntimeCommand) -> bool:
	return left.sequence < right.sequence


func _player_initialization_less(
	left: S2PlayerInitialization, right: S2PlayerInitialization
) -> bool:
	if left.player.team_id != right.player.team_id:
		return String(left.player.team_id) < String(right.player.team_id)
	if left.player.shirt_number != right.player.shirt_number:
		return left.player.shirt_number < right.player.shirt_number
	return String(left.player.player_id) < String(right.player.player_id)


func _provider_setup(provider: Object) -> Dictionary:
	if provider == null:
		return {}
	var script: Script = provider.get_script() as Script
	return {
		"class": provider.get_class(),
		"script_path": script.resource_path if script != null else "",
		"snapshot": {},
	}


func _source_setup() -> Dictionary:
	if contact_source == null:
		return {}
	var setup: Dictionary = _provider_setup(contact_source)
	setup["snapshot"] = contact_source.snapshot()
	return setup


func _solver_setup() -> Dictionary:
	if contact_solver == null:
		return {}
	var setup: Dictionary = _provider_setup(contact_solver)
	setup["snapshot"] = contact_solver.snapshot()
	return setup
