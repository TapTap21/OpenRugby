class_name TransitionEvaluationResult
extends RefCounted
## Checked transition selection result; null transition means a successful no-match.

var ok: bool:
	get:
		return _ok
var transition: MatchTransitionDef:
	get:
		return _transition
var error: Error:
	get:
		return _error

var _ok: bool
var _transition: MatchTransitionDef
var _error: Error


func _init(p_ok: bool, p_transition: MatchTransitionDef, p_error: Error) -> void:
	_ok = p_ok
	_transition = p_transition
	_error = p_error
