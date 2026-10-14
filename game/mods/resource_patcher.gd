class_name ResourcePatcher
extends RefCounted
## Layer 1 engine: applies JSON field patches to Resources in place, and fills Resources from
## extracted JSON data.
##
## Field paths are [code]/[/code]-separated; each segment is an exported property of a
## [Resource], a key of a [Dictionary] or an existing index of an [Array]. Scalars replace,
## dictionaries merge by key, arrays replace unless [code]$append[/code] is used, and nested
## resources merge field by field. Before the first change to an [code](object, property)[/code]
## the old value is stored, so [method revert] restores the base exactly. Value rules are in
## [code]docs/specs/S1-modloader.md[/code] section 7.

const BASE_ID: StringName = &"base"
## Properties a patch may never touch (a data mod must not be able to attach a script).
const _BLOCKED_PROPERTIES: Array[StringName] = [&"script", &"resource_path"]
const _DICTIONARY_OPS: PackedStringArray = ["$replace"]
const _ARRAY_OPS: PackedStringArray = ["$append", "$replace"]

var _ledger: OverrideLedger = null
var _load_resource: Callable = Callable()
var _snapshots: Array[_Snapshot] = []
var _snapshot_keys: Dictionary[String, bool] = {}
## Exported (storage) properties per class or script: key -> {name: property info}.
var _property_cache: Dictionary[String, Dictionary] = {}


func _init(p_ledger: OverrideLedger = null, p_load_resource: Callable = Callable()) -> void:
	_ledger = p_ledger
	_load_resource = p_load_resource


## Applies [param fields] (field path -> JSON value) to [param target] in place, recording every
## applied leaf in the ledger as written by [param mod_id]. Returns the problems found; a bad
## field never stops the other fields.
func apply(
	target: Resource, target_path: String, fields: Dictionary, mod_id: StringName
) -> Array[ModIssue]:
	var context: _Context = _Context.new(target_path, mod_id, _ledger)
	if target == null:
		context.fail(&"patch_target_missing", "", "the target resource is null")
		return context.issues
	_merge_object(target, fields, "", context)
	return context.issues


## Restores every value changed since construction (or the last revert), in reverse order.
func revert() -> void:
	for index: int in range(_snapshots.size() - 1, -1, -1):
		_snapshots[index].restore()
	_snapshots.clear()
	_snapshot_keys.clear()


## Fills [param resource] from the JSON object [param data] with the patch rules (no ledger, no
## revert, mod id [code]base[/code]); null nested resources are created. This is the
## JSON-to-Resource loader for extracted data.
static func fill(resource: Resource, data: Dictionary) -> Array[ModIssue]:
	var patcher: ResourcePatcher = ResourcePatcher.new()
	var path: String = resource.resource_path if resource != null else ""
	var context: _Context = _Context.new(path, BASE_ID, null)
	context.track = false
	context.fill = true
	if resource == null:
		context.fail(&"patch_target_missing", "", "the resource to fill is null")
		return context.issues
	patcher._merge_object(resource, data, "", context)
	return context.issues


func _merge_object(target: Object, data: Dictionary, base_path: String, context: _Context) -> void:
	for key: Variant in data.keys():
		var relative: String = str(key)
		var path: String = relative if base_path.is_empty() else base_path + "/" + relative
		var slot: _Slot = _resolve(target, relative, path, context)
		if slot != null:
			_assign(slot, data[key], path, context)


## Walks [param relative] from [param root] to the slot it names, or reports
## [code]patch_unknown_field[/code] and returns null.
func _resolve(root: Object, relative: String, path: String, context: _Context) -> _Slot:
	var segments: PackedStringArray = relative.split("/")
	var container: Variant = root
	var owner: Object = root
	var owner_property: StringName = &""
	for index: int in segments.size():
		var last: bool = index == segments.size() - 1
		var slot: _Slot = _slot_in(container, segments[index], last)
		if slot == null:
			context.fail(&"patch_unknown_field", path, "no field '%s'" % segments[index])
			return null
		if slot.object != null:
			owner = slot.object
			owner_property = slot.key
		slot.owner = owner
		slot.owner_property = owner_property
		if last:
			return slot
		container = slot.get_value()
		if not (container is Resource or container is Dictionary or container is Array):
			context.fail(&"patch_unknown_field", path, "'%s' cannot be entered" % segments[index])
			return null
	return null


