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
	mod_set_hash: String = ""
) -> Error:
	if Engine.physics_ticks_per_second != MatchSim.TICKS_PER_SECOND:
		return ERR_UNCONFIGURED
	if not config.validate().is_empty():
		return ERR_INVALID_PARAMETER
	sim = MatchSim.new(config)
	for system: SimSystem in systems:
		sim.add_system(system)
	var header: ReplayHeader = ReplayHeader.new()
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	header.game_version = version
	header.seed = config.seed
	header.mod_set_hash = mod_set_hash
	header.action_layout_hash = source.layout_hash()
	header.slot_count = config.slot_count
	header.axes_per_slot = config.axes_per_slot
	input_log = InputLog.new(header)
	_source = source
	_frame = InputFrame.new(config.slot_count, config.axes_per_slot)
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
	EventBus.match_state_changed.emit(from_state, to_state, sim.tick_count)


func _on_sim_period_started(period: int) -> void:
	EventBus.match_period_started.emit(period)


func _on_sim_period_ended(period: int) -> void:
	EventBus.match_period_ended.emit(period)


func _on_sim_finished() -> void:
	EventBus.match_finished.emit(sim.tick_count)
