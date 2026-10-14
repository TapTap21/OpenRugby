class_name TestInputSampler
extends GdUnitTestSuite
## Tests for InputSampler: device state quantised into InputFrame (S9-input section 5, criteria
## I-16 and I-17). InputMap is restored to defaults and pressed actions are released in after_test.

const ACTION_SET_PATH: String = "res://game/platform/input/default_action_set.tres"
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

var _bindings: InputBindings = null
var _set: InputActionSet = null


func before_test() -> void:
	var res: Resource = ResourceLoader.load(ACTION_SET_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_set = res as InputActionSet
	_bindings = InputBindings.new(_set)
	_bindings.apply_defaults()


func after_test() -> void:
	for action_id: StringName in MOVE_ACTIONS:
		Input.action_release(action_id)
	Input.action_release(&"kick")
	if _bindings != null:
		_bindings.reset_all()
	_bindings = null
	_set = null


## I-16: a pressed kick and move_right give bit 3 and axis x 127; releasing both gives zeros.
func test_i16_buttons_and_axis_sampled_then_cleared() -> void:
	var sampler: InputSampler = InputSampler.new(_set, 1)
	Input.action_press(&"kick")
	Input.action_press(&"move_right")
	var frame: InputFrame = _set.make_frame(1)
	@warning_ignore("unused_variable")
	var filled: bool = sampler.fill_frame(7, frame)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(filled).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(frame.tick).is_equal(7)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(frame.buttons[0]).is_equal(1 << 3)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(frame.get_axis(0, 0)).is_equal(127)
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(frame.get_axis(0, 1)).is_equal(0)
	Input.action_release(&"kick")
	Input.action_release(&"move_right")
	@warning_ignore("unused_variable")
	var cleared: bool = sampler.fill_frame(8, frame)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(frame.buttons[0]).is_equal(0)
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(frame.get_axis(0, 0)).is_equal(0)
	@warning_ignore("unused_variable")
	var r8: GdUnitIntAssert = assert_int(frame.get_axis(0, 1)).is_equal(0)


## I-17: diagonal movement is normalised to length 1 and quantised to (-90, -90); the sampler
## layout hash equals the set's.
func test_i17_diagonal_quantised_and_layout_hash() -> void:
	var sampler: InputSampler = InputSampler.new(_set, 1)
	Input.action_press(&"move_left")
	Input.action_press(&"move_up")
	var frame: InputFrame = _set.make_frame(1)
	@warning_ignore("unused_variable")
	var filled: bool = sampler.fill_frame(1, frame)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(frame.get_axis(0, 0)).is_equal(-90)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(frame.get_axis(0, 1)).is_equal(-90)
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(sampler.layout_hash()).is_equal(_set.layout_hash())