func _slot_in(container: Variant, segment: String, last: bool) -> _Slot:
	if segment.is_empty():
		return null
	if container is Object:
		var object: Object = container
		return _object_slot(object, segment)
	if container is Dictionary:
		var dictionary: Dictionary = container
		var converted: Array = PatchValues.convert_key(segment, dictionary)
		if not converted[0] or (not last and not dictionary.has(converted[1])):
			return null
		return _Slot.on_dictionary(dictionary, converted[1])
	if container is Array:
		var array: Array = container
		return _array_slot(array, segment)
	return null


func _object_slot(object: Object, segment: String) -> _Slot:
	var info: Dictionary = _property_info(object, segment)
	if info.is_empty():
		return null
	return _Slot.on_object(object, StringName(segment), PatchValues.from_property(info))


static func _array_slot(array: Array, segment: String) -> _Slot:
	if not segment.is_valid_int() or segment.begins_with("-") or segment.begins_with("+"):
		return null
	var index: int = segment.to_int()
	if index >= array.size():
		return null
	return _Slot.on_array(array, index)


func _assign(slot: _Slot, json: Variant, path: String, context: _Context) -> void:
	var current: Variant = slot.get_value()
	var type: int = slot.info.type
	if type == TYPE_NIL:
		type = _variant_target_type(current, json)
	match type:
		TYPE_NIL:
			_write(slot, _plain(json), path, context)
		TYPE_OBJECT:
			_assign_object(slot, current, json, path, context)
		TYPE_DICTIONARY:
			_assign_dictionary(slot, current, json, path, context)
		TYPE_ARRAY:
			_assign_array(slot, current, json, path, context)
		_:
			if PatchValues.packed_element_type(type) != TYPE_NIL and json is Dictionary:
				var data: Dictionary = json
				_assign_packed(slot, current, data, path, context)
				return
			var converted: Array = _convert_new(json, slot.info, path, context)
			if converted[0]:
				_write(slot, converted[1], path, context)


## For an untyped slot: merge into existing containers and resources, otherwise replace.
static func _variant_target_type(current: Variant, json: Variant) -> int:
	if current is Resource and json is Dictionary:
		return TYPE_OBJECT
	if current is Dictionary and json is Dictionary:
		return TYPE_DICTIONARY
	if current is Array and (json is Array or json is Dictionary):
		return TYPE_ARRAY
	return TYPE_NIL


func _assign_object(
	slot: _Slot, current: Variant, json: Variant, path: String, context: _Context
) -> void:
	if json is Dictionary:
		var data: Dictionary = json
		if current is Resource:
			var nested: Resource = current
			_merge_object(nested, data, path, context)
			return
		if current == null and context.fill:
			var created: Resource = PatchValues.instantiate(slot.info)
			if created != null:
				_merge_object(created, data, path, context.quiet())
				_write(slot, created, path, context)
				return
		context.fail(&"patch_type_mismatch", path, "there is no resource to merge into")
		return
	var converted: Array = _convert_new(json, slot.info, path, context)
	if converted[0]:
		_write(slot, converted[1], path, context)


func _assign_dictionary(
	slot: _Slot, current: Variant, json: Variant, path: String, context: _Context
) -> void:
	if not json is Dictionary:
		context.fail(&"patch_type_mismatch", path, "expected a JSON object")
		return
	var data: Dictionary = json
	var op: String = _op_name(data, _DICTIONARY_OPS, path, context)
	if op == "!":
		return
	if not current is Dictionary:
		var payload: Variant = data[op] if op != "" else data
		_write(slot, _plain(payload), path, context)
		return
	var dictionary: Dictionary = current
	if op == "$replace":
		_replace_dictionary(slot, dictionary, data[op], path, context)
		return
	for key: Variant in data.keys():
		var key_path: String = path + "/" + str(key)
		var converted: Array = PatchValues.convert_key(str(key), dictionary)
		if not converted[0]:
			context.fail(&"patch_type_mismatch", key_path, "the key does not fit the dictionary")
			continue
		var value: Variant = data[key]
		if value == null:
			if dictionary.has(converted[1]):
				_touch(slot, context)
				if dictionary.erase(converted[1]):
					context.record(key_path)
			continue
		var child: _Slot = _Slot.on_dictionary(dictionary, converted[1])
		child.owner = slot.owner
		child.owner_property = slot.owner_property
		_assign(child, value, key_path, context)


