class_name CheckpointResult
extends RefCounted
## Checked opaque state snapshot used for simulation rollback.

var ok: bool:
	get:
		return _ok
var error: Error:
	get:
		return _error
var value: Variant:
	get:
		return OwnerCapture._copy_value(_value)

var _ok: bool
var _value: Variant
var _error: Error
var _has_detached_value: bool = false


func _init(p_ok: bool, p_value: Variant, p_error: Error) -> void:
	_ok = p_ok
	var copy_result: Dictionary = OwnerCapture._try_copy_value(p_value)
	_has_detached_value = copy_result.ok
	_value = copy_result.value if copy_result.ok else null
	_error = p_error
