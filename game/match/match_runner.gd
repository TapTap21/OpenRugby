# gdlint: disable=max-returns
class_name MatchRunner
extends Node
## Drives a [MatchSim] from the physics tick, records the input log and relays sim signals to
## the global event bus. This is the only place in the match folder that touches engine state.

## Emitted after each executed tick with the 1-based tick number.
signal ticked(tick: int)
## Emitted when the input source has no more frames.
signal input_ended

const _TYPED_CODEC_AVAILABLE: bool = false

var sim: MatchSim
var input_log: InputLog

var _source: InputSource
var _frame: InputFrame
var _running: bool = false
var _candidate_commands: DetachedCommandBundle
var _waiting_retry: bool = false


func _physics_process(_delta: float) -> void:
	if _running and not _waiting_retry:
		var advanced: bool = step_once()
		assert(advanced or not _running or sim.is_finished())


## Builds the sim and starts running; returns an error code when it cannot start.
func start(
	_config: MatchConfig,
	source: InputSource,
	_systems: Array[SimSystem] = [],
	_mod_set_hash: String = "",
	_extension_points: ExtensionPoints = null
) -> Error:
	# Production recording is disabled until the reviewed typed S2 codec/port seam is present.
	if source == null:
		return ERR_INVALID_PARAMETER
	return ERR_UNCONFIGURED


## Stops stepping the sim.
func stop() -> void:
	_running = false


## True while the runner is stepping the sim.
func is_running() -> bool:
	return _running


## Runs one tick; false when not running, finished, or the input source ran out.
func step_once() -> bool:
	# Return before source sampling or sim mutation until the reviewed typed S2 codec exists.
	if not _TYPED_CODEC_AVAILABLE:
		return false
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
