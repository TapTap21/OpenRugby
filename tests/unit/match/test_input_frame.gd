class_name TestInputFrame
extends GdUnitTestSuite
## Tests for InputFrame: one tick of quantised controller input (S1-core section 2.2).


## C-05: a new InputFrame(2, 4) has buttons of size 2, axes of size 8, all zero.
func test_c05_new_frame_shape_and_zero() -> void:
	var frame: InputFrame = InputFrame.new(2, 4)
	var total: int = 0
	for value: int in frame.axes:
		total += absi(value)
	for mask: int in frame.buttons:
		total += absi(mask)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(frame.buttons.size()).is_equal(2)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(frame.axes.size()).is_equal(8)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(total).is_equal(0)


## C-06: set_held(1, 5, true) makes is_held(1, 5) true and is_held(0, 5) false.
func test_c06_set_held_is_per_slot() -> void:
	var frame: InputFrame = InputFrame.new(2, 4)
	frame.set_held(1, 5, true)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(frame.is_held(1, 5)).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(frame.is_held(0, 5)).is_false()


## C-07: set_axis clamps to [-127, 127].
func test_c07_set_axis_clamps() -> void:
	var frame: InputFrame = InputFrame.new(1, 2)
	frame.set_axis(0, 1, 300)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(frame.get_axis(0, 1)).is_equal(127)
	frame.set_axis(0, 1, -300)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(frame.get_axis(0, 1)).is_equal(-127)


## C-08: copy_from then equals is true; changing one bit makes equals false.
func test_c08_copy_and_equals() -> void:
	var source: InputFrame = InputFrame.new(2, 4)
	source.tick = 9
	source.set_held(1, 3, true)
	source.set_axis(0, 2, -55)
	var copy: InputFrame = InputFrame.new(2, 4)
	copy.copy_from(source)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(copy.equals(source)).is_true()
	copy.set_held(0, 0, true)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(copy.equals(source)).is_false()
