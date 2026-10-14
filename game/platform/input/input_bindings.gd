class_name InputBindings
extends RefCounted
## Owns the live [InputMap] bindings of an [InputActionSet]: defaults, remapping and persistence.
##
## Every successful mutation emits [signal EventBus.input_bindings_changed]. Nothing here writes
## to res://; saved bindings go to user:// only.

## Device kind a binding belongs to.
enum Device { GAMEPAD, KEYBOARD }

## Version of the saved bindings file.
const SCHEMA_VERSION: int = 1

## Default path of the saved bindings file.
const DEFAULT_PATH: String = "user://input_bindings.cfg"

const _SECTION_META: String = "meta"
const _SECTION_GAMEPAD: String = "gamepad"
const _SECTION_KEYBOARD: String = "keyboard"

## The action set whose bindings this object manages.
var action_set: InputActionSet


func _init(p_action_set: InputActionSet) -> void:
	action_set = p_action_set


## Sets every action to its default bindings and deadzone. Emits the changed signal once.
func apply_defaults() -> void:
	for action: InputActionDef in action_set.actions:
		if action != null:
			_apply_default(action)
		_emit_bindings_changed()


## Returns the current [InputMap] events of [param action_id] for [param device], in map order.
func get_events(action_id: StringName, device: Device) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	if not InputMap.has_action(action_id):
		return result
	for event: InputEvent in InputMap.action_get_events(action_id):
		if InputEventCodec.device_of(event) == device:
			result.append(event)
	return result


## Replaces the [param index]-th event of [param device] with [param event]. An index equal to
## the count appends. Does not resolve conflicts. Returns an [Error].
func rebind(action_id: StringName, device: Device, index: int, event: InputEvent) -> Error:
	return _edit(action_id, device, index, event, false)


## Removes the [param index]-th event of [param device]. Returns an [Error].
func unbind(action_id: StringName, device: Device, index: int) -> Error:
	return _edit(action_id, device, index, null, true)


## Returns the other actions that already use [param event] and can be pressed together with
## [param action_id]. UI and MATCH actions are never co-active.
func find_conflicts(action_id: StringName, event: InputEvent) -> Array[StringName]:
	var result: Array[StringName] = []
	var definition: InputActionDef = action_set.get_action(action_id)
	if definition == null:
		return result
	for other: InputActionDef in action_set.actions:
		if other == null or other.id == action_id:
			continue
		if not _co_active(definition.context, other.context):
			continue
		if not InputMap.has_action(other.id):
			continue
		for existing: InputEvent in InputMap.action_get_events(other.id):
			if InputEventCodec.same_binding(existing, event):
				result.append(other.id)
				break
	return result


## Restores [param action_id] to its default bindings. Emits the changed signal.
func reset_action(action_id: StringName) -> void:
	var definition: InputActionDef = action_set.get_action(action_id)
	if definition == null:
		return
	_apply_default(definition)
	_emit_bindings_changed()


## Same as [method apply_defaults].
func reset_all() -> void:
	apply_defaults()


## Writes the remappable bindings to [param path] as a [ConfigFile]. Returns the save result.
func save_to(path: String = DEFAULT_PATH) -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(_SECTION_META, "schema_version", SCHEMA_VERSION)
	config.set_value(_SECTION_META, "action_set", String(action_set.id))
	for definition: InputActionDef in action_set.actions:
		if definition == null or not definition.remappable:
			continue
		_store_device(config, definition.id, Device.GAMEPAD, _SECTION_GAMEPAD)
		_store_device(config, definition.id, Device.KEYBOARD, _SECTION_KEYBOARD)
	return config.save(path)


