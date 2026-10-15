class_name AppendPrepareResult
extends RefCounted
## Immutable result of preparing a complete input-log row.

var ok: bool:
	get:
		return _ok
var token: PreparedAppendToken:
	get:
		return _token
var error: Error:
	get:
		return _error

var _ok: bool
var _token: PreparedAppendToken
var _error: Error


func _init(p_ok: bool, p_token: PreparedAppendToken, p_error: Error) -> void:
	if p_ok and p_token != null and p_error == OK:
		_ok = true
		_token = p_token
		_error = OK
	else:
		_ok = false
		_token = null
		_error = p_error if p_error != OK else ERR_INVALID_PARAMETER


## Creates a success result for the exact non-null reservation token.
static func prepared(token: PreparedAppendToken) -> AppendPrepareResult:
	if token == null:
		return failed(ERR_INVALID_PARAMETER)
	return AppendPrepareResult.new(true, token, OK)


## Creates a failure result with no token and a non-OK error.
static func failed(error: Error) -> AppendPrepareResult:
	var failure: Error = error if error != OK else ERR_INVALID_PARAMETER
	return AppendPrepareResult.new(false, null, failure)
