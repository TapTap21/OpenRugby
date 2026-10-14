class_name ModRuntime
extends RefCounted
## The applied mod state: load order, asset map, patched resources, extension points and hooks.
##
## [ModLoader] builds it; [code]Main[/code] owns it and passes it down. Moddable asset loads go
## through [method resolve_asset_path] / [method load_resource]. The shipped game applies mods
## once at boot; [method revert] exists for tests and for the "Modern on, then off, changes
## nothing" check. Mounted packs stay mounted (Godot cannot unmount them).

const BASE_ID: StringName = &"base"
var game_version: String = ""
var mod_set_hash: String = ""
var load_order: PackedStringArray = PackedStringArray()
## Applied manifests, base first.
var manifests: Array[ModManifest] = []
var issues: Array[ModIssue] = []
var extension_points: ExtensionPoints = null
var ledger: OverrideLedger = null

## [code]res://[/code] path -> shadowing file of the mod that applied last.
var _asset_map: Dictionary[String, String] = {}
## Strong references to every resource loaded through the runtime (Godot's cache is weak).
var _held: Dictionary[String, Resource] = {}
var _patcher: ResourcePatcher = null
var _entries: Array[_EntryRecord] = []
var _connections: Array[_Connection] = []
var _active: bool = false


func _init() -> void:
	extension_points = ExtensionPoints.new()
	BaseExtensionPoints.declare_into(extension_points)
	ledger = OverrideLedger.new()
	_patcher = ResourcePatcher.new(ledger, load_resource)


## Returns the event bus autoload, or null when it is not in the scene tree.
static func event_bus() -> Node:
	return EventBusAccess.resolve()


## Returns the file that shadows [param path], or [param path] unchanged.
func resolve_asset_path(path: String) -> String:
	return _asset_map.get(path, path)


## Loads [param path] through the asset map and keeps the resource strongly referenced. Returns
## null when nothing exists at the resolved path.
func load_resource(path: String) -> Resource:
	var resolved: String = resolve_asset_path(path)
	var held: Resource = _held.get(resolved)
	if held != null:
		return held
	if resolved.is_empty() or not ResourceLoader.exists(resolved):
		return null
	var loaded: Resource = ResourceLoader.load(resolved)
	if loaded != null:
		_held[resolved] = loaded
	return loaded


## Returns true when any issue is an error.
func has_errors() -> bool:
	for issue: ModIssue in issues:
		if issue.is_error():
			return true
	return false


## Returns true from apply until [method revert].
func is_active() -> bool:
	return _active


## Returns a copy of the asset map ([code]res://[/code] path -> shadowing file).
func asset_map() -> Dictionary[String, String]:
	return _asset_map.duplicate()


## Shuts entry scripts down in reverse load order, removes their hooks and event connections,
## undoes every data patch, clears the asset map and the ledger, and becomes inactive.
func revert() -> void:
	for index: int in range(_entries.size() - 1, -1, -1):
		_entries[index].entry._mod_shutdown()
	for manifest: ModManifest in manifests:
		extension_points.unregister_mod(manifest.id)
	var bus: Node = event_bus()
	for connection: _Connection in _connections:
		if bus != null and bus.is_connected(connection.signal_name, connection.callable):
			bus.disconnect(connection.signal_name, connection.callable)
	_connections.clear()
	_entries.clear()
	_patcher.revert()
	_asset_map.clear()
	ledger.clear()
	_held.clear()
	_active = false


## Marks the runtime as applied. Used by [ModLoader].
func activate() -> void:
	_active = true


## Appends [param issue]. Used by [ModLoader] and [ModApi].
func add_issue(issue: ModIssue) -> void:
	issues.append(issue)


## Maps [param res_path] to the shadowing [param file_path] of [param mod_id] and records it in
## the ledger. Used by [ModLoader].
func map_asset(res_path: String, file_path: String, mod_id: StringName) -> void:
	_asset_map[res_path] = file_path
	ledger.record_asset(res_path, mod_id)


## Applies one data patch to [param target] (loaded from [param target_path]) for
## [param mod_id]. Used by [ModLoader].
func patch(
	target: Resource, target_path: String, fields: Dictionary, mod_id: StringName
) -> Array[ModIssue]:
	_held[target_path] = target
	return _patcher.apply(target, target_path, fields, mod_id)


## Remembers a running entry script so [method revert] can shut it down. Used by [ModLoader].
func add_entry(mod_id: StringName, entry: ModEntry) -> void:
	_entries.append(_EntryRecord.new(mod_id, entry))


## Registers a hook for [param mod_id]; an undeclared point also adds a
## [code]hook_undeclared_point[/code] error. Used by [ModApi].
func register_hook(
	mod_id: StringName,
	point: StringName,
	callable: Callable,
	priority: int = 0,
	stateless_for_match: bool = false,
	setup_fingerprint: String = ""
) -> Error:
	var result: Error = extension_points.register(
		point, mod_id, callable, priority, stateless_for_match, setup_fingerprint
	)
	if result == ERR_DOES_NOT_EXIST:
		add_issue(
			ModIssue.error(
				&"hook_undeclared_point",
				mod_id,
				"'%s' registered a hook on undeclared point '%s'" % [mod_id, point]
			)
		)
	return result


## Connects [param callable] to the event bus signal [param signal_name] for [param mod_id] and
## tracks it for [method revert]. Used by [ModApi].
func connect_event(mod_id: StringName, signal_name: StringName, callable: Callable) -> Error:
	var bus: Node = event_bus()
	if bus == null or not bus.has_signal(signal_name):
		return ERR_DOES_NOT_EXIST
	if not callable.is_valid():
		return ERR_INVALID_PARAMETER
	var result: Error = bus.connect(signal_name, callable) as Error
	if result == OK:
		_connections.append(_Connection.new(mod_id, signal_name, callable))
	return result


## A running entry script.
class _EntryRecord:
	extends RefCounted

	var mod_id: StringName = &""
	var entry: ModEntry = null

	func _init(p_mod_id: StringName, p_entry: ModEntry) -> void:
		mod_id = p_mod_id
		entry = p_entry


## An event bus connection made by a mod.
class _Connection:
	extends RefCounted

	var mod_id: StringName = &""
	var signal_name: StringName = &""
	var callable: Callable = Callable()

	func _init(p_mod_id: StringName, p_signal_name: StringName, p_callable: Callable) -> void:
		mod_id = p_mod_id
		signal_name = p_signal_name
		callable = p_callable
