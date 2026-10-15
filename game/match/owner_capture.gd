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
		var dependency: SimDependencyCheckpoint = value
		if not dependency._has_detached_state:
			return {"ok": false, "value": null}
		var copied_state: Dictionary = _try_copy_value(dependency.state)
		if not copied_state.ok:
			return {"ok": false, "value": null}
		return {
			"ok": true,
			"value":
			SimDependencyCheckpoint.new(
				dependency.stable_provider_id, dependency.provider_version, copied_state.value
			)
		}
	if value is Dictionary:
		var source_dictionary: Dictionary = value
		var copied: Dictionary = {}
		for key: Variant in source_dictionary:
			var copied_key: Dictionary = _try_copy_value(key)
			var copied_value: Dictionary = _try_copy_value(source_dictionary[key])
			if not copied_key.ok or not copied_value.ok:
				return {"ok": false, "value": null}
			copied[copied_key.value] = copied_value.value
		return {"ok": true, "value": copied}
	if value is Array:
		var source_array: Array = value
		var copied_array: Array = []
		for item: Variant in source_array:
			var copied_item: Dictionary = _try_copy_value(item)
			if not copied_item.ok:
				return {"ok": false, "value": null}
			copied_array.append(copied_item.value)
		return {"ok": true, "value": copied_array}
	if _is_packed_array(value):
		var packed_copy: Variant = _copy_packed_array(value)
		return {"ok": true, "value": packed_copy}
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


static func _copy_packed_array(value: Variant) -> Variant:
	if value is PackedByteArray:
		var byte_array: PackedByteArray = value
		return byte_array.duplicate()
	if value is PackedInt32Array:
		var int32_array: PackedInt32Array = value
		return int32_array.duplicate()
	if value is PackedInt64Array:
		var int64_array: PackedInt64Array = value
		return int64_array.duplicate()
	if value is PackedFloat32Array:
		var float32_array: PackedFloat32Array = value
		return float32_array.duplicate()
	if value is PackedFloat64Array:
		var float64_array: PackedFloat64Array = value
		return float64_array.duplicate()
	if value is PackedStringArray:
		var string_array: PackedStringArray = value
		return string_array.duplicate()
	if value is PackedVector2Array:
		var vector2_array: PackedVector2Array = value
		return vector2_array.duplicate()
	if value is PackedVector3Array:
		var vector3_array: PackedVector3Array = value
		return vector3_array.duplicate()
	if value is PackedColorArray:
		var color_array: PackedColorArray = value
		return color_array.duplicate()
	if value is PackedVector4Array:
		var vector4_array: PackedVector4Array = value
		return vector4_array.duplicate()
	return null


static func _is_empty_checkpoint_value(value: Variant) -> bool:
	if value == null:
		return true
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return dictionary_value.is_empty()
	if value is Array:
		var array_value: Array = value
		return array_value.is_empty()
	if _is_packed_array(value):
		return _packed_array_is_empty(value)
	if value is String or value is StringName:
		return str(value).is_empty()
	return false


static func _packed_array_is_empty(value: Variant) -> bool:
	if value is PackedByteArray:
		var byte_array: PackedByteArray = value
		return byte_array.is_empty()
	if value is PackedInt32Array:
		var int32_array: PackedInt32Array = value
		return int32_array.is_empty()
	if value is PackedInt64Array:
		var int64_array: PackedInt64Array = value
		return int64_array.is_empty()
	if value is PackedFloat32Array:
		var float32_array: PackedFloat32Array = value
		return float32_array.is_empty()
	if value is PackedFloat64Array:
		var float64_array: PackedFloat64Array = value
		return float64_array.is_empty()
	if value is PackedStringArray:
		var string_array: PackedStringArray = value
		return string_array.is_empty()
	if value is PackedVector2Array:
		var vector2_array: PackedVector2Array = value
		return vector2_array.is_empty()
	if value is PackedVector3Array:
		var vector3_array: PackedVector3Array = value
		return vector3_array.is_empty()
	if value is PackedColorArray:
		var color_array: PackedColorArray = value
		return color_array.is_empty()
	if value is PackedVector4Array:
		var vector4_array: PackedVector4Array = value
		return vector4_array.is_empty()
	return false


func _init(p_payload: Variant) -> void:
	var result: Dictionary = _try_copy_value(p_payload)
	_has_detached_payload = result.ok
	_payload = result.value if result.ok else null
