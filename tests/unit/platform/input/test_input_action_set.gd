class_name TestInputActionSet
extends GdUnitTestSuite
## Tests for the default action set resource and InputActionSet rules (S9-input sections 2 and
## 2.1, criteria I-01 to I-06).

const ACTION_SET_PATH: String = "res://game/platform/input/default_action_set.tres"
const TRANSLATIONS_PATH: String = "res://localization/translations.csv"


func _fresh_set() -> InputActionSet:
	var res: Resource = ResourceLoader.load(ACTION_SET_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as InputActionSet


func _action(action_id: StringName, context: InputActionDef.Context) -> InputActionDef:
	var action: InputActionDef = InputActionDef.new()
	action.id = action_id
	action.context = context
	action.display_name_key = "INPUT_ACTION_" + String(action_id).to_upper()
	return action


## I-01: the default action set loads, validates, and has the observed mapped action contexts.
func test_i01_default_set_loads_with_expected_actions() -> void:
	var action_set: InputActionSet = _fresh_set()
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(action_set).is_not_null()
	if action_set == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(action_set.validate().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(action_set.actions.size()).is_equal(20)
	var expected: Dictionary = {
		"move_up": InputActionDef.Context.MATCH,
		"move_down": InputActionDef.Context.MATCH,
		"move_left": InputActionDef.Context.MATCH,
		"move_right": InputActionDef.Context.MATCH,
		"sprint": InputActionDef.Context.MATCH,
		"pass_left": InputActionDef.Context.MATCH,
		"pass_right": InputActionDef.Context.MATCH,
		"kick": InputActionDef.Context.MATCH,
		"tackle": InputActionDef.Context.MATCH,
		"switch_player": InputActionDef.Context.MATCH,
		"kick_up_and_under": InputActionDef.Context.MATCH,
		"kick_grubber": InputActionDef.Context.MATCH,
		"drop_kick": InputActionDef.Context.MATCH,
		"pause": InputActionDef.Context.SYSTEM,
		"ui_accept": InputActionDef.Context.UI,
		"ui_cancel": InputActionDef.Context.UI,
		"ui_up": InputActionDef.Context.UI,
		"ui_down": InputActionDef.Context.UI,
		"ui_left": InputActionDef.Context.UI,
		"ui_right": InputActionDef.Context.UI,
	}
	var mismatches: Array[String] = []
	for action_name: String in expected.keys():
		var action: InputActionDef = action_set.get_action(StringName(action_name))
		if action == null:
			@warning_ignore("return_value_discarded")
			mismatches.append("missing " + action_name)
			continue
		if action.context != expected[action_name]:
			@warning_ignore("return_value_discarded")
			mismatches.append("context " + action_name)
		if action.display_name_key != "INPUT_ACTION_" + action_name.to_upper():
			@warning_ignore("return_value_discarded")
			mismatches.append("key " + action_name)
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(mismatches).is_empty()


## I-02: every default action has a gamepad and a keyboard binding, and its display key exists
## in translations.csv.
func test_i02_defaults_bound_and_keys_translated() -> void:
	var action_set: InputActionSet = _fresh_set()
	var known_keys: Dictionary = {}
	var csv_lines: PackedStringArray = FileAccess.get_file_as_string(TRANSLATIONS_PATH).split("\n")
	for line: String in csv_lines:
		known_keys[line.get_slice(",", 0).strip_edges()] = true
	var problems: Array[String] = []
	for action: InputActionDef in action_set.actions:
		if action.gamepad_events.is_empty():
			@warning_ignore("return_value_discarded")
			problems.append("no gamepad " + String(action.id))
		if action.keyboard_events.is_empty():
			@warning_ignore("return_value_discarded")
			problems.append("no keyboard " + String(action.id))
		if not known_keys.has(action.display_name_key):
			@warning_ignore("return_value_discarded")
			problems.append("untranslated " + action.display_name_key)
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(problems).is_empty()


## I-03: button bits, axes and axis indices of the default action_set.
func test_i03_button_bits_and_axes() -> void:
	var action_set: InputActionSet = _fresh_set()
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = (
		assert_array(action_set.button_actions())
		. is_equal(
			[
				&"sprint",
				&"pass_left",
				&"pass_right",
				&"kick",
				&"tackle",
				&"switch_player",
				&"kick_up_and_under",
				&"kick_grubber",
				&"drop_kick",
			]
		)
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(action_set.bit_of(&"kick")).is_equal(3)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(action_set.bit_of(&"move_up")).is_equal(-1)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(action_set.bit_of(&"pause")).is_equal(-1)
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(action_set.axes_per_slot()).is_equal(2)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(action_set.axis_index(&"move", 1)).is_equal(1)


## I-04: layout_hash is SHA-256 of the defined text, changes when two button actions swap order,
## and is stable across two loads.
func test_i04_layout_hash_matches_definition() -> void:
	var action_set: InputActionSet = _fresh_set()
	var lines: Array[String] = []
	for button_id: StringName in action_set.button_actions():
		@warning_ignore("return_value_discarded")
		lines.append("button:" + String(button_id))
	@warning_ignore("return_value_discarded")
	lines.append("axis:move:move_left,move_right,move_up,move_down")
	var expected_text: String = "\n".join(lines)
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(action_set.layout_hash()).is_equal(
		expected_text.sha256_text()
	)

	var swapped: InputActionSet = _fresh_set()
	var first: InputActionDef = swapped.actions[4]
	swapped.actions[4] = swapped.actions[5]
	swapped.actions[5] = first
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(swapped.layout_hash() != action_set.layout_hash()).is_true()
	)

	var second_load: InputActionSet = _fresh_set()
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(second_load.layout_hash()).is_equal(
		action_set.layout_hash()
	)


## I-05: a duplicate action id is reported.
func test_i05_duplicate_action_id_reported() -> void:
	var action_set: InputActionSet = InputActionSet.new()
	@warning_ignore("return_value_discarded")
	action_set.actions.append(_action(&"dup", InputActionDef.Context.MATCH))
	@warning_ignore("return_value_discarded")
	action_set.actions.append(_action(&"dup", InputActionDef.Context.MATCH))
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(action_set.validate().size() > 0).is_true()


## I-05: an axis naming an unknown action is reported.
func test_i05_axis_with_unknown_action_reported() -> void:
	var action_set: InputActionSet = InputActionSet.new()
	@warning_ignore("return_value_discarded")
	action_set.actions.append(_action(&"kick", InputActionDef.Context.MATCH))
	var axis: InputAxisDef = InputAxisDef.new()
	axis.id = &"move"
	axis.negative_x = &"ghost"
	axis.positive_x = &"kick"
	axis.negative_y = &"kick"
	axis.positive_y = &"kick"
	@warning_ignore("return_value_discarded")
	action_set.axes.append(axis)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(action_set.validate().size() > 0).is_true()


## I-05: an axis naming a UI action is reported.
func test_i05_axis_with_ui_action_reported() -> void:
	var action_set: InputActionSet = InputActionSet.new()
	@warning_ignore("return_value_discarded")
	action_set.actions.append(_action(&"ui_up", InputActionDef.Context.UI))
	@warning_ignore("return_value_discarded")
	action_set.actions.append(_action(&"kick", InputActionDef.Context.MATCH))
	var axis: InputAxisDef = InputAxisDef.new()
	axis.id = &"menu"
	axis.negative_x = &"ui_up"
	axis.positive_x = &"ui_up"
	axis.negative_y = &"ui_up"
	axis.positive_y = &"ui_up"
	@warning_ignore("return_value_discarded")
	action_set.axes.append(axis)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(action_set.validate().size() > 0).is_true()


## I-06: make_frame(3) has three slots and two axes per slot.
func test_i06_make_frame_shape() -> void:
	var action_set: InputActionSet = _fresh_set()
	var frame: InputFrame = action_set.make_frame(3)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(frame.slot_count).is_equal(3)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(frame.axes_per_slot).is_equal(2)
