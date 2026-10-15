# gdlint: disable=max-returns
class_name MatchRunner
extends Node
## Drives a [MatchSim] from the physics tick, records the input log and relays sim signals to
## the global event bus. This is the only place in the match folder that touches engine state.

## Emitted after each executed tick with the 1-based tick number.
signal ticked(tick: int)
## Emitted when the input source has no more frames.
signal input_ended

var sim: MatchSim
var input_log: InputLog

var _source: InputSource
var _frame: InputFrame
var _running: bool = false
var _candidate_commands: DetachedCommandBundle
var _waiting_retry: bool = false
var _candidate_ready: bool = false
var _publishing: bool = false


func _physics_process(_delta: float) -> void:
	if _running and not _waiting_retry:
		var advanced: bool = step_once()
		assert(advanced or _waiting_retry or not _running or sim.is_finished())


## Builds the sim and starts running; returns an error code when it cannot start.
func start(
	config: MatchConfig,
	source: InputSource,
	_systems: Array[SimSystem] = [],
	mod_set_hash: String = "",
	extension_points: ExtensionPoints = null
) -> Error:
	if _running or _publishing:
		return ERR_INVALID_PARAMETER
	sim = null
	input_log = null
	_source = null
	_frame = null
	_candidate_commands = null
	_candidate_ready = false
	_waiting_retry = false
	if config == null or source == null:
		return ERR_INVALID_PARAMETER
	# Replay remains unavailable until the S2 typed codec and receipt path are implemented.
	if source is ReplayInputSource:
		return ERR_UNCONFIGURED
	if _has_extension_hooks(extension_points):
		return ERR_UNCONFIGURED
	sim = MatchSim.new(config)
	if not sim.is_valid():
		sim = null
		return ERR_INVALID_PARAMETER
	for system: SimSystem in _systems:
		var add_error: Error = sim.add_system(system)
		if add_error != OK:
			sim = null
			return add_error
	var ownership_error: Error = sim.claim_runner_ownership()
	if ownership_error != OK:
		sim = null
		return ownership_error
	var header: ReplayHeader = ReplayHeader.new()
	header.format_version = InputLog.FORMAT_VERSION
	header.game_version = str(ProjectSettings.get_setting("application/config/version", ""))
	header.seed = config.seed
	header.mod_set_hash = mod_set_hash
	header.action_layout_hash = source.layout_hash()
	header.tick_rate = MatchSim.TICKS_PER_SECOND
	header.slot_count = config.slot_count
	header.axes_per_slot = config.axes_per_slot
	input_log = InputLog.new(header)
	_source = source
	_frame = InputFrame.new(config.slot_count, config.axes_per_slot)
	_candidate_commands = null
	_candidate_ready = false
	_waiting_retry = false
	var state_connection: Error = sim.state_changed.connect(_on_sim_state_changed)
	var start_connection: Error = sim.period_started.connect(_on_sim_period_started)
	var end_connection: Error = sim.period_ended.connect(_on_sim_period_ended)
	var finish_connection: Error = sim.finished.connect(_on_sim_finished)
	if (
		state_connection != OK
		or start_connection != OK
		or end_connection != OK
		or finish_connection != OK
	):
		sim = null
		input_log = null
		_source = null
		_frame = null
		return ERR_ALREADY_EXISTS
	_running = true
	return OK


## Stops stepping the sim.
func stop() -> void:
	_running = false


## True while the runner is stepping the sim.
func is_running() -> bool:
	return _running