func _replace_dictionary(
	slot: _Slot, dictionary: Dictionary, payload: Variant, path: String, context: _Context
) -> void:
	if not payload is Dictionary:
		context.fail(&"patch_type_mismatch", path, "$replace needs a JSON object")
		return
	var entries: Dictionary = payload
	var replacement: Dictionary = dictionary.duplicate()
	replacement.clear()
	var value_info: PatchValues.TypeInfo = PatchValues.dictionary_value(dictionary)
	for key: Variant in entries.keys():
		var key_path: String = path + "/" + str(key)
		var key_converted: Array = PatchValues.convert_key(str(key), dictionary)
		if not key_converted[0]:
			context.fail(&"patch_type_mismatch", key_path, "the key does not fit the dictionary")
			return
		var value_converted: Array = _convert_new(entries[key], value_info, key_path, context)
		if not value_converted[0]:
			return
		replacement[key_converted[1]] = value_converted[1]
	_touch(slot, context)
	dictionary.clear()
	dictionary.merge(replacement)
	context.record(path)


func _assign_array(
	slot: _Slot, current: Variant, json: Variant, path: String, context: _Context
) -> void:
	var items: Array = []
	var append: bool = false
	if json is Array:
		items = json
	elif json is Dictionary:
		var data: Dictionary = json
		var op: String = _op_name(data, _ARRAY_OPS, path, context)
		if op == "!":
			return
		if op == "" or not data[op] is Array:
			context.fail(&"patch_type_mismatch", path, "expected an array, $append or $replace")
			return
		items = data[op]
		append = op == "$append"
	else:
		context.fail(&"patch_type_mismatch", path, "expected a JSON array")
		return
	if not current is Array:
		_write(slot, _plain(items), path, context)
		return
	var array: Array = current
	var result: Array = array.duplicate()
	if not append:
		result.clear()
	var element: PatchValues.TypeInfo = PatchValues.array_element(array)
	for item: Variant in items:
		var converted: Array = _convert_new(item, element, "%s/%d" % [path, result.size()], context)
		if not converted[0]:
			return
		result.append(converted[1])
	_touch(slot, context)
	array.assign(result)
	context.record(path)


## Applies [code]$append[/code] / [code]$replace[/code] to a packed array (packed arrays are
## values, so the result is written back).
func _assign_packed(
	slot: _Slot, current: Variant, json: Dictionary, path: String, context: _Context
) -> void:
	var op: String = _op_name(json, _ARRAY_OPS, path, context)
	if op == "!":
		return
	if op == "" or not json[op] is Array:
		context.fail(&"patch_type_mismatch", path, "expected an array, $append or $replace")
		return
	var converted: Array = _convert_new(json[op], slot.info, path, context)
	if not converted[0]:
		return
	if op == "$append":
		var combined: Array = type_convert(current, TYPE_ARRAY)
		var added: Array = type_convert(converted[1], TYPE_ARRAY)
		combined.append_array(added)
		converted[1] = type_convert(combined, slot.info.type)
	_write(slot, converted[1], path, context)


## Converts [param json] to a new value of the type [param info] describes, reporting
## [code]patch_type_mismatch[/code] at [param path] on failure.
func _convert_new(
	json: Variant, info: PatchValues.TypeInfo, path: String, context: _Context
) -> Array:
	var result: Array = [false, null]
	match info.type:
		TYPE_NIL:
			result = [true, _plain(json)]
		TYPE_OBJECT:
			result = _convert_object(json, info, path, context)
		TYPE_DICTIONARY:
			if json is Dictionary:
				var data: Dictionary = json
				if _op_name(data, PackedStringArray(), path, null) == "":
					result = [true, _plain(json)]
		TYPE_ARRAY:
			if json is Array:
				result = [true, _plain(json)]
		_:
			if PatchValues.packed_element_type(info.type) != TYPE_NIL:
				result = _convert_packed(json, info.type)
			else:
				result = PatchValues.convert_scalar(json, info)
	if not result[0] and not (info.type == TYPE_OBJECT and json is Dictionary):
		context.fail(&"patch_type_mismatch", path, _mismatch_text(json, info))
	return result


