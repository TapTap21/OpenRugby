class_name InputEventCodec
extends RefCounted
## Converts bindable [InputEvent]s to plain dictionaries for persistence, and back.
##
## Supported: keyboard keys (by physical keycode), joypad buttons, joypad axes (sign only) and
## mouse buttons. Decoded events always use device [constant ANY_DEVICE].

## Device value meaning "all devices".
const ANY_DEVICE: int = -1

const TYPE_KEY: String = "key"
const TYPE_JOY_BUTTON: String = "joy_button"
const TYPE_JOY_AXIS: String = "joy_axis"
const TYPE_MOUSE_BUTTON: String = "mouse_button"


## Returns the dictionary form of [param event], or an empty dictionary when unsupported.
static func encode(event: InputEvent) -> Dictionary:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null:
		return {"type": TYPE_KEY, "physical_keycode": key_event.physical_keycode}
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null:
		return {"type": TYPE_JOY_BUTTON, "button_index": button.button_index}
	var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if motion != null:
		var sign_value: float = -1.0 if motion.axis_value < 0.0 else 1.0
		return {"type": TYPE_JOY_AXIS, "axis": motion.axis, "axis_value": sign_value}
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null:
		return {"type": TYPE_MOUSE_BUTTON, "button_index": mouse.button_index}
	return {}


## Returns the event described by [param data], or null when it is invalid or unsupported.
static func decode(data: Dictionary) -> InputEvent:
	var type_value: Variant = data.get("type", null)
	if typeof(type_value) != TYPE_STRING:
		return null
	var type_name: String = type_value
	match type_name:
		TYPE_KEY:
			var keycode_value: Variant = data.get("physical_keycode", null)
			if typeof(keycode_value) != TYPE_INT:
				return null
			var keycode: int = keycode_value
			var key_event: InputEventKey = InputEventKey.new()
			key_event.device = ANY_DEVICE
			key_event.physical_keycode = keycode
			return key_event
		TYPE_JOY_BUTTON:
			var index_value: Variant = data.get("button_index", null)
			if typeof(index_value) != TYPE_INT:
				return null
			var button_index: int = index_value
			var button: InputEventJoypadButton = InputEventJoypadButton.new()
			button.device = ANY_DEVICE
			button.button_index = button_index
			return button
		TYPE_JOY_AXIS:
			var axis_value: Variant = data.get("axis", null)
			var sign_value: Variant = data.get("axis_value", null)
			if typeof(axis_value) != TYPE_INT or typeof(sign_value) != TYPE_FLOAT:
				return null
			var axis: int = axis_value
			var value: float = sign_value
			var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
			motion.device = ANY_DEVICE
			motion.axis = axis
			motion.axis_value = -1.0 if value < 0.0 else 1.0
			return motion
		TYPE_MOUSE_BUTTON:
			var mouse_index: Variant = data.get("button_index", null)
			if typeof(mouse_index) != TYPE_INT:
				return null
			var mouse_button: int = mouse_index
			var mouse: InputEventMouseButton = InputEventMouseButton.new()
			mouse.device = ANY_DEVICE
			mouse.button_index = mouse_button
			return mouse
	return null


## Returns true when [param a] and [param b] are the same supported binding; device is ignored.
static func same_binding(a: InputEvent, b: InputEvent) -> bool:
	var encoded_a: Dictionary = encode(a)
	return not encoded_a.is_empty() and encoded_a == encode(b)


## Returns the [enum InputBindings.Device] kind of [param event], or [constant ANY_DEVICE].
static func device_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return InputBindings.Device.KEYBOARD
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return InputBindings.Device.GAMEPAD
	return ANY_DEVICE