## Runs one tick; false when not running, finished, or the input source ran out.
func step_once() -> bool:
	if _publishing or not _running or sim == null or _source == null or input_log == null:
		return false
	if sim.is_finished():
		_running = false
		return false
	if not _waiting_retry:
		_frame.clear()
		_frame.tick = sim.tick_count
		var builder: DetachedCommandBundleBuilder = DetachedCommandBundleBuilder.new()
		if not _source.fill_frame(sim.tick_count, _frame, builder):
			_running = false
			input_ended.emit()
			return false
		_frame.tick = sim.tick_count
		_candidate_commands = builder.seal()
		if _candidate_commands == null or not _candidate_commands.is_valid():
			_running = false
			push_warning("MatchRunner: input source produced an invalid command bundle")
			return false
		if _candidate_commands.size() != 0:
			_running = false
			push_warning("MatchRunner: command-bearing input requires the S2 typed codec")
			return false
		_candidate_ready = true
	if not _candidate_ready or _candidate_commands == null:
		_running = false
		return false
	var tick_result: TickResult = sim.tick_checked(_frame, _candidate_commands)
	if tick_result.status != TickResult.Status.PREPARED or tick_result.prepared_tick == null:
		if tick_result.status == TickResult.Status.FATAL_ROLLBACK:
			_running = false
		else:
			_waiting_retry = true
		return false
	var prepared_tick: PreparedTick = tick_result.prepared_tick
	if not prepared_tick._outputs.is_empty():
		var output_abort_error: Error = sim.abort_prepared_tick(prepared_tick)
		_running = false
		if output_abort_error != OK:
			push_error("MatchRunner: output rejection rollback failed")
		else:
			push_warning("MatchRunner: tick outputs require the S2 typed codec")
		return false
	var append_result: AppendPrepareResult = input_log.prepare_empty_live_append(prepared_tick)
	if not append_result.ok:
		var prepare_abort_error: Error = sim.abort_prepared_tick(prepared_tick)
		if prepare_abort_error != OK:
			_running = false
			push_error("MatchRunner: append preparation rollback failed")
		else:
			_waiting_retry = true
		return false
	var token: PreparedAppendToken = append_result.token
	if not sim._register_append_registration(input_log, token, prepared_tick):
		var register_abort_error: Error = sim.abort_prepared_tick(prepared_tick)
		var cancel_error: Error = input_log.cancel_append(token)
		if register_abort_error != OK or cancel_error != OK:
			_running = false
			push_error("MatchRunner: failed to roll back append registration")
		else:
			_waiting_retry = true
		return false
	sim.finalize_prepared_tick(prepared_tick, token)
	if prepared_tick._active:
		var finalize_abort_error: Error = sim.abort_prepared_tick(prepared_tick)
		if finalize_abort_error != OK:
			_running = false
		else:
			_waiting_retry = true
		return false
	var commit_error: Error = input_log.commit_append(token)
	if commit_error != OK:
		_running = false
		push_error("MatchRunner: append failed after sim finalization")
		return false
	var committed_tick: int = prepared_tick.candidate_tick
	_candidate_ready = false
	_candidate_commands = null
	_waiting_retry = false
	if sim.is_finished():
		_running = false
	_publishing = true
	sim.publish_staged_signals(tick_result.signal_batch)
	ticked.emit(committed_tick)
	_publishing = false
	return true


func _has_extension_hooks(extension_points: ExtensionPoints) -> bool:
	if extension_points == null:
		return false
	for point: String in extension_points.declared_points():
		if not extension_points.hooks(StringName(point)).is_empty():
			return true
	return false


## Fraction of the current physics tick elapsed, for presenters that interpolate manually.
func interpolation_fraction() -> float:
	return Engine.get_physics_interpolation_fraction()


func _on_sim_state_changed(from_state: StringName, to_state: StringName) -> void:
	_emit_bus_signal(&"match_state_changed", [from_state, to_state, sim.tick_count])


func _on_sim_period_started(period: int) -> void:
	_emit_bus_signal(&"match_period_started", [period])


func _on_sim_period_ended(period: int) -> void:
	_emit_bus_signal(&"match_period_ended", [period])


func _on_sim_finished() -> void:
	_emit_bus_signal(&"match_finished", [sim.tick_count])


func _emit_bus_signal(signal_name: StringName, arguments: Array) -> void:
	var emit_result: Error = EventBusAccess.emit(signal_name, arguments)
	if emit_result != OK and emit_result != ERR_UNAVAILABLE:
		push_warning(
			"MatchRunner: could not emit %s (%s)" % [signal_name, error_string(emit_result)]
		)
