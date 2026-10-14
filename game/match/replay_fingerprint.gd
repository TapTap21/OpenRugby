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
		return _resource_snapshot(value)
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
	if value is RefCounted and value.has_method("snapshot"):
		return {"type": value.get_class(), "snapshot": _normalize(value.call("snapshot"))}
	return value


static func _key_less(left: Variant, right: Variant) -> bool:
	return str(left) < str(right)


static func _resource_snapshot(resource: Resource) -> Dictionary:
	var script: Script = resource.get_script() as Script
	var names: Array[String] = []
	for property: Dictionary in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(String(property["name"]))
	names.sort()
	var properties: Dictionary = {}
	for name: String in names:
		properties[name] = _normalize(resource.get(name))
	return {
		"resource": script.resource_path if script != null else resource.get_class(),
		"properties": properties
	}