func _convert_object(
	json: Variant, info: PatchValues.TypeInfo, path: String, context: _Context
) -> Array:
	if json == null:
		return [true, null]
	if json is String:
		var loaded: Resource = _load(str(json))
		if loaded != null and PatchValues.is_instance(loaded, info):
			return [true, loaded]
		return [false, null]
	if json is Dictionary:
		var created: Resource = PatchValues.instantiate(info)
		if created == null:
			context.fail(&"patch_type_mismatch", path, "cannot create a %s" % _type_name(info))
			return [false, null]
		var data: Dictionary = json
		_merge_object(created, data, path, context.quiet())
		return [true, created]
	return [false, null]


## Converts a plain JSON array to a packed array of [param type].
static func _convert_packed(json: Variant, type: int) -> Array:
	if not json is Array:
		return [false, null]
	var values: Array = json
	var element: PatchValues.TypeInfo = PatchValues.builtin(PatchValues.packed_element_type(type))
	var items: Array = []
	for value: Variant in values:
		var converted: Array = PatchValues.convert_scalar(value, element)
		if not converted[0]:
			return [false, null]
		items.append(converted[1])
	return [true, type_convert(items, type)]


## Returns the single [code]$[/code] operation of [param data], "" when it has none, or "!" after
## reporting [code]patch_unknown_op[/code]. A null [param context] only inspects.
static func _op_name(
	data: Dictionary, allowed: PackedStringArray, path: String, context: _Context
) -> String:
	var op: String = ""
	for key: Variant in data.keys():
		if str(key).begins_with("$"):
			op = str(key)
	if op.is_empty():
		return ""
	if data.size() != 1 or not allowed.has(op):
		if context != null:
			context.fail(&"patch_unknown_op", path, "unknown or mixed operation '%s'" % op)
		return "!"
	return op


func _write(slot: _Slot, value: Variant, path: String, context: _Context) -> void:
	_touch(slot, context)
	slot.set_value(value)
	context.record(path)


## Stores the old value of the slot's owning (object, property) before its first change.
func _touch(slot: _Slot, context: _Context) -> void:
	if not context.track or slot.owner == null:
		return
	var key: String = "%d:%s" % [slot.owner.get_instance_id(), slot.owner_property]
	if _snapshot_keys.has(key):
		return
	_snapshot_keys[key] = true
	_snapshots.append(_Snapshot.new(slot.owner, slot.owner_property))


func _load(path: String) -> Resource:
	if _load_resource.is_valid():
		var loaded: Resource = _load_resource.call(path)
		return loaded
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)


## Returns the property info of the exported (storage) property [param property_name] of
## [param object], or an empty dictionary.
func _property_info(object: Object, property_name: String) -> Dictionary:
	if _BLOCKED_PROPERTIES.has(StringName(property_name)):
		return {}
	var script: Script = object.get_script()
	var cache_key: String = object.get_class()
	if script != null:
		cache_key = "script:%d" % script.get_instance_id()
	if not _property_cache.has(cache_key):
		var properties: Dictionary = {}
		for info: Dictionary in object.get_property_list():
			var usage: int = info.get("usage", 0)
			if usage & PROPERTY_USAGE_STORAGE:
				properties[str(info.get("name", ""))] = info
		_property_cache[cache_key] = properties
	var cached: Dictionary = _property_cache[cache_key]
	return cached.get(property_name, {})


## Returns a deep copy of JSON containers so patches never alias the parsed data.
static func _plain(json: Variant) -> Variant:
	if json is Dictionary:
		var dictionary: Dictionary = json
		return dictionary.duplicate(true)
	if json is Array:
		var array: Array = json
		return array.duplicate(true)
	return json


static func _type_name(info: PatchValues.TypeInfo) -> String:
	if info.type_script != null and info.type_script.get_global_name() != &"":
		return String(info.type_script.get_global_name())
	if info.type_class != &"":
		return String(info.type_class)
	return type_string(info.type)


