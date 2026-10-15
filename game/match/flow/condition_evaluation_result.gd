class_name ConditionEvaluationResult
extends RefCounted
## Checked condition evaluation value.

var ok: bool:
	get:
		return _ok
var value: bool:
	get:
		return _value
var error: Error:
	get:
		return _error

var _ok: bool
var _value: bool
var _error: Error


func _init(p_ok: bool, p_value: bool, p_error: Error) -> void:
	_ok = p_ok
	_value = p_value
	_error = p_error
