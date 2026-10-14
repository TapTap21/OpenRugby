class_name TestInputBindings
extends GdUnitTestSuite
## Tests for InputBindings: defaults into InputMap, rebinding, conflicts, reset and persistence
## (S9-input section 4, criteria I-08 to I-15, I-19). Tests never touch DEFAULT_PATH; files go to
## user://s1_tests. InputMap is restored to defaults in after_test.

const ACTION_SET_PATH: String = "res://game/platform/input/default_action_set.tres"
const TMP_DIR: String = "user://s1_tests"
const CHANGED_TEST_ID: String = "test-harness"
const LOCKED_ACTION: StringName = &"locked_test_action"

var _bindings: InputBindings = null
var _changed_hits: Array[int] = []
var _changed_callable: Callable = Callable()


func before_test() -> void:
	_changed_hits.clear()
	_changed_callable = Callable(self, "_on_bindings_changed")


func after_test() -> void:
	if EventBus.input_bindings_changed.is_connected(_changed_callable):
		EventBus.input_bindings_changed.disconnect(_changed_callable)
	if InputMap.has_action(LOCKED_ACTION):
		InputMap.erase_action(LOCKED_ACTION)
	if _bindings != null:
		_bindings.reset_all()
	_bindings = null


func _on_bindings_changed() -> void:
	@warning_ignore("return_value_discarded")
	_changed_hits.append(1)


func _fresh_set() -> InputActionSet:
	var res: Resource = ResourceLoader.load(ACTION_SET_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as InputActionSet


## Creates bindings over a fresh default set and applies the defaults.
func _defaults() -> InputBindings:
	_bindings = InputBindings.new(_fresh_set())
	_bindings.apply_defaults()
	return _bindings


func _key(keycode: Key) -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = keycode
	key.device = -1
	return key


func _joy_button(index: JoyButton) -> InputEventJoypadButton:
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = index
	button.device = -1
	return button


func _ensure_tmp_dir() -> void:
	@warning_ignore("unused_variable")
	var made: Error = DirAccess.make_dir_recursive_absolute(TMP_DIR)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		@warning_ignore("unused_variable")
		var removed: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## I-08: apply_defaults puts all 17 actions in InputMap and the default gamepad button for kick.
func test_i08_apply_defaults_fills_input_map() -> void:
	var bindings: InputBindings = _defaults()
	var missing: Array[String] = []
	for action: InputActionDef in bindings.action_set.actions:
		if not InputMap.has_action(action.id):
			@warning_ignore("return_value_discarded")
			missing.append(String(action.id))
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(missing).is_empty()
	var kick_pads: Array[InputEvent] = bindings.get_events(&"kick", InputBindings.Device.GAMEPAD)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(kick_pads.size()).is_equal(1)
	if kick_pads.size() == 1:
		var button: InputEventJoypadButton = kick_pads[0] as InputEventJoypadButton
		@warning_ignore("unused_variable")
		var r3: GdUnitBoolAssert = (
			assert_bool(button != null and button.button_index == JOY_BUTTON_Y).is_true()
		)


## I-09: rebinding kick to P succeeds, replaces K, and emits input_bindings_changed.
func test_i09_rebind_replaces_and_emits() -> void:
	var bindings: InputBindings = _defaults()
	@warning_ignore("unused_variable")
	var connected: Error = EventBus.input_bindings_changed.connect(_changed_callable)
	var result: Error = bindings.rebind(&"kick", InputBindings.Device.KEYBOARD, 0, _key(KEY_P))
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(result).is_equal(OK)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_P))).is_true()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_K))).is_false()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(_changed_hits).is_equal([1])