static func _mismatch_text(json: Variant, info: PatchValues.TypeInfo) -> String:
	return (
		"cannot use %s %s as %s"
		% [type_string(typeof(json)), JSON.stringify(json).left(60), _type_name(info)]
	)


## Per-call settings and the issues found.
class _Context:
	extends RefCounted

	var target_path: String = ""
	var mod_id: StringName = &""
	var ledger: OverrideLedger = null
	## Store old values for revert.
	var track: bool = true
	## Create missing nested resources ([method ResourcePatcher.fill]).
	var fill: bool = false
	var issues: Array[ModIssue] = []

	func _init(p_target_path: String, p_mod_id: StringName, p_ledger: OverrideLedger) -> void:
		target_path = p_target_path
		mod_id = p_mod_id
		ledger = p_ledger

	## Returns a context for building new values: same issues, no snapshots, no ledger.
	func quiet() -> _Context:
		var copy: _Context = _Context.new(target_path, mod_id, null)
		copy.track = false
		copy.fill = fill
		copy.issues = issues
		return copy

	func record(field_path: String) -> void:
		if ledger != null:
			ledger.record_field(target_path, field_path, mod_id)

	func fail(code: StringName, field_path: String, message: String) -> void:
		var where: String = target_path
		if not field_path.is_empty():
			where += " " + field_path
		issues.append(ModIssue.error(code, mod_id, "%s: %s" % [where, message]))


## One patchable location: an object property, a dictionary key or an array index.
class _Slot:
	extends RefCounted

	enum Kind { OBJECT, DICTIONARY, ARRAY }

	var kind: Kind = Kind.OBJECT
	var object: Object = null
	var dictionary: Dictionary = {}
	var array: Array = []
	var key: Variant = null
	var info: PatchValues.TypeInfo = null
	## The object property that owns this location (for revert snapshots).
	var owner: Object = null
	var owner_property: StringName = &""

	static func on_object(
		p_object: Object, property: StringName, p_info: PatchValues.TypeInfo
	) -> _Slot:
		var slot: _Slot = _Slot.new()
		slot.kind = Kind.OBJECT
		slot.object = p_object
		slot.key = property
		slot.info = p_info
		return slot

	static func on_dictionary(p_dictionary: Dictionary, p_key: Variant) -> _Slot:
		var slot: _Slot = _Slot.new()
		slot.kind = Kind.DICTIONARY
		slot.dictionary = p_dictionary
		slot.key = p_key
		slot.info = PatchValues.dictionary_value(p_dictionary)
		return slot

	static func on_array(p_array: Array, index: int) -> _Slot:
		var slot: _Slot = _Slot.new()
		slot.kind = Kind.ARRAY
		slot.array = p_array
		slot.key = index
		slot.info = PatchValues.array_element(p_array)
		return slot

	func get_value() -> Variant:
		match kind:
			Kind.OBJECT:
				var property: StringName = key
				return object.get(property)
			Kind.ARRAY:
				var index: int = key
				return array[index]
		return dictionary.get(key)

	func set_value(value: Variant) -> void:
		match kind:
			Kind.OBJECT:
				var property: StringName = key
				object.set(property, value)
			Kind.ARRAY:
				var index: int = key
				array[index] = value
			Kind.DICTIONARY:
				dictionary[key] = value


## The value an (object, property) had before its first change.
class _Snapshot:
	extends RefCounted

	var owner: Object = null
	var property: StringName = &""
	var old_value: Variant = null
	var original: Variant = null

	func _init(p_owner: Object, p_property: StringName) -> void:
		owner = p_owner
		property = p_property
		original = owner.get(property)
		if original is Dictionary:
			var dictionary: Dictionary = original
			old_value = dictionary.duplicate(true)
		elif original is Array:
			var array: Array = original
			old_value = array.duplicate(true)
		else:
			old_value = original

	func restore() -> void:
		var current: Variant = owner.get(property)
		if current is Dictionary and is_same(current, original):
			var dictionary: Dictionary = current
			var old_dictionary: Dictionary = old_value
			dictionary.clear()
			dictionary.merge(old_dictionary)
		elif current is Array and is_same(current, original):
			var array: Array = current
			var old_array: Array = old_value
			array.assign(old_array)
		else:
			owner.set(property, old_value)
