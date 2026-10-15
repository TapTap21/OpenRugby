class_name ReplayFingerprint
extends RefCounted
## Stable hashing of match setup data, with Resources reduced to sorted properties.


## Returns a lowercase SHA-256 fingerprint for deterministic match setup data.
static func hash(value: Variant) -> String:
	var normalized: Variant = _normalize(value)
	var context: HashingContext = HashingContext.new()
	var error: Error = context.start(HashingContext.HASH_SHA256)
	assert(error == OK)
	error = context.update(var_to_bytes(normalized))
	assert(error == OK)
	return context.finish().hex_encode()


static func _normalize(value: Variant) -> Variant:
	if value is Resource:
		var resource: Resource = value
		return _resource_snapshot(resource)
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array[Variant] = []
		for key: Variant in source:
			keys.append(key)
		keys.sort_custom(_key_less)
		var result: Dictionary = {}
		for key: Variant in keys:
			result[str(key)] = _normalize(source[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_normalize(item))
		return result
	if value is RefCounted:
		var ref_counted: RefCounted = value
		if ref_counted.has_method("snapshot"):
			return {
				"type": ref_counted.get_class(),
				"snapshot": _normalize(ref_counted.call("snapshot"))
			}
	return value


static func _key_less(left: Variant, right: Variant) -> bool:
	return str(left) < str(right)


static func _resource_snapshot(resource: Resource) -> Dictionary:
	var raw_script: Variant = resource.get_script()
	var script_path: String = ""
	var has_script: bool = false
	if raw_script is Script:
		var script: Script = raw_script
		script_path = script.resource_path
		has_script = true
	var names: Array[String] = []
	for property: Dictionary in resource.get_property_list():
		var raw_usage: Variant = property.get("usage", 0)
		var raw_name: Variant = property.get("name", "")
		if not raw_usage is int:
			continue
		var usage: int = raw_usage
		var property_name: String
		if raw_name is String:
			property_name = raw_name
		elif raw_name is StringName:
			var property_name_value: StringName = raw_name
			property_name = String(property_name_value)
		else:
			continue
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property_name)
	names.sort()
	var properties: Dictionary = {}
	for name: String in names:
		properties[name] = _normalize(resource.get(name))
	return {
		"resource": script_path if has_script else resource.get_class(), "properties": properties
	}
