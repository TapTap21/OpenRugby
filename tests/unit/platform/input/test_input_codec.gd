class_name TestInputCodec
extends GdUnitTestSuite
## Tests for InputEventCodec: encode/decode of supported event types (S9-input section 3,
## criterion I-07).


func _round_trip_ok(event: InputEvent) -> bool:
	var data: Dictionary = InputEventCodec.encode(event)
	var decoded: InputEvent = InputEventCodec.decode(data)
	if decoded == null:
		return false
	return InputEventCodec.same_binding(event, decoded) and decoded.device == -1


## I-07: key, joy button, joy axis and mouse button round-trip to a same_binding event with
## device -1; mouse motion encodes to {}; an unknown type decodes to null.
func test_i07_codec_round_trip_and_rejections() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_P
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_Y
	var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_X
	axis.axis_value = -1.0
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(_round_trip_ok(key)).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(_round_trip_ok(button)).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(_round_trip_ok(axis)).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(_round_trip_ok(mouse)).is_true()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	@warning_ignore("unused_variable")
	var r5: GdUnitDictionaryAssert = assert_dict(InputEventCodec.encode(motion)).is_empty()
	@warning_ignore("unused_variable")
	var r6: GdUnitObjectAssert = assert_object(InputEventCodec.decode({"type": "nope"})).is_null()
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(InputEventCodec.device_of(key)).is_equal(
		InputBindings.Device.KEYBOARD
	)
	@warning_ignore("unused_variable")
	var r8: GdUnitIntAssert = assert_int(InputEventCodec.device_of(button)).is_equal(
		InputBindings.Device.GAMEPAD
	)
