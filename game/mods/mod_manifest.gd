class_name ModManifest
extends RefCounted
## A parsed [code]mod.json[/code] (schema version 1), plus where the mod was found.
##
## Parsing never fails: every problem becomes a [ModIssue] in [member issues], so the mod manager
## can show why a mod cannot load. See [code]docs/specs/S1-modloader.md[/code] section 2.

enum Source { BASE, BUILTIN, USER_FOLDER, USER_PCK }

const SCHEMA_VERSION: int = 1
const BASE_ID: StringName = &"base"
const MANIFEST_FILE: String = "mod.json"
const CAPABILITIES: PackedStringArray = ["data", "assets", "rules", "scripts", "ui"]
const ID_PATTERN: String = "^[a-z0-9][a-z0-9_-]{1,63}$"
const MIN_PRIORITY: int = -1000
const MAX_PRIORITY: int = 1000

const _KNOWN_KEYS: PackedStringArray = [
	"schema_version",
	"id",
	"name",
	"version",
	"author",
	"description",
	"game_version",
	"dependencies",
	"load_priority",
	"capabilities",
	"entry_script",
]
const _DEPENDENCY_KEYS: PackedStringArray = ["id", "version", "optional"]

static var _id_regex: RegEx = null

var id: StringName = &""
var name: String = ""
var author: String = ""
var description: String = ""
var version_text: String = ""
var game_version_text: String = ""
var entry_script: String = ""
var root_path: String = ""
var pck_path: String = ""
var version: ModVersion = null
var game_version: VersionConstraint = null
var dependencies: Array[ModDependency] = []
var load_priority: int = 0
var capabilities: PackedStringArray = PackedStringArray()
var source: Source = Source.BUILTIN
var issues: Array[ModIssue] = []


## Builds a manifest from parsed JSON [param data]. Never returns null; problems become issues.
## The folder-name rule compares the id with the last path segment of [param p_root_path].
static func parse(data: Dictionary, p_root_path: String, p_source: Source) -> ModManifest:
	var manifest: ModManifest = ModManifest.new()
	manifest.root_path = p_root_path
	manifest.source = p_source
	manifest.id = StringName(folder_name(p_root_path))
	for key: Variant in data.keys():
		if not _KNOWN_KEYS.has(str(key)):
			manifest._warn(&"manifest_unknown_key", "unknown top-level key '%s'" % str(key))
	manifest._parse_schema(data)
	manifest._parse_id(data)
	manifest.name = manifest._read_string(data, "name", true, "")
	if manifest.name.strip_edges().is_empty() and data.get("name") is String:
		manifest._fail(&"manifest_invalid_field", "'name' must not be empty")
	manifest.author = manifest._read_string(data, "author", false, "")
	manifest.description = manifest._read_string(data, "description", false, "")
	manifest._parse_versions(data)
	manifest._parse_dependencies(data)
	manifest._parse_priority(data)
	manifest._parse_capabilities(data)
	manifest._parse_entry_script(data)
	return manifest


## Reads and parses [code]<p_root_path>/mod.json[/code]. An unreadable file or invalid JSON gives
## a [code]manifest_parse_error[/code] issue.
static func load_file(p_root_path: String, p_source: Source) -> ModManifest:
	var path: String = p_root_path.path_join(MANIFEST_FILE)
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	var problem: String = ""
	if text.is_empty() and FileAccess.get_open_error() != OK:
		problem = "cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	elif json.parse(text) != OK:
		problem = "%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
	elif not json.data is Dictionary:
		problem = "%s: the top level must be a JSON object" % path
	if problem.is_empty():
		var data: Dictionary = json.data
		return parse(data, p_root_path, p_source)
	var manifest: ModManifest = ModManifest.new()
	manifest.root_path = p_root_path
	manifest.source = p_source
	manifest.id = StringName(folder_name(p_root_path))
	manifest._fail(&"manifest_parse_error", problem)
	return manifest


