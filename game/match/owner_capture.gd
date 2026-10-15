class_name OwnerCapture
extends RefCounted
## Immutable opaque owner-defined value captured before system ticks.

var payload: Variant:
	get:
		var result: Dictionary = _try_copy_value(_payload)
		return result.value if result.ok else null

var _payload: Variant
var _has_detached_payload: bool = false


static func _copy_value(value: Variant) -> Variant:
	var result: Dictionary = _try_copy_value(value)
	return result.value if result.ok else null


static func _copy_contract_value(value: Variant) -> Variant:
	var result: Dictionary = _try_copy_value(value)
	return result.value if result.ok else null


static func _try_copy_value(value: Variant) -> Dictionary:
	if value is SimDependencyCheckpoint:
		if not value._has_detached_state:
			return {"ok": false, "value": null}
		var copied_state: Dictionary = _try_copy_value(value.state)
		if not copied_state.ok:
			return {"ok": false, "value": null}
		return {
			"ok": true,
			"value":
			SimDependencyCheckpoint.new(
				value.stable_provider_id, value.provider_version, copied_state.value
			)
		}
	if value is Dictionary:
		var copied: Dictionary = {}
		for key: Variant in value:
			var copied_key: Dictionary = _try_copy_value(key)
			var copied_value: Dictionary = _try_copy_value(value[key])
			if not copied_key.ok or not copied_value.ok:
				return {"ok": false, "value": null}
			copied[copied_key.value] = copied_value.value
		return {"ok": true, "value": copied}
	if value is Array:
		var copied_array: Array = []
		for item: Variant in value:
			var copied_item: Dictionary = _try_copy_value(item)
			if not copied_item.ok:
				return {"ok": false, "value": null}
			copied_array.append(copied_item.value)
		return {"ok": true, "value": copied_array}
	if _is_packed_array(value):
		return {"ok": true, "value": value.duplicate()}
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return {"ok": false, "value": null}
	return {"ok": true, "value": value}


static func _is_packed_array(value: Variant) -> bool:
	return (
		typeof(value)
		in [
			TYPE_PACKED_BYTE_ARRAY,
			TYPE_PACKED_INT32_ARRAY,
			TYPE_PACKED_INT64_ARRAY,
			TYPE_PACKED_FLOAT32_ARRAY,
			TYPE_PACKED_FLOAT64_ARRAY,
			TYPE_PACKED_STRING_ARRAY,
			TYPE_PACKED_VECTOR2_ARRAY,
			TYPE_PACKED_VECTOR3_ARRAY,
			TYPE_PACKED_COLOR_ARRAY,
			TYPE_PACKED_VECTOR4_ARRAY
		]
	)


static func _is_empty_checkpoint_value(value: Variant) -> bool:
	if value == null:
		return true
	if value is Dictionary or value is Array or _is_packed_array(value):
		return value.is_empty()
	if value is String or value is StringName:
		return value.is_empty()
	return false


func _init(p_payload: Variant) -> void:
	var result: Dictionary = _try_copy_value(p_payload)
	_has_detached_payload = result.ok
	_payload = result.value if result.ok else null
