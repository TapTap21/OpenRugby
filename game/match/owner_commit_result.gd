class_name OwnerCommitResult
extends RefCounted
## Checked result from a tick owner's post-update commit.

var ok: bool:
	get:
		return _ok
var error: Error:
	get:
		return _error

var _ok: bool
var _error: Error


func _init(p_ok: bool, p_error: Error) -> void:
	_ok = p_ok
	_error = p_error
