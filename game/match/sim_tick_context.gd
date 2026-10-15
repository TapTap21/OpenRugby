class_name SimTickContext
extends RefCounted
## Immutable generic view of the candidate input and pre-tick simulation state.

# gdlint: disable=class-definitions-order,function-arguments-number

var _candidate_tick: int
var _candidate_attempt_id: int
var _candidate_frame: InputFrame
var _previous_frame: InputFrame
var _pressed_buttons: PackedInt64Array
var _released_buttons: PackedInt64Array
var _commands: DetachedCommandBundle
var _pre_clock_period: int
var _pre_clock_elapsed_ticks: int
var _pre_clock_period_count: int
var _pre_clock_period_ticks: int
var _pre_clock_game_seconds_per_period: int
var _pre_flow_state: StringName
var _pre_flow_ticks_in_state: int
var _pre_pending_triggers: Array[StringName]
var _clock_delta_numerator: int
var _clock_delta_denominator: int


func _init(
	p_candidate_tick: int,
	p_candidate_frame: InputFrame,
	p_previous_frame: InputFrame,
	p_pressed_buttons: PackedInt64Array,
	p_released_buttons: PackedInt64Array,
	p_commands: DetachedCommandBundle,
	p_pre_clock_period: int,
	p_pre_clock_elapsed_ticks: int,
	p_pre_clock_period_count: int,
	p_pre_clock_period_ticks: int,
	p_pre_clock_game_seconds_per_period: int,
	p_pre_flow_state: StringName,
	p_pre_flow_ticks_in_state: int,
	p_pre_pending_triggers: Array[StringName],
	p_clock_delta_numerator: int,
	p_clock_delta_denominator: int,
	p_candidate_attempt_id: int
) -> void:
	_candidate_tick = p_candidate_tick
	_candidate_attempt_id = p_candidate_attempt_id
	_candidate_frame = _copy_frame(p_candidate_frame)
	_previous_frame = _copy_frame(p_previous_frame)
	_pressed_buttons = p_pressed_buttons.duplicate()
	_released_buttons = p_released_buttons.duplicate()
	_commands = DetachedCommandBundle.new(p_commands.records_in_order())
	_pre_clock_period = p_pre_clock_period
	_pre_clock_elapsed_ticks = p_pre_clock_elapsed_ticks
	_pre_clock_period_count = p_pre_clock_period_count
	_pre_clock_period_ticks = p_pre_clock_period_ticks
	_pre_clock_game_seconds_per_period = p_pre_clock_game_seconds_per_period
	_pre_flow_state = p_pre_flow_state
	_pre_flow_ticks_in_state = p_pre_flow_ticks_in_state
	_pre_pending_triggers = p_pre_pending_triggers.duplicate()
	_clock_delta_numerator = p_clock_delta_numerator
	_clock_delta_denominator = p_clock_delta_denominator


var candidate_tick: int:
	get:
		return _candidate_tick
var candidate_attempt_id: int:
	get:
		return _candidate_attempt_id
var candidate_frame: InputFrame:
	get:
		return _copy_frame(_candidate_frame)
var previous_frame: InputFrame:
	get:
		return _copy_frame(_previous_frame)
var pressed_buttons: PackedInt64Array:
	get:
		return _pressed_buttons.duplicate()
var released_buttons: PackedInt64Array:
	get:
		return _released_buttons.duplicate()
var commands: DetachedCommandBundle:
	get:
		return DetachedCommandBundle.new(_commands.records_in_order())
var pre_clock_period: int:
	get:
		return _pre_clock_period
var pre_clock_elapsed_ticks: int:
	get:
		return _pre_clock_elapsed_ticks
var pre_clock_period_count: int:
	get:
		return _pre_clock_period_count
var pre_clock_period_ticks: int:
	get:
		return _pre_clock_period_ticks
var pre_clock_game_seconds_per_period: int:
	get:
		return _pre_clock_game_seconds_per_period
var pre_flow_state: StringName:
	get:
		return _pre_flow_state
var pre_flow_ticks_in_state: int:
	get:
		return _pre_flow_ticks_in_state
var pre_pending_triggers: Array[StringName]:
	get:
		return _pre_pending_triggers.duplicate()
var clock_delta_numerator: int:
	get:
		return _clock_delta_numerator
var clock_delta_denominator: int:
	get:
		return _clock_delta_denominator


static func _copy_frame(frame: InputFrame) -> InputFrame:
	if frame == null:
		return null
	var copy: InputFrame = InputFrame.new(frame.slot_count, frame.axes_per_slot)
	copy.copy_from(frame)
	return copy