## I-10: rebind errors are reported with the documented codes.
func test_i10_rebind_error_codes() -> void:
	var bindings: InputBindings = _defaults()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = (
		assert_int(
			bindings.rebind(&"no_such_action", InputBindings.Device.KEYBOARD, 0, _key(KEY_P))
		)
		. is_equal(ERR_DOES_NOT_EXIST)
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = (
		assert_int(
			bindings.rebind(&"kick", InputBindings.Device.KEYBOARD, 0, _joy_button(JOY_BUTTON_A))
		)
		. is_equal(ERR_INVALID_PARAMETER)
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = (
		assert_int(bindings.rebind(&"kick", InputBindings.Device.KEYBOARD, 5, _key(KEY_P)))
		. is_equal(ERR_INVALID_PARAMETER)
	)

	var locked_set: InputActionSet = InputActionSet.new()
	var locked: InputActionDef = InputActionDef.new()
	locked.id = LOCKED_ACTION
	locked.display_name_key = "INPUT_ACTION_LOCKED_TEST_ACTION"
	locked.remappable = false
	@warning_ignore("return_value_discarded")
	locked.keyboard_events.append(_key(KEY_L))
	@warning_ignore("return_value_discarded")
	locked_set.actions.append(locked)
	var locked_bindings: InputBindings = InputBindings.new(locked_set)
	locked_bindings.apply_defaults()
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = (
		assert_int(
			locked_bindings.rebind(LOCKED_ACTION, InputBindings.Device.KEYBOARD, 0, _key(KEY_P))
		)
		. is_equal(ERR_UNAVAILABLE)
	)


## I-11: find_conflicts reports co-active actions only.
func test_i11_find_conflicts_respects_contexts() -> void:
	var bindings: InputBindings = _defaults()
	var on_j: Array[StringName] = bindings.find_conflicts(&"kick", _key(KEY_J))
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(on_j).is_equal([&"tackle"])
	var cancel_escape: Array[StringName] = bindings.find_conflicts(&"ui_cancel", _key(KEY_ESCAPE))
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(cancel_escape.has(&"pause")).is_false()
	var kick_escape: Array[StringName] = bindings.find_conflicts(&"kick", _key(KEY_ESCAPE))
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(kick_escape.has(&"pause")).is_true()


## I-12: reset_action after a rebind restores exactly the defaults.
func test_i12_reset_action_restores_defaults() -> void:
	var bindings: InputBindings = _defaults()
	@warning_ignore("unused_variable")
	var rebound: Error = bindings.rebind(&"kick", InputBindings.Device.KEYBOARD, 0, _key(KEY_P))
	bindings.reset_action(&"kick")
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_K))).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_P))).is_false()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = (
		assert_int(bindings.get_events(&"kick", InputBindings.Device.KEYBOARD).size()).is_equal(1)
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = (
		assert_int(bindings.get_events(&"kick", InputBindings.Device.GAMEPAD).size()).is_equal(1)
	)


## I-13: rebinds survive save_to, reset_all and load_from; other actions stay at defaults.
func test_i13_save_reset_and_load_restores_rebinds() -> void:
	_ensure_tmp_dir()
	var path: String = TMP_DIR + "/i13_bindings.cfg"
	_remove(path)
	var bindings: InputBindings = _defaults()
	@warning_ignore("unused_variable")
	var r1_err: Error = bindings.rebind(&"kick", InputBindings.Device.KEYBOARD, 0, _key(KEY_P))
	@warning_ignore("unused_variable")
	var r2_err: Error = bindings.rebind(&"pass_left", InputBindings.Device.KEYBOARD, 0, _key(KEY_Z))
	@warning_ignore("unused_variable")
	var saved: Error = bindings.save_to(path)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(saved).is_equal(OK)
	bindings.reset_all()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_K))).is_true()
	)
	@warning_ignore("unused_variable")
	var loaded: Error = bindings.load_from(path)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(loaded).is_equal(OK)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_P))).is_true()
	)
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_K))).is_false()
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"pass_left", _key(KEY_Z))).is_true()
	)
	@warning_ignore("unused_variable")
	var r7: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"sprint", _key(KEY_SHIFT))).is_true()
	)
	var file: ConfigFile = ConfigFile.new()
	@warning_ignore("unused_variable")
	var file_error: Error = file.load(path)
	@warning_ignore("unused_variable")
	var r8: GdUnitIntAssert = assert_int(file.get_value("meta", "schema_version", -1)).is_equal(1)
	_remove(path)


## I-14: a missing file and a newer schema both leave the bindings unchanged.
func test_i14_load_errors_leave_bindings_unchanged() -> void:
	_ensure_tmp_dir()
	var bindings: InputBindings = _defaults()
	var missing_path: String = TMP_DIR + "/i14_missing.cfg"
	_remove(missing_path)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(bindings.load_from(missing_path)).is_equal(
		ERR_FILE_NOT_FOUND
	)
	var future_path: String = TMP_DIR + "/i14_future.cfg"
	var future: ConfigFile = ConfigFile.new()
	future.set_value("meta", "schema_version", 2)
	future.set_value("keyboard", "kick", [{"type": "key", "physical_keycode": KEY_P}])
	@warning_ignore("unused_variable")
	var written: Error = future.save(future_path)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(bindings.load_from(future_path)).is_equal(
		ERR_FILE_UNRECOGNIZED
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_K))).is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_P))).is_false()
	)
	_remove(future_path)


## I-15: unknown action ids and invalid event entries in the file are ignored.
func test_i15_load_ignores_unknown_and_invalid_entries() -> void:
	_ensure_tmp_dir()
	var path: String = TMP_DIR + "/i15_entries.cfg"
	var file: ConfigFile = ConfigFile.new()
	file.set_value("meta", "schema_version", 1)
	(
		file
		. set_value(
			"keyboard",
			"kick",
			[{"type": "key", "physical_keycode": KEY_P}, {"type": "nope"}],
		)
	)
	file.set_value("keyboard", "ghost_action", [{"type": "key", "physical_keycode": KEY_Z}])
	@warning_ignore("unused_variable")
	var written: Error = file.save(path)
	var bindings: InputBindings = _defaults()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(bindings.load_from(path)).is_equal(OK)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = (
		assert_int(bindings.get_events(&"kick", InputBindings.Device.KEYBOARD).size()).is_equal(1)
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(InputMap.action_has_event(&"kick", _key(KEY_P))).is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(InputMap.has_action(&"ghost_action")).is_false()
	_remove(path)


## I-19: GameSettings builds input_bindings at startup and the kick action exists in InputMap.
func test_i19_game_settings_owns_bindings() -> void:
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(GameSettings.input_bindings).is_not_null()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(InputMap.has_action(&"kick")).is_true()
