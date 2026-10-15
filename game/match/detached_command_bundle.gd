class_name DetachedCommandBundle
extends RefCounted
## Immutable ordered copies of concrete command records owned by another subsystem.

var _records: Array[RefCounted] = []
var _valid: bool = true


func _init(records: Array[RefCounted] = []) -> void:
	for record: RefCounted in records:
		var copy: RefCounted = _copy_record(record)
		if copy == null:
			_valid = false
			_records.clear()
			return
		_records.append(copy)


## Returns independent concrete record copies in submission order.
func records_in_order() -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for record: RefCounted in _records:
		var copy: RefCounted = _copy_record(record)
		if copy == null:
			return []
		result.append(copy)
	return result


## Number of records in this bundle.
func size() -> int:
	return _records.size()


## True when each stored record can be copied as its original concrete type.
func is_valid() -> bool:
	return _valid and records_in_order().size() == _records.size()


static func _copy_record(record: RefCounted) -> RefCounted:
	if record == null:
		return null
	for method: Dictionary in record.get_method_list():
		if method.get("name", "") == "detached_copy":
			var copied: Variant = record.call("detached_copy")
			if copied is RefCounted:
				var copied_record: RefCounted = copied
				if copied_record != record and copied_record.get_script() == record.get_script():
					return copied_record
			return null
	return null