## Returns the manifest that stands for the base game ("mod zero").
static func make_base(p_game_version: String) -> ModManifest:
	var manifest: ModManifest = ModManifest.new()
	manifest.id = BASE_ID
	manifest.name = "OpenRugby"
	manifest.version_text = p_game_version
	manifest.version = ModVersion.parse(p_game_version)
	manifest.game_version_text = "*"
	manifest.game_version = VersionConstraint.parse("*")
	manifest.root_path = "res://"
	manifest.source = Source.BASE
	manifest.capabilities = CAPABILITIES.duplicate()
	return manifest


## Returns the last path segment of [param path] ([code]res://mods/foo/[/code] gives
## [code]foo[/code]).
static func folder_name(path: String) -> String:
	var trimmed: String = path.trim_suffix("/")
	if trimmed.ends_with(":/"):
		return ""
	return trimmed.get_file()


## Returns true when [param text] is a well-formed mod id (the reserved id [code]base[/code]
## included).
static func is_valid_id(text: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.create_from_string(ID_PATTERN)
	return _id_regex.search(text) != null


## Returns true when the manifest has no error issues.
func is_valid() -> bool:
	for issue: ModIssue in issues:
		if issue.is_error():
			return false
	return true


## Returns true when the manifest declares [param capability].
func has_capability(capability: StringName) -> bool:
	return capabilities.has(String(capability))


## Returns true when the mod runs code (capability [code]scripts[/code]).
func is_script_mod() -> bool:
	return has_capability(&"scripts")


func _parse_schema(data: Dictionary) -> void:
	if not data.has("schema_version"):
		_fail(&"manifest_invalid_field", "missing required key 'schema_version'")
		return
	var value: Variant = data["schema_version"]
	if not _is_integral(value):
		_fail(&"manifest_invalid_field", "'schema_version' must be an integer")
	elif _as_int(value) > SCHEMA_VERSION:
		_fail(
			&"manifest_unsupported_schema",
			"schema_version %d is newer than supported (%d)" % [_as_int(value), SCHEMA_VERSION]
		)
	elif _as_int(value) < 1:
		_fail(&"manifest_invalid_field", "'schema_version' must be at least 1")


func _parse_id(data: Dictionary) -> void:
	var text: String = _read_string(data, "id", true, "")
	if not data.get("id") is String:
		return
	id = StringName(text)
	if not is_valid_id(text):
		_fail(&"manifest_invalid_field", "'id' must match %s" % ID_PATTERN)
	elif id == BASE_ID:
		_fail(&"manifest_reserved_id", "the id 'base' is reserved for the game")
	elif text != folder_name(root_path):
		_fail(
			&"manifest_id_mismatch",
			"id '%s' does not match its folder '%s'" % [text, folder_name(root_path)]
		)


func _parse_versions(data: Dictionary) -> void:
	version_text = _read_string(data, "version", true, "")
	if data.get("version") is String:
		version = ModVersion.parse(version_text)
		if version == null:
			_fail(&"manifest_invalid_field", "'version' is not a semantic version")
	game_version_text = _read_string(data, "game_version", true, "")
	if data.get("game_version") is String:
		game_version = VersionConstraint.parse(game_version_text)
		if game_version == null:
			_fail(&"manifest_invalid_field", "'game_version' is not a version constraint")


func _parse_dependencies(data: Dictionary) -> void:
	if not data.has("dependencies"):
		return
	if not data["dependencies"] is Array:
		_fail(&"manifest_invalid_field", "'dependencies' must be an array")
		return
	var entries: Array = data["dependencies"]
	var seen: Dictionary[StringName, bool] = {}
	for entry: Variant in entries:
		var dependency: ModDependency = _parse_dependency(entry)
		if dependency == null:
			continue
		if dependency.id == id:
			_fail(&"manifest_invalid_field", "a mod cannot depend on itself")
		elif seen.has(dependency.id):
			_fail(&"manifest_invalid_field", "duplicate dependency '%s'" % dependency.id)
		else:
			seen[dependency.id] = true
			dependencies.append(dependency)


func _parse_dependency(entry: Variant) -> ModDependency:
	if not entry is Dictionary:
		_fail(&"manifest_invalid_field", "each dependency must be an object")
		return null
	var data: Dictionary = entry
	for key: Variant in data.keys():
		if not _DEPENDENCY_KEYS.has(str(key)):
			_warn(&"manifest_unknown_key", "unknown dependency key '%s'" % str(key))
	var dependency: ModDependency = ModDependency.new()
	var dep_id: Variant = data.get("id")
	if not dep_id is String or not is_valid_id(str(dep_id)):
		_fail(&"manifest_invalid_field", "dependency 'id' must be a valid mod id")
		return null
	dependency.id = StringName(str(dep_id))
	var constraint_value: Variant = data.get("version", "*")
	if constraint_value is String:
		dependency.constraint_text = str(constraint_value)
		dependency.constraint = VersionConstraint.parse(dependency.constraint_text)
	if dependency.constraint == null:
		_fail(&"manifest_invalid_field", "dependency '%s' has an invalid version" % dep_id)
		return null
	var optional_value: Variant = data.get("optional", false)
	if not optional_value is bool:
		_fail(&"manifest_invalid_field", "dependency '%s' 'optional' must be a bool" % dep_id)
		return null
	dependency.optional = optional_value
	return dependency


func _parse_priority(data: Dictionary) -> void:
	if not data.has("load_priority"):
		return
	var value: Variant = data["load_priority"]
	if not _is_integral(value) or _as_int(value) < MIN_PRIORITY or _as_int(value) > MAX_PRIORITY:
		_fail(
			&"manifest_invalid_field",
			"'load_priority' must be an integer in [%d, %d]" % [MIN_PRIORITY, MAX_PRIORITY]
		)
		return
	load_priority = _as_int(value)


func _parse_capabilities(data: Dictionary) -> void:
	if not data.has("capabilities"):
		_fail(&"manifest_invalid_field", "missing required key 'capabilities'")
		return
	if not data["capabilities"] is Array:
		_fail(&"manifest_invalid_field", "'capabilities' must be an array")
		return
	var values: Array = data["capabilities"]
	for value: Variant in values:
		if not value is String or not CAPABILITIES.has(str(value)):
			_fail(&"manifest_invalid_field", "unknown capability '%s'" % str(value))
		elif not capabilities.has(str(value)):
			capabilities += PackedStringArray([str(value)])


func _parse_entry_script(data: Dictionary) -> void:
	entry_script = _read_string(data, "entry_script", false, "")
	var scripts: bool = has_capability(&"scripts")
	if scripts and entry_script.is_empty():
		_fail(&"manifest_invalid_field", "capability 'scripts' requires 'entry_script'")
	elif not scripts and not entry_script.is_empty():
		_fail(&"manifest_invalid_field", "'entry_script' requires capability 'scripts'")
	elif not entry_script.is_empty() and not _is_safe_relative_script(entry_script):
		_fail(
			&"manifest_invalid_field",
			"'entry_script' must be a relative .gd path inside the mod folder"
		)


## Reads a string key; reports a missing required key or a wrong type.
func _read_string(data: Dictionary, key: String, required: bool, default: String) -> String:
	if not data.has(key):
		if required:
			_fail(&"manifest_invalid_field", "missing required key '%s'" % key)
		return default
	var value: Variant = data[key]
	if not value is String:
		_fail(&"manifest_invalid_field", "'%s' must be a string" % key)
		return default
	return str(value)


func _fail(code: StringName, message: String) -> void:
	issues.append(ModIssue.error(code, id, message))


func _warn(code: StringName, message: String) -> void:
	issues.append(ModIssue.warning(code, id, message))


static func _is_integral(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return is_finite(number) and number == floorf(number) and absf(number) < 9.0e15
	return false


static func _as_int(value: Variant) -> int:
	if value is int:
		var whole: int = value
		return whole
	var number: float = value if value is float else 0.0
	return int(number)


static func _is_safe_relative_script(path: String) -> bool:
	if not path.ends_with(".gd") or path.contains("\\") or path.contains(":"):
		return false
	if path.begins_with("/"):
		return false
	for segment: String in path.split("/"):
		if segment == ".." or segment.is_empty():
			return false
	return true
