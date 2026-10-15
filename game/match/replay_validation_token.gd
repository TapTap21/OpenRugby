class_name ReplayValidationToken
extends RefCounted
## Opaque replay validation capability; ordinary public construction is inert.

var _active: bool = false
var _authority: ReplayValidationAuthority
var _prepared_tick: PreparedTick
var _source_row: ReplaySourceRow
var _readback_identity: RefCounted
var _expected_output_identity: RefCounted
var _generated_output_identity: RefCounted


func _init() -> void:
	pass
