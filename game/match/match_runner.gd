class_name MatchRunner
extends Node
## Drives a [MatchSim] from the physics tick, records the input log and relays sim signals to
## the global event bus. This is the only place in the match folder that touches engine state.

## Emitted after each executed tick with the 1-based tick number.
signal ticked(tick: int)
## Emitted when the input source has no more frames.
signal input_ended
## Emitted when composition cannot start; the report lists the missing capabilities.
signal start_blocked(report: MatchReadinessReport)

var sim: MatchSim
var input_log: InputLog
var runtime_port: S2RuntimePort
var last_build_result: MatchBuildResult

var _source: InputSource
var _frame: InputFrame
var _running: bool = false


func _physics_process(_delta: float) -> void:
	if _running:
		var advanced: bool = step_once()
		assert(advanced or not _running or sim.is_finished())


## Builds the sim and starts running; returns an error code when it cannot start.
func start(
	config: MatchConfig,
	source: InputSource,
	systems: Array[SimSystem] = [],
	mod_set_hash: String = "",
	extension_points: ExtensionPoints = null,
	contact_source: BallContactSource = null,
	contact_solver: BallContactSolver = null,
	s2_port: S2RuntimePort = null
) -> Error:
	_running = false
	var resolved_port: S2RuntimePort = s2_port if s2_port != null else S2RuntimePort.new()
	if contact_source != null:
		resolved_port.set_contact_source(contact_source)
	if contact_solver != null:
		resolved_port.set_contact_solver(contact_solver)
	var request: MatchCompositionRequest = MatchCompositionRequest.new()
	request.config = config
	request.systems = systems.duplicate()
	request.mod_set_hash = mod_set_hash
	request.action_layout_hash = source.layout_hash() if source != null else ""
	request.extension_points = extension_points
	request.s2 = resolved_port
	last_build_result = MatchCompositionBuilder.build(request)
	if config == null:
		if (
			last_build_result
			. readiness
			. details_for(MatchReadinessReport.Capability.MATCH_CONFIG)
			. is_empty()
		):
			last_build_result.readiness.add_blocker(
				MatchReadinessReport.Capability.MATCH_CONFIG,
				"original match configuration is missing"
			)
		last_build_result.error = ERR_INVALID_PARAMETER
	else:
		var original_config_errors: PackedStringArray = config.validate()
		var reported_config_errors: PackedStringArray = last_build_result.readiness.details_for(
			MatchReadinessReport.Capability.MATCH_CONFIG
		)
		for error_message: String in original_config_errors:
			if not reported_config_errors.has(error_message):
				last_build_result.readiness.add_blocker(
					MatchReadinessReport.Capability.MATCH_CONFIG,
					"original match configuration is invalid: %s" % error_message
				)
		if not original_config_errors.is_empty():
			last_build_result.error = ERR_INVALID_PARAMETER
	if source == null:
		last_build_result.readiness.add_blocker(
			MatchReadinessReport.Capability.MATCH_CONFIG, "input source is missing"
		)
		if last_build_result.error != ERR_INVALID_PARAMETER:
			last_build_result.error = ERR_UNCONFIGURED
	if not last_build_result.is_success():
		sim = null
		input_log = null
		runtime_port = last_build_result.s2
		start_blocked.emit(last_build_result.readiness)
		return last_build_result.error
	sim = last_build_result.sim
	runtime_port = last_build_result.s2
	var header: ReplayHeader = ReplayHeader.new()
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	header.game_version = version
	header.seed = sim.config.seed
	header.mod_set_hash = mod_set_hash
	header.action_layout_hash = request.action_layout_hash
	header.setup_fingerprint = last_build_result.setup_fingerprint
	header.slot_count = sim.config.slot_count
	header.axes_per_slot = sim.config.axes_per_slot
	input_log = InputLog.new(header)
	_source = source
	_frame = InputFrame.new(sim.config.slot_count, sim.config.axes_per_slot)
	var err: int = sim.state_changed.connect(_on_sim_state_changed)
	assert(err == OK)
	err = sim.period_started.connect(_on_sim_period_started)
	assert(err == OK)
	err = sim.period_ended.connect(_on_sim_period_ended)
	assert(err == OK)
	err = sim.finished.connect(_on_sim_finished)
	assert(err == OK)
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
	if not _running or sim.is_finished():
		return false
	if not _source.fill_frame(sim.tick_count, _frame):
		_running = false
		input_ended.emit()
		return false
	_frame.tick = sim.tick_count
	var frame_commands: Array[Dictionary] = runtime_port.queued_command_snapshots()
	sim.tick(_frame)
	if not sim.last_tick_succeeded:
		_running = false
		return false
	input_log.append(_frame, frame_commands, runtime_port.results_since(0))
	ticked.emit(sim.tick_count)
	return true


## Fraction of the current physics tick elapsed, for presenters that interpolate manually.
func interpolation_fraction() -> float:
	return Engine.get_physics_interpolation_fraction()


## Typed report for the most recent failed or successful composition attempt.
func readiness_report() -> MatchReadinessReport:
	return last_build_result.readiness if last_build_result != null else MatchReadinessReport.new()


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
