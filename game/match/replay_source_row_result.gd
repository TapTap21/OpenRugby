class_name ReplaySourceRowResult
extends RefCounted
## Immutable result for reading a replay row from its source log.

var ok: bool
var row: ReplaySourceRow
var error: Error


func _init(p_ok: bool, p_row: ReplaySourceRow, p_error: Error) -> void:
	ok = p_ok
	row = p_row
	error = p_error
