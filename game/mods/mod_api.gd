class_name ModApi
extends RefCounted
## What a mod entry script receives in [method ModEntry._mod_init].
##
## It may register callables on declared [ExtensionPoints] and connect to [code]EventBus[/code]
## signals, and load resources through the mod runtime. It exposes no scene tree access; mods are
## trusted code, so this is a convention, not a sandbox.

## The id of the mod this API belongs to (read-only).
var mod_id: StringName:
	get:
		return _mod_id
	set(_value):
		push_error("ModApi.mod_id is read-only")

var _mod_id: StringName = &""
## Weak, so that entry scripts keeping their API do not keep the runtime alive.
var _runtime_ref: WeakRef = null


func _init(p_runtime: ModRuntime, p_mod_id: StringName) -> void:
	_runtime_ref = weakref(p_runtime)
	_mod_id = p_mod_id


## Registers [param callable] on the extension point [param point]. An undeclared point returns
## [constant ERR_DOES_NOT_EXIST] and adds a [code]hook_undeclared_point[/code] error.
func register_hook(
	point: StringName,
	callable: Callable,
	priority: int = 0,
	stateless_for_match: bool = false,
	setup_fingerprint: String = ""
) -> Error:
	var runtime: ModRuntime = _runtime()
	if runtime == null:
		return ERR_UNAVAILABLE
	return runtime.register_hook(
		_mod_id, point, callable, priority, stateless_for_match, setup_fingerprint
	)


## Connects [param callable] to the [code]EventBus[/code] signal [param signal_name]; returns
## [constant ERR_DOES_NOT_EXIST] if the bus has no such signal. Reverting the runtime disconnects
## it.
func connect_event(signal_name: StringName, callable: Callable) -> Error:
	var runtime: ModRuntime = _runtime()
	if runtime == null:
		return ERR_UNAVAILABLE
	return runtime.connect_event(_mod_id, signal_name, callable)


## Loads [param path] through the mod runtime (asset overrides apply).
func load_resource(path: String) -> Resource:
	var runtime: ModRuntime = _runtime()
	if runtime == null:
		return null
	return runtime.load_resource(path)


## Returns the file that shadows [param path], or [param path] unchanged.
func resolve_asset_path(path: String) -> String:
	var runtime: ModRuntime = _runtime()
	if runtime == null:
		return path
	return runtime.resolve_asset_path(path)


func _runtime() -> ModRuntime:
	var runtime: ModRuntime = _runtime_ref.get_ref()
	return runtime
