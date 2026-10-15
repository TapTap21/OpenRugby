class_name AppendPrepareResult
extends RefCounted
## Immutable result of preparing a complete input-log row.

var ok: bool
var token: PreparedAppendToken
var error: Error


func _init(p_ok: bool, p_token: PreparedAppendToken, p_error: Error) -> void:
	ok = p_ok
	token = p_token
	error = p_error
