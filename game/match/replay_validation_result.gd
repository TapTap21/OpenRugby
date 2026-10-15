class_name ReplayValidationResult
extends RefCounted
## Immutable result of validating one replay row.

var ok: bool:
	get:
		return _ok
var token: ReplayValidationToken:
	get:
		return _token
var error: Error:
	get:
		return _error

var _ok: bool
var _token: ReplayValidationToken
var _error: Error


## Creates a result; malformed combinations are normalized to a safe failure.
func _init(p_ok: bool, p_token: ReplayValidationToken, p_error: Error) -> void:
	if p_ok and p_token != null and p_error == OK:
		_ok = true
		_token = p_token
		_error = OK
	else:
		_ok = false
		_token = null
		_error = p_error if p_error != OK else ERR_INVALID_PARAMETER
