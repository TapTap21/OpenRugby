class_name SimDependencyCheckpoint
extends RefCounted
## Opaque checkpoint for a provider owned by a registered participant.

var stable_provider_id: String:
	get:
		return _stable_provider_id
var provider_version: String:
	get:
		return _provider_version
var state: Variant:
	get:
		return OwnerCapture._copy_value(_state)

var _stable_provider_id: String
var _provider_version: String
var _state: Variant
var _has_detached_state: bool = false


func _init(p_stable_provider_id: String, p_provider_version: String, p_state: Variant) -> void:
	_stable_provider_id = p_stable_provider_id
	_provider_version = p_provider_version
	var result: Dictionary = OwnerCapture._try_copy_value(p_state)
	_has_detached_state = result.ok
	_state = result.value if result.ok else null
