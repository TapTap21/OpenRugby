class_name MatchSim
extends RefCounted
## Deterministic fixed-step match simulation: clock, flow state machine and registered systems.
##
## The only inputs are the config, the seed and one [InputFrame] per tick. It never touches
## engine singletons; the runner relays its signals.

## The flow moved from [param from_state] to [param to_state].
signal state_changed(from_state: StringName, to_state: StringName)
## A period (1-based) started.
signal period_started(period: int)
## A period (1-based) ended.
signal period_ended(period: int)
## The match reached a terminal state.
signal finished

const TICKS_PER_SECOND: int = 60

## Match configuration; read-only after construction.
var config: MatchConfig
var rng: SimRng
var clock: MatchClock
var flow: MatchStateMachine
## Ticks executed so far.
var tick_count: int = 0
var s2_runtime_port: S2RuntimePort
var last_tick_succeeded: bool = true

var _valid: bool = false
var _finished: bool = false
var _systems: Array[SimSystem] = []
var _pending_triggers: Array[StringName] = []
var _current: InputFrame
var _previous: InputFrame


func _init(p_config: MatchConfig) -> void:
	config = p_config
	if p_config == null:
		push_error("MatchSim: config is null")
		_current = InputFrame.new(1, 2)
		_previous = InputFrame.new(1, 2)
		return
	var errors: PackedStringArray = p_config.validate()
	if not errors.is_empty():
		push_error("MatchSim: invalid config: " + "; ".join(errors))
		_current = InputFrame.new(1, 2)
		_previous = InputFrame.new(1, 2)
		return
	rng = SimRng.new(p_config.seed)
	clock = MatchClock.new(
		p_config.rules.period_count,
		p_config.period_real_seconds * TICKS_PER_SECOND,
		p_config.rules.period_game_seconds
	)
	flow = MatchStateMachine.new(p_config.flow)
	_current = InputFrame.new(p_config.slot_count, p_config.axes_per_slot)
	_previous = InputFrame.new(p_config.slot_count, p_config.axes_per_slot)
	_valid = true


## True when the config validated and the sim can run.
func is_valid() -> bool:
	return _valid


## Registers [param system]; only allowed before the first tick.
func add_system(system: SimSystem) -> void:
	if tick_count > 0:
		push_error("MatchSim.add_system: systems cannot be added after the first tick")
		return
	_systems.append(system)
	system.setup(self)


## Runs one simulation tick with [param frame] as the input.
func tick(frame: InputFrame) -> void:
	if not _valid or _finished:
		last_tick_succeeded = false
		return
	var system_checkpoints: Array[SimDependencyCheckpoint] = []
	var previous_current: InputFrame = null
	var previous_previous: InputFrame = null
	var original_tick: int = tick_count
	var original_rng: SimRng = rng
	var original_rng_state: int = original_rng.get_state()
	var original_triggers: Array[StringName] = _pending_triggers.duplicate()
	var original_clock: MatchClock = clock
	var original_clock_state: Dictionary = _clock_state(clock)
	var original_flow: MatchStateMachine = flow
	var original_flow_state: Dictionary = _flow_state(flow)
	var original_finished: bool = _finished
	if s2_runtime_port != null:
		for system: SimSystem in _systems:
			var checkpoint: SimDependencyCheckpoint = system.transaction_checkpoint()
			if checkpoint == null or not checkpoint.complete:
				s2_runtime_port.fail_tick(
					"%s could not create a tick checkpoint" % system.system_id()
				)
				last_tick_succeeded = false
				return
			system_checkpoints.append(checkpoint)
		previous_current = _copy_frame(_current)
		previous_previous = _copy_frame(_previous)
		s2_runtime_port.begin_tick()
	tick_count += 1
	_previous.copy_from(_current)
	if frame.slot_count == _current.slot_count and frame.axes_per_slot == _current.axes_per_slot:
		_current.copy_from(frame)
	else:
		push_error("MatchSim.tick: input frame shape mismatch")
		_current.clear()
		_current.tick = frame.tick
	for system: SimSystem in _systems:
		system.tick(self)
		if s2_runtime_port != null and not s2_runtime_port.tick_succeeded():
			break
	if s2_runtime_port != null and not s2_runtime_port.tick_succeeded():
		for index: int in range(_systems.size() - 1, -1, -1):
			if not _systems[index].restore_transaction_checkpoint(system_checkpoints[index]):
				s2_runtime_port.fail_tick(
					"%s failed to restore its tick checkpoint" % _systems[index].system_id()
				)
		rng = original_rng
		rng.set_state(original_rng_state)
		tick_count = original_tick
		_current.copy_from(previous_current)
		_previous.copy_from(previous_previous)
		_pending_triggers = original_triggers
		clock = original_clock
		_restore_clock_state(clock, original_clock_state)
		flow = original_flow
		_restore_flow_state(flow, original_flow_state)
		_finished = original_finished
		s2_runtime_port.rollback_tick()
		last_tick_succeeded = false
		return
	var def: MatchStateDef = flow.current_def()
	if def.clock_runs:
		clock.advance()
	flow.ticks_in_state += 1
	var transition: MatchTransitionDef = flow.find_transition(self, _pending_triggers)
	if transition != null:
		_apply_transition(transition)
	_pending_triggers.clear()
	if s2_runtime_port != null:
		s2_runtime_port.commit_tick()
	last_tick_succeeded = true