## Loads bindings from [param path]. Actions and device kinds absent from the file keep their
## current events. Returns [constant ERR_FILE_NOT_FOUND] or [constant ERR_FILE_UNRECOGNIZED]
## without changing anything when the file cannot be used.
func load_from(path: String = DEFAULT_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(path)
	if err != OK:
		return err
	var version_value: Variant = config.get_value(_SECTION_META, "schema_version", null)
	if typeof(version_value) != TYPE_INT:
		return ERR_FILE_UNRECOGNIZED
	var version: int = version_value
	if version > SCHEMA_VERSION:
		return ERR_FILE_UNRECOGNIZED
	# Version 1 is the first schema, so there is nothing to migrate yet.
	for definition: InputActionDef in action_set.actions:
		if definition == null or not definition.remappable:
			continue
		_load_device(config, definition.id, Device.GAMEPAD, _SECTION_GAMEPAD)
		_load_device(config, definition.id, Device.KEYBOARD, _SECTION_KEYBOARD)
	_emit_bindings_changed()
	return OK


func _apply_default(definition: InputActionDef) -> void:
	if not InputMap.has_action(definition.id):
		InputMap.add_action(definition.id, definition.deadzone)
	InputMap.action_set_deadzone(definition.id, definition.deadzone)
	InputMap.action_erase_events(definition.id)
	for event: InputEvent in definition.gamepad_events:
		if event != null:
			InputMap.action_add_event(definition.id, _with_any_device(event))
	for event: InputEvent in definition.keyboard_events:
		if event != null:
			InputMap.action_add_event(definition.id, _with_any_device(event))


func _emit_bindings_changed() -> void:
	var emit_result: Error = EventBusAccess.emit(&"input_bindings_changed")
	if emit_result != OK and emit_result != ERR_UNAVAILABLE:
		push_warning(
			"InputBindings: could not emit input_bindings_changed (%s)" % error_string(emit_result)
		)


func _edit(
	action_id: StringName, device: Device, index: int, event: InputEvent, remove: bool
) -> Error:
	var definition: InputActionDef = action_set.get_action(action_id)
	if definition == null:
		return ERR_DOES_NOT_EXIST
	if not definition.remappable:
		return ERR_UNAVAILABLE
	var device_events: Array[InputEvent] = get_events(action_id, device)
	var count: int = device_events.size()
	var max_index: int = count - 1 if remove else count
	if index < 0 or index > max_index:
		return ERR_INVALID_PARAMETER
	if not remove and not _is_valid_for(event, device):
		return ERR_INVALID_PARAMETER
	var replacement: Array[InputEvent] = []
	for position: int in count:
		replacement.append(device_events[position])
	if remove:
		replacement.remove_at(index)
	elif index == count:
		replacement.append(_with_any_device(event))
	else:
		replacement[index] = _with_any_device(event)
	_replace_device_events(action_id, device, replacement)
	_emit_bindings_changed()
	return OK


func _replace_device_events(
	action_id: StringName, device: Device, replacement: Array[InputEvent]
) -> void:
	var kept: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action_id):
		if InputEventCodec.device_of(event) != device:
			kept.append(event)
	InputMap.action_erase_events(action_id)
	for event: InputEvent in kept:
		InputMap.action_add_event(action_id, event)
	for event: InputEvent in replacement:
		InputMap.action_add_event(action_id, event)


func _store_device(
	config: ConfigFile, action_id: StringName, device: Device, section: String
) -> void:
	var encoded: Array = []
	for event: InputEvent in get_events(action_id, device):
		encoded.append(InputEventCodec.encode(event))
	config.set_value(section, String(action_id), encoded)


func _load_device(
	config: ConfigFile, action_id: StringName, device: Device, section: String
) -> void:
	if not config.has_section_key(section, String(action_id)):
		return
	var raw_value: Variant = config.get_value(section, String(action_id))
	if typeof(raw_value) != TYPE_ARRAY:
		return
	var entries: Array = raw_value
	var decoded: Array[InputEvent] = []
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_data: Dictionary = entry
		var event: InputEvent = InputEventCodec.decode(entry_data)
		if event != null and InputEventCodec.device_of(event) == device:
			decoded.append(event)
	_replace_device_events(action_id, device, decoded)


func _is_valid_for(event: InputEvent, device: Device) -> bool:
	if event == null or InputEventCodec.encode(event).is_empty():
		return false
	return InputEventCodec.device_of(event) == device


func _with_any_device(event: InputEvent) -> InputEvent:
	var copy: InputEvent = event.duplicate() as InputEvent
	copy.device = InputEventCodec.ANY_DEVICE
	return copy


func _co_active(a: InputActionDef.Context, b: InputActionDef.Context) -> bool:
	if a == b:
		return true
	return (
		(a == InputActionDef.Context.MATCH and b == InputActionDef.Context.SYSTEM)
		or (a == InputActionDef.Context.SYSTEM and b == InputActionDef.Context.MATCH)
	)
