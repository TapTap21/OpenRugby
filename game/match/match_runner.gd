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
	contact_solver: BallContactSolver = null
) -> Error:
	if Engine.physics_ticks_per_second != MatchSim.TICKS_PER_SECOND:
		return ERR_UNCONFIGURED
	if (
		contact_source == null
		or contact_solver == null
		or not contact_source.is_available()
		or not contact_solver.is_available()
	):
		return ERR_UNCONFIGURED
	var effective_config: MatchConfig = config.duplicate(true) as MatchConfig
	if extension_points != null:
		var filtered_flow: Variant = extension_points.filter(
			BaseExtensionPoints.MATCH_FLOW_CONFIG, effective_config.flow, [effective_config]
		)
		if not filtered_flow is MatchFlowConfig:
			return ERR_INVALID_PARAMETER
		effective_config.flow = filtered_flow
	if not effective_config.validate().is_empty():
		return ERR_INVALID_PARAMETER
	var provided_systems: Array = []
	var typed_provided_systems: Array[SimSystem] = []
	if extension_points != null:
		provided_systems = extension_points.collect(
			BaseExtensionPoints.MATCH_SIM_SYSTEMS, [effective_config]
		)
	for provided_system: Variant in provided_systems:
		if not provided_system is SimSystem:
			return ERR_INVALID_PARAMETER
		typed_provided_systems.append(provided_system)
	sim = MatchSim.new(effective_config)
	for system: SimSystem in systems:
		sim.add_system(system)
	for system: SimSystem in typed_provided_systems:
		sim.add_system(system)
	sim.add_system(LocomotionSystem.new(effective_config.s2_physics.locomotion))
	var ball_system: BallPhysicsSystem = BallPhysicsSystem.new(
		effective_config.s2_physics.ball,
		effective_config.s2_physics.surfaces,
		contact_source,
		contact_solver
	)
	ball_system.pitch_condition = effective_config.s2_physics.pitch_condition
	ball_system.stadium_id = effective_config.s2_physics.stadium_id
	ball_system.configure_extensions(extension_points, effective_config)
	sim.add_system(ball_system)
	var interaction_system: S2InteractionSystem = S2InteractionSystem.new(
		effective_config.s2_physics.tackle, effective_config.s2_physics.catches
	)
	interaction_system.configure_extensions(extension_points)
	sim.add_system(interaction_system)
	var header: ReplayHeader = ReplayHeader.new()
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	header.game_version = version
	header.seed = effective_config.seed
	header.mod_set_hash = mod_set_hash
	header.action_layout_hash = source.layout_hash()
	header.slot_count = effective_config.slot_count
	header.axes_per_slot = effective_config.axes_per_slot
	input_log = InputLog.new(header)
	_source = source
	_frame = InputFrame.new(effective_config.slot_count, effective_config.axes_per_slot)
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
	sim.tick(_frame)
	input_log.append(_frame)
	ticked.emit(sim.tick_count)
	return true


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
