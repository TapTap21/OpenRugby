class_name OverrideLedger
extends RefCounted
## Provenance of every patched resource field and shadowed asset, and the conflicts between mods.
##
## A conflict is a field or asset touched by two or more distinct mods. Untouched fields and
## assets belong to [code]base[/code].

const BASE_ID: StringName = &"base"

## Field writers keyed by [code]resource_path + "\n" + field_path[/code].
var _fields: Dictionary[String, _Entry] = {}
## Asset writers keyed by [code]res://[/code] path.
var _assets: Dictionary[String, _Entry] = {}


## Records that [param mod_id] wrote [param field_path] of the resource at [param resource_path].
func record_field(resource_path: String, field_path: String, mod_id: StringName) -> void:
	var key: String = resource_path + "\n" + field_path
	var entry: _Entry = _fields.get(key)
	if entry == null:
		entry = _Entry.new(&"field", resource_path, field_path)
		_fields[key] = entry
	entry.writers.append(mod_id)


## Records that [param mod_id] shadows the asset at [param res_path].
func record_asset(res_path: String, mod_id: StringName) -> void:
	var entry: _Entry = _assets.get(res_path)
	if entry == null:
		entry = _Entry.new(&"asset", res_path, "")
		_assets[res_path] = entry
	entry.writers.append(mod_id)


## Returns the mod that last wrote the field, or [code]&"base"[/code] if it was never patched.
func last_writer(resource_path: String, field_path: String) -> StringName:
	var entry: _Entry = _fields.get(resource_path + "\n" + field_path)
	return _last(entry)


## Returns every writer of the field in write order (repeats kept).
func field_writers(resource_path: String, field_path: String) -> Array[StringName]:
	var entry: _Entry = _fields.get(resource_path + "\n" + field_path)
	return _writers(entry)


## Returns the mod whose file shadows [param res_path], or [code]&"base"[/code].
func asset_owner(res_path: String) -> StringName:
	var entry: _Entry = _assets.get(res_path)
	return _last(entry)


## Returns every mod that shadowed [param res_path], in apply order (repeats kept).
func asset_writers(res_path: String) -> Array[StringName]:
	var entry: _Entry = _assets.get(res_path)
	return _writers(entry)


## Returns one entry per field or asset touched by two or more distinct mods:
## [code]{"kind", "target", "field", "mods", "winner"}[/code], sorted by kind (assets first),
## then target, then field.
func conflicts() -> Array[Dictionary]:
	var entries: Array[_Entry] = []
	for entry: _Entry in _assets.values():
		if entry.distinct_writers().size() > 1:
			entries.append(entry)
	for entry: _Entry in _fields.values():
		if entry.distinct_writers().size() > 1:
			entries.append(entry)
	entries.sort_custom(_entry_less)
	var result: Array[Dictionary] = []
	for entry: _Entry in entries:
		(
			result
			. append(
				{
					"kind": entry.kind,
					"target": entry.target,
					"field": entry.field,
					"mods": entry.distinct_writers(),
					"winner": entry.writers[entry.writers.size() - 1],
				}
			)
		)
	return result


## Forgets every record.
func clear() -> void:
	_fields.clear()
	_assets.clear()


static func _last(entry: _Entry) -> StringName:
	if entry == null or entry.writers.is_empty():
		return BASE_ID
	return entry.writers[entry.writers.size() - 1]


static func _writers(entry: _Entry) -> Array[StringName]:
	if entry == null:
		return []
	return entry.writers.duplicate()


static func _entry_less(left: _Entry, right: _Entry) -> bool:
	if left.kind != right.kind:
		return left.kind == &"asset"
	if left.target != right.target:
		return left.target < right.target
	return left.field < right.field


## Writers of one field or asset.
class _Entry:
	extends RefCounted

	var kind: StringName = &""
	var target: String = ""
	var field: String = ""
	var writers: Array[StringName] = []

	func _init(p_kind: StringName, p_target: String, p_field: String) -> void:
		kind = p_kind
		target = p_target
		field = p_field

	func distinct_writers() -> Array[StringName]:
		var result: Array[StringName] = []
		for writer: StringName in writers:
			if not result.has(writer):
				result.append(writer)
		return result
