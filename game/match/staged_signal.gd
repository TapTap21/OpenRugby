class_name StagedSignal
extends RefCounted
## One typed notification deferred until the tick is finalized.

enum Kind { STATE_CHANGED, PERIOD_STARTED, PERIOD_ENDED, FINISHED }

var kind: Kind:
	get:
		return _kind
var from_state: StringName:
	get:
		return _from_state
var to_state: StringName:
	get:
		return _to_state
var period: int:
	get:
		return _period

var _kind: Kind
var _from_state: StringName
var _to_state: StringName
var _period: int


func _init(
	p_kind: Kind, p_from_state: StringName = &"", p_to_state: StringName = &"", p_period: int = 0
) -> void:
	_kind = p_kind
	_from_state = p_from_state
	_to_state = p_to_state
	_period = p_period
