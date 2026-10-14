class_name EventBusAccess
extends RefCounted
## Resolves and emits signals on the EventBus autoload without compile-time singleton access.
##
## Scripts launched with Godot's `-s` entry point can execute without project autoload instances.
## Callers can therefore use the same feature scripts in the game and in headless script tests.

const EVENT_BUS_PATH: NodePath = ^"/root/EventBus"


## Returns the EventBus autoload when the active main loop has a scene tree, otherwise null.
static func resolve() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(EVENT_BUS_PATH)


## Emits [param signal_name] with [param arguments], or returns an error when unavailable.
static func emit(signal_name: StringName, arguments: Array = []) -> Error:
	var bus: Node = resolve()
	if bus == null or not bus.has_signal(signal_name):
		return ERR_UNAVAILABLE
	var call_arguments: Array = [signal_name]
	call_arguments.append_array(arguments)
	return bus.emit_signal.callv(call_arguments)