## Queues [param trigger] for evaluation in the current or next tick.
func raise_trigger(trigger: StringName) -> void:
	_pending_triggers.append(trigger)


## Id of the current flow state ([code]&""[/code] for an invalid sim).
func current_state() -> StringName:
	if flow == null:
		return &""
	return flow.current


## True once a terminal state was entered.
func is_finished() -> bool:
	return _finished


## True when flow data marks the current state as simulation-active.
func is_simulation_active() -> bool:
	if flow == null:
		return false
	var state_def: MatchStateDef = flow.current_def()
	return state_def != null and state_def.simulation_active and not _finished


## True while button [param bit] is held on [param slot] in the current tick.
func is_held(slot: int, bit: int) -> bool:
	return _current.is_held(slot, bit)


## True when the button went down this tick.
func just_pressed(slot: int, bit: int) -> bool:
	return _current.is_held(slot, bit) and not _previous.is_held(slot, bit)


## True when the button went up this tick.
func just_released(slot: int, bit: int) -> bool:
	return _previous.is_held(slot, bit) and not _current.is_held(slot, bit)


## Quantised axis value for the current tick.
func get_axis(slot: int, axis: int) -> int:
	return _current.get_axis(slot, axis)


## Returns the full simulation state with a stable key order (only [code]tick[/code] and
## [code]valid[/code] for an invalid sim).
func snapshot() -> Dictionary:
	if not _valid:
		return {"tick": tick_count, "valid": false}
	var systems_data: Array = []
	for system: SimSystem in _systems:
		systems_data.append({"id": system.system_id(), "data": system.snapshot()})
	var pending: Array[StringName] = _pending_triggers.duplicate()
	return {
		"tick": tick_count,
		"rng_seed": rng.seed,
		"rng_state": rng.get_state(),
		"state": flow.current,
		"ticks_in_state": flow.ticks_in_state,
		"period": clock.period,
		"elapsed_ticks": clock.elapsed_ticks,
		"finished": _finished,
		"pending_triggers": pending,
		"input_buttons": _current.buttons.duplicate(),
		"input_axes": _current.axes.duplicate(),
		"previous_input_buttons": _previous.buttons.duplicate(),
		"previous_input_axes": _previous.axes.duplicate(),
		"systems": systems_data,
		"s2_runtime": s2_runtime_port.snapshot() if s2_runtime_port != null else {},
	}


func _copy_frame(source: InputFrame) -> InputFrame:
	var copy: InputFrame = InputFrame.new(source.slot_count, source.axes_per_slot)
	copy.copy_from(source)
	return copy


func _clock_state(source: MatchClock) -> Dictionary:
	return {
		"period": source.period,
		"period_count": source.period_count,
		"period_ticks": source.period_ticks,
		"elapsed_ticks": source.elapsed_ticks,
		"game_seconds_per_period": source.game_seconds_per_period,
	}


func _restore_clock_state(target: MatchClock, state: Dictionary) -> void:
	target.period = state["period"]
	target.period_count = state["period_count"]
	target.period_ticks = state["period_ticks"]
	target.elapsed_ticks = state["elapsed_ticks"]
	target.game_seconds_per_period = state["game_seconds_per_period"]


func _flow_state(source: MatchStateMachine) -> Dictionary:
	return {
		"config": source.config,
		"current": source.current,
		"ticks_in_state": source.ticks_in_state,
	}


func _restore_flow_state(target: MatchStateMachine, state: Dictionary) -> void:
	target.config = state["config"]
	target.current = state["current"]
	target.ticks_in_state = state["ticks_in_state"]


## Lowercase hex SHA-256 of the serialised snapshot.
func state_hash() -> String:
	var ctx: HashingContext = HashingContext.new()
	var err: Error = ctx.start(HashingContext.HASH_SHA256)
	assert(err == OK)
	err = ctx.update(var_to_bytes(snapshot()))
	assert(err == OK)
	return ctx.finish().hex_encode()


func _apply_transition(transition: MatchTransitionDef) -> void:
	var from_state: StringName = flow.current
	flow.current = transition.to
	flow.ticks_in_state = 0
	state_changed.emit(from_state, transition.to)
	if transition.period_effect == MatchTransitionDef.PeriodEffect.START:
		period_started.emit(clock.period)
	elif transition.period_effect == MatchTransitionDef.PeriodEffect.ADVANCE:
		clock.start_next_period()
		period_started.emit(clock.period)
	var def: MatchStateDef = flow.current_def()
	if def.ends_period:
		period_ended.emit(clock.period)
	if def.terminal:
		_finished = true
		finished.emit()
