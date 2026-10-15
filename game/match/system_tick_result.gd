class_name SystemTickResult
extends RefCounted
## Checked result from a system tick.

var ok: bool:
	get:
		return _ok
var error: Error:
	get:
		return _error
var outputs: Array[RefCounted]:
	get:
		return _copy_records(_outputs)

var _ok: bool
var _error: Error
var _outputs: Array[RefCounted]


func _init(p_ok: bool, p_error: Error, p_outputs: Array[RefCounted] = []) -> void:
	_ok = p_ok
	_error = p_error
	_outputs = _copy_records(p_outputs)
	if _outputs.size() != p_outputs.size():
		_ok = false
		_error = ERR_INVALID_DATA


static func _copy_records(records: Array[RefCounted]) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for record: RefCounted in records:
		var copied: RefCounted = DetachedCommandBundle._copy_record(record)
		if copied == null:
			return []
		result.append(copied)
	return result
