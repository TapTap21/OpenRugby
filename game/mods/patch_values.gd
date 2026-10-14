class_name PatchValues
extends RefCounted
## JSON value conversion and type checks for [ResourcePatcher] (internal helper).
##
## Conversions return [code][ok: bool, value: Variant][/code] so that null stays a valid value.

const _HEX_COLOR: String = "^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"

static var _hex_regex: RegEx = null
static var _global_class_paths: Dictionary[StringName, String] = {}


## Returns the declared type of an object property from its [method Object.get_property_list]
## entry.
static func from_property(info: Dictionary) -> TypeInfo:
	var result: TypeInfo = TypeInfo.new()
	result.type = info.get("type", TYPE_NIL)
	result.type_class = info.get("class_name", &"")
	var hint: int = info.get("hint", PROPERTY_HINT_NONE)
	if result.type == TYPE_INT and hint == PROPERTY_HINT_ENUM:
		result.enum_hint = info.get("hint_string", "")
	return result


## Returns the element type of [param array] (untyped arrays give [constant TYPE_NIL]).
static func array_element(array: Array) -> TypeInfo:
	var result: TypeInfo = TypeInfo.new()
	result.type = array.get_typed_builtin()
	result.type_class = array.get_typed_class_name()
	result.type_script = array.get_typed_script()
	return result


## Returns the value type of [param dictionary] (untyped values give [constant TYPE_NIL]).
static func dictionary_value(dictionary: Dictionary) -> TypeInfo:
	var result: TypeInfo = TypeInfo.new()
	result.type = dictionary.get_typed_value_builtin()
	result.type_class = dictionary.get_typed_value_class_name()
	result.type_script = dictionary.get_typed_value_script()
	return result


## Returns a [TypeInfo] for the built-in [param type].
static func builtin(type: int) -> TypeInfo:
	var result: TypeInfo = TypeInfo.new()
	result.type = type
	return result


## Converts the JSON key [param text] to the key type of [param dictionary].
static func convert_key(text: String, dictionary: Dictionary) -> Array:
	match dictionary.get_typed_key_builtin():
		TYPE_NIL, TYPE_STRING:
			return [true, text]
		TYPE_STRING_NAME:
			return [true, StringName(text)]
		TYPE_INT:
			if text.is_valid_int():
				return [true, text.to_int()]
		TYPE_FLOAT:
			if text.is_valid_float():
				return [true, text.to_float()]
	return [false, null]


## Converts a JSON scalar to [param info]'s built-in type (bool, int incl. enum names, float,
## strings, Color, vectors).
static func convert_scalar(json: Variant, info: TypeInfo) -> Array:
	match info.type:
		TYPE_BOOL:
			if json is bool:
				return [true, json]
		TYPE_INT:
			if is_integral(json):
				return [true, to_int(json)]
			if json is String and not info.enum_hint.is_empty():
				return enum_value(info.enum_hint, str(json))
		TYPE_FLOAT:
			if json is float or json is int:
				return [true, to_float(json)]
		TYPE_STRING:
			if json is String or json is StringName:
				return [true, str(json)]
		TYPE_STRING_NAME:
			if json is String or json is StringName:
				return [true, StringName(str(json))]
		TYPE_NODE_PATH:
			if json is String:
				return [true, NodePath(str(json))]
		TYPE_COLOR:
			return _color(json)
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			return _vector(json, info.type)
	return [false, null]


## Looks up [param name] in an enum hint string ([code]"A:0,B:1"[/code] or [code]"A,B"[/code]).
## Godot capitalizes script enum names in the hint ([code]PRIMARY_KICK[/code] becomes
## [code]Primary Kick[/code]), so an exact match wins, then a match ignoring case, spaces and
## underscores.
static func enum_value(hint_string: String, name: String) -> Array:
	var next_value: int = 0
	var loose: Array = [false, null]
	for item: String in hint_string.split(",", false):
		var parts: PackedStringArray = item.split(":")
		var value: int = next_value
		if parts.size() > 1 and parts[1].strip_edges().is_valid_int():
			value = parts[1].strip_edges().to_int()
		var label: String = parts[0].strip_edges()
		if label == name:
			return [true, value]
		if not loose[0] and _enum_key(label) == _enum_key(name):
			loose = [true, value]
		next_value = value + 1
	return loose


## Returns the element type of a packed array type, or [constant TYPE_NIL] for other types.
static func packed_element_type(type: int) -> int:
	match type:
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return TYPE_INT
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return TYPE_FLOAT
		TYPE_PACKED_STRING_ARRAY:
			return TYPE_STRING
		TYPE_PACKED_VECTOR2_ARRAY:
			return TYPE_VECTOR2
		TYPE_PACKED_VECTOR3_ARRAY:
			return TYPE_VECTOR3
		TYPE_PACKED_VECTOR4_ARRAY:
			return TYPE_VECTOR4
		TYPE_PACKED_COLOR_ARRAY:
			return TYPE_COLOR
	return TYPE_NIL


