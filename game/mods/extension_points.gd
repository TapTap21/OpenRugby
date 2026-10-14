class_name ExtensionPoints
extends RefCounted
## Registry of named extension points that mod entry scripts hook into (layer 3).
##
## The base game declares points ([BaseExtensionPoints]); mods register callables on them through
## [ModApi]. Hooks run in ascending priority, ties in registration order (mods register in load
## order, so ties follow load order).

## OBSERVER hooks are notified, FILTER hooks transform a value, PROVIDER hooks contribute items.
enum Kind { OBSERVER, FILTER, PROVIDER }

var _points: Dictionary[StringName, _Point] = {}
var _next_sequence: int = 0


## Declares [param point]. Returns [constant ERR_ALREADY_EXISTS] if it is already declared.
func declare(point: StringName, kind: Kind, description: String = "") -> Error:
	if _points.has(point):
		return ERR_ALREADY_EXISTS
	_points[point] = _Point.new(kind, description)
	return OK


## Returns true when [param point] is declared.
func is_declared(point: StringName) -> bool:
	return _points.has(point)


## Returns the kind of [param point] ([constant Kind.OBSERVER] when undeclared).
func kind_of(point: StringName) -> Kind:
	var entry: _Point = _points.get(point)
	if entry == null:
		return Kind.OBSERVER
	return entry.kind


## Returns the description given when [param point] was declared.
func description_of(point: StringName) -> String:
	var entry: _Point = _points.get(point)
	if entry == null:
		return ""
	return entry.description


## Registers [param callable] on [param point] for [param mod_id].
## Returns [constant ERR_DOES_NOT_EXIST] for an undeclared point and
## [constant ERR_INVALID_PARAMETER] for an invalid callable.
func register(
	point: StringName, mod_id: StringName, callable: Callable, priority: int = 0
) -> Error:
	var entry: _Point = _points.get(point)
	if entry == null:
		return ERR_DOES_NOT_EXIST
	if not callable.is_valid():
		return ERR_INVALID_PARAMETER
	entry.hooks.append(_Hook.new(mod_id, callable, priority, _next_sequence))
	_next_sequence += 1
	entry.hooks.sort_custom(_hook_less)
	return OK


## Removes every hook that [param mod_id] registered.
func unregister_mod(mod_id: StringName) -> void:
	for entry: _Point in _points.values():
		var kept: Array[_Hook] = []
		for hook: _Hook in entry.hooks:
			if hook.mod_id != mod_id:
				kept.append(hook)
		entry.hooks = kept


## Returns the hooks of [param point] in call order.
func hooks(point: StringName) -> Array[Callable]:
	var result: Array[Callable] = []
	var entry: _Point = _points.get(point)
	if entry == null:
		return result
	for hook: _Hook in entry.hooks:
		result.append(hook.callable)
	return result


## Calls every hook of the OBSERVER [param point] with [param args].
func notify(point: StringName, args: Array = []) -> void:
	if not _check_kind(point, Kind.OBSERVER):
		return
	for callable: Callable in _live_hooks(point):
		callable.callv(args)


## Passes [param value] through every hook of the FILTER [param point]: each hook receives
## [code][value] + args[/code] and returns the new value.
func filter(point: StringName, value: Variant, args: Array = []) -> Variant:
	if not _check_kind(point, Kind.FILTER):
		return value
	var current: Variant = value
	for callable: Callable in _live_hooks(point):
		current = callable.callv([current] + args)
	return current


## Returns every non-null value returned by the hooks of the PROVIDER [param point].
func collect(point: StringName, args: Array = []) -> Array:
	var result: Array = []
	if not _check_kind(point, Kind.PROVIDER):
		return result
	for callable: Callable in _live_hooks(point):
		var item: Variant = callable.callv(args)
		if item != null:
			result.append(item)
	return result


## Returns the declared point names, sorted.
func declared_points() -> PackedStringArray:
	var names: Array[String] = []
	for point: StringName in _points.keys():
		names.append(String(point))
	names.sort()
	return PackedStringArray(names)


func _check_kind(point: StringName, kind: Kind) -> bool:
	var entry: _Point = _points.get(point)
	if entry == null:
		push_error("extension point '%s' is not declared" % point)
		return false
	if entry.kind != kind:
		push_error(
			(
				"extension point '%s' is %s, not %s"
				% [point, Kind.find_key(entry.kind), Kind.find_key(kind)]
			)
		)
		return false
	return true


func _live_hooks(point: StringName) -> Array[Callable]:
	var result: Array[Callable] = []
	for callable: Callable in hooks(point):
		if callable.is_valid():
			result.append(callable)
	return result


static func _hook_less(left: _Hook, right: _Hook) -> bool:
	if left.priority != right.priority:
		return left.priority < right.priority
	return left.sequence < right.sequence


## One declared point.
class _Point:
	extends RefCounted

	var kind: Kind = Kind.OBSERVER
	var description: String = ""
	var hooks: Array[_Hook] = []

	func _init(p_kind: Kind, p_description: String) -> void:
		kind = p_kind
		description = p_description


## One registered hook.
class _Hook:
	extends RefCounted

	var mod_id: StringName = &""
	var callable: Callable = Callable()
	var priority: int = 0
	var sequence: int = 0

	func _init(
		p_mod_id: StringName, p_callable: Callable, p_priority: int, p_sequence: int
	) -> void:
		mod_id = p_mod_id
		callable = p_callable
		priority = p_priority
		sequence = p_sequence
