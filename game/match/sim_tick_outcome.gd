class_name SimTickOutcome
extends RefCounted
## Immutable generic result of a successfully staged simulation tick.

# gdlint: disable=class-definitions-order,function-arguments-number

var _candidate_tick: int
var _pre_clock_period: int
var _pre_clock_elapsed_ticks: int
var _post_clock_period: int
var _post_clock_elapsed_ticks: int
var _pre_flow_state: StringName
var _pre_flow_ticks_in_state: int
var _post_flow_state: StringName
var _post_flow_ticks_in_state: int
var _selected_transition_to: StringName
var _selected_transition_trigger: StringName
var _period_effect: int
var _clock_delta_numerator: int
var _clock_delta_denominator: int


func _init(
	p_candidate_tick: int,
	p_pre_clock_period: int,
	p_pre_clock_elapsed_ticks: int,
	p_post_clock_period: int,
	p_post_clock_elapsed_ticks: int,
	p_pre_flow_state: StringName,
	p_pre_flow_ticks_in_state: int,
	p_post_flow_state: StringName,
	p_post_flow_ticks_in_state: int,
	p_selected_transition_to: StringName,
	p_selected_transition_trigger: StringName,
	p_period_effect: int,
	p_clock_delta_numerator: int,
	p_clock_delta_denominator: int
) -> void:
	_candidate_tick = p_candidate_tick
	_pre_clock_period = p_pre_clock_period
	_pre_clock_elapsed_ticks = p_pre_clock_elapsed_ticks
	_post_clock_period = p_post_clock_period
	_post_clock_elapsed_ticks = p_post_clock_elapsed_ticks
	_pre_flow_state = p_pre_flow_state
	_pre_flow_ticks_in_state = p_pre_flow_ticks_in_state
	_post_flow_state = p_post_flow_state
	_post_flow_ticks_in_state = p_post_flow_ticks_in_state
	_selected_transition_to = p_selected_transition_to
	_selected_transition_trigger = p_selected_transition_trigger
	_period_effect = p_period_effect
	_clock_delta_numerator = p_clock_delta_numerator
	_clock_delta_denominator = p_clock_delta_denominator


var candidate_tick: int:
	get:
		return _candidate_tick
var pre_clock_period: int:
	get:
		return _pre_clock_period
var pre_clock_elapsed_ticks: int:
	get:
		return _pre_clock_elapsed_ticks
var post_clock_period: int:
	get:
		return _post_clock_period
var post_clock_elapsed_ticks: int:
	get:
		return _post_clock_elapsed_ticks
var pre_flow_state: StringName:
	get:
		return _pre_flow_state
var pre_flow_ticks_in_state: int:
	get:
		return _pre_flow_ticks_in_state
var post_flow_state: StringName:
	get:
		return _post_flow_state
var post_flow_ticks_in_state: int:
	get:
		return _post_flow_ticks_in_state
var selected_transition_to: StringName:
	get:
		return _selected_transition_to
var selected_transition_trigger: StringName:
	get:
		return _selected_transition_trigger
var period_effect: int:
	get:
		return _period_effect
var clock_delta_numerator: int:
	get:
		return _clock_delta_numerator
var clock_delta_denominator: int:
	get:
		return _clock_delta_denominator