## Returns true when [param value] is an int or an integral, finite float.
static func is_integral(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return is_finite(number) and number == floorf(number) and absf(number) < 9.0e15
	return false


## Returns [param value] (an int or float) as an int.
static func to_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	return int(to_float(value))


## Returns [param value] (an int or float) as a float; other values give 0.0.
static func to_float(value: Variant) -> float:
	if value is float:
		var number: float = value
		return number
	if value is int:
		var whole: int = value
		return float(whole)
	return 0.0


## Returns true when [param object] is an instance of the class or script [param info] declares.
static func is_instance(object: Object, info: TypeInfo) -> bool:
	if info.type_script != null:
		return _script_chain_has(object, info.type_script)
	if info.type_class == &"":
		return true
	if ClassDB.class_exists(info.type_class):
		return object.is_class(info.type_class)
	return has_global_class(object, info.type_class)


## Returns true when the script of [param object], or one of its base scripts, has the global
## class name [param global_name].
static func has_global_class(object: Object, global_name: StringName) -> bool:
	if object == null:
		return false
	var script: Script = object.get_script()
	while script != null:
		if script.get_global_name() == global_name:
			return true
		script = script.get_base_script()
	return false


## Creates a new [Resource] of the class [param info] declares, or returns null when that class
## cannot be instantiated or is not a resource.
static func instantiate(info: TypeInfo) -> Resource:
	var script: Script = info.type_script
	if script == null and info.type_class != &"" and not ClassDB.class_exists(info.type_class):
		script = _global_class_script(info.type_class)
	var created: Variant = null
	if script is GDScript and script.can_instantiate():
		var gdscript: GDScript = script
		created = gdscript.new()
	elif (
		script == null
		and ClassDB.class_exists(info.type_class)
		and ClassDB.can_instantiate(info.type_class)
		and ClassDB.is_parent_class(info.type_class, &"Resource")
	):
		created = ClassDB.instantiate(info.type_class)
	if created is Resource:
		return created
	if created is Object and not created is RefCounted:
		var object: Object = created
		object.free()
	return null


static func _enum_key(label: String) -> String:
	return label.replace(" ", "").replace("_", "").to_lower()


static func _script_chain_has(object: Object, wanted: Script) -> bool:
	var script: Script = object.get_script()
	while script != null:
		if script == wanted:
			return true
		script = script.get_base_script()
	return false


static func _global_class_script(global_name: StringName) -> Script:
	if _global_class_paths.is_empty():
		for entry: Dictionary in ProjectSettings.get_global_class_list():
			var entry_name: StringName = entry.get("class", &"")
			var entry_path: String = entry.get("path", "")
			_global_class_paths[entry_name] = entry_path
	var path: String = _global_class_paths.get(global_name, "")
	if path.is_empty():
		return null
	return load(path) as Script


static func _color(json: Variant) -> Array:
	if json is String:
		if _hex_regex == null:
			_hex_regex = RegEx.create_from_string(_HEX_COLOR)
		if _hex_regex.search(str(json)) != null:
			return [true, Color.html(str(json))]
		return [false, null]
	var numbers: Array[float] = _numbers(json, 3, 4, false)
	if numbers.is_empty():
		return [false, null]
	for number: float in numbers:
		if number < 0.0 or number > 1.0:
			return [false, null]
	var alpha: float = 1.0
	if numbers.size() == 4:
		alpha = numbers[3]
	return [true, Color(numbers[0], numbers[1], numbers[2], alpha)]


static func _vector(json: Variant, type: int) -> Array:
	var size: int = 2
	if type == TYPE_VECTOR3 or type == TYPE_VECTOR3I:
		size = 3
	elif type == TYPE_VECTOR4 or type == TYPE_VECTOR4I:
		size = 4
	var integral: bool = type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]
	var n: Array[float] = _numbers(json, size, size, integral)
	if n.is_empty():
		return [false, null]
	match type:
		TYPE_VECTOR2:
			return [true, Vector2(n[0], n[1])]
		TYPE_VECTOR2I:
			return [true, Vector2i(int(n[0]), int(n[1]))]
		TYPE_VECTOR3:
			return [true, Vector3(n[0], n[1], n[2])]
		TYPE_VECTOR3I:
			return [true, Vector3i(int(n[0]), int(n[1]), int(n[2]))]
		TYPE_VECTOR4:
			return [true, Vector4(n[0], n[1], n[2], n[3])]
	return [true, Vector4i(int(n[0]), int(n[1]), int(n[2]), int(n[3]))]


## Returns the numbers of a JSON array of [param min_size]..[param max_size] numbers as floats,
## or an empty array when [param json] is not such an array.
static func _numbers(json: Variant, min_size: int, max_size: int, integral: bool) -> Array[float]:
	var numbers: Array[float] = []
	if not json is Array:
		return numbers
	var values: Array = json
	if values.size() < min_size or values.size() > max_size:
		return numbers
	for value: Variant in values:
		if not (value is float or value is int) or (integral and not is_integral(value)):
			numbers.clear()
			return numbers
		numbers.append(to_float(value))
	return numbers


## A declared type: built-in [member type], plus class and script for objects and the enum hint
## for enum-typed ints.
class TypeInfo:
	extends RefCounted

	var type: int = TYPE_NIL
	var type_class: StringName = &""
	var type_script: Script = null
	var enum_hint: String = ""
