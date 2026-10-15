class_name TestInputLog
extends GdUnitTestSuite
## Tests for ReplayHeader and InputLog serialisation (S1-core section 3.2, criteria C-28 to C-30).

const TMP_DIR: String = "user://s1_tests"
const SLOT_COUNT: int = 2
const AXES_PER_SLOT: int = 4
const FRAME_COUNT: int = 3

var _published_signal_count: int = 0


func _header() -> ReplayHeader:
	var header: ReplayHeader = ReplayHeader.new()
	header.game_version = "0.1.0"
	header.seed = 12345
	header.mod_set_hash = "mods-hash"
	header.action_layout_hash = "layout-hash"
	header.slot_count = SLOT_COUNT
	header.axes_per_slot = AXES_PER_SLOT
	return header


func _frame(index: int) -> InputFrame:
	var frame: InputFrame = InputFrame.new(SLOT_COUNT, AXES_PER_SLOT)
	frame.tick = index
	frame.set_held(0, index + 1, true)
	frame.set_held(1, 2, true)
	frame.set_axis(0, 1, 10 * index)
	frame.set_axis(1, 3, -20 - index)
	return frame


func _filled_log() -> InputLog:
	var log: InputLog = InputLog.new(_header())
	for index: int in range(FRAME_COUNT):
		@warning_ignore("return_value_discarded")
		log.append_fixture_row(_frame(index))
	return log


## C-28: to_bytes/from_bytes keeps the header fields and every frame.
func test_c28_bytes_round_trip_keeps_header_and_frames() -> void:
	var original: InputLog = _filled_log()
	var restored: InputLog = InputLog.from_bytes(original.to_bytes())
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(restored).is_not_null()
	if restored == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(restored.header.game_version).is_equal("0.1.0")
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(restored.header.seed).is_equal(12345)
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(restored.header.mod_set_hash).is_equal("mods-hash")
	@warning_ignore("unused_variable")
	var r5: GdUnitStringAssert = assert_str(restored.header.action_layout_hash).is_equal(
		"layout-hash"
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(restored.header.slot_count).is_equal(SLOT_COUNT)
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(restored.header.axes_per_slot).is_equal(AXES_PER_SLOT)
	@warning_ignore("unused_variable")
	var r8: GdUnitIntAssert = assert_int(restored.frame_count()).is_equal(FRAME_COUNT)
	var frames_match: bool = true
	var read_back: InputFrame = InputFrame.new(SLOT_COUNT, AXES_PER_SLOT)
	for index: int in range(FRAME_COUNT):
		@warning_ignore("unused_variable")
		var read_ok: bool = restored.read_frame(index, read_back)
		if not read_back.equals(_frame(index)):
			frames_match = false
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(frames_match).is_true()


## C-28: save and load_file (user://) keep the header and frames.
func test_c28_save_and_load_file_round_trip() -> void:
	@warning_ignore("unused_variable")
	var made: Error = DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path: String = TMP_DIR + "/c28_input_log.bin"
	var original: InputLog = _filled_log()
	@warning_ignore("unused_variable")
	var save_result: Error = original.save(path)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(save_result).is_equal(OK)
	var loaded: InputLog = InputLog.load_file(path)
	@warning_ignore("unused_variable")
	var r2: GdUnitObjectAssert = assert_object(loaded).is_not_null()
	if loaded != null:
		@warning_ignore("unused_variable")
		var r3: GdUnitIntAssert = assert_int(loaded.header.seed).is_equal(12345)
		@warning_ignore("unused_variable")
		var r4: GdUnitIntAssert = assert_int(loaded.frame_count()).is_equal(FRAME_COUNT)
	@warning_ignore("unused_variable")
	var removed: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## C-29: fixture append with a wrong-shaped frame is rejected.
func test_c29_wrong_shape_frame_is_ignored() -> void:
	var log: InputLog = InputLog.new(_header())
	var append_error: Error = log.append_fixture_row(InputFrame.new(SLOT_COUNT + 1, AXES_PER_SLOT))
	@warning_ignore("unused_variable")
	var append_result: GdUnitIntAssert = assert_int(append_error).is_equal(ERR_INVALID_PARAMETER)
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(0)


func test_fixture_row_readers_return_detached_copies() -> void:
	var log: InputLog = InputLog.new(_header())
	var frame: InputFrame = _frame(0)
	var commands: Array[Dictionary] = [{"nested": [1, 2]}]
	var outputs: Array[Dictionary] = [{"value": 3}]
	@warning_ignore("unused_variable")
	var appended: Error = log.append_fixture_row(frame, commands, outputs)
	var command_copy: Array[Dictionary] = log.frame_commands(0)
	var output_copy: Array[Dictionary] = log.frame_outputs(0)
	command_copy[0]["nested"].append(9)
	output_copy[0]["value"] = 7
	var stored_commands: Array = log.frame_commands(0)[0]["nested"]
	@warning_ignore("unused_variable")
	var commands_unchanged: GdUnitArrayAssert = assert_array(stored_commands).is_equal([1, 2])
	@warning_ignore("unused_variable")
	var outputs_unchanged: GdUnitIntAssert = assert_int(log.frame_outputs(0)[0]["value"]).is_equal(
		3
	)
	@warning_ignore("unused_variable")
	var stale_row: GdUnitArrayAssert = assert_array(log.frame_outputs(1)).is_empty()


func test_recursive_exact_row_equality_treats_nan_as_equal() -> void:
	var nan_value: float = NAN
	var nan_vector2: Vector2 = Vector2(NAN, NAN)
	var nan_vector3: Vector3 = Vector3(NAN, NAN, NAN)
	var nan_vector4: Vector4 = Vector4(NAN, NAN, NAN, NAN)
	var nan_color: Color = Color(NAN, NAN, NAN, NAN)
	var nan_basis: Basis = Basis(nan_vector3, nan_vector3, nan_vector3)
	var nan_values: Array[Variant] = [
		nan_value,
		nan_vector2,
		nan_vector3,
		nan_vector4,
		Rect2(nan_vector2, nan_vector2),
		Transform2D(nan_vector2, nan_vector2, nan_vector2),
		Plane(nan_vector3, NAN),
		Quaternion(NAN, NAN, NAN, NAN),
		AABB(nan_vector3, nan_vector3),
		nan_basis,
		Transform3D(nan_basis, nan_vector3),
		Projection(nan_vector4, nan_vector4, nan_vector4, nan_vector4),
		nan_color,
		PackedFloat32Array([NAN]),
		PackedFloat64Array([NAN]),
		PackedVector2Array([nan_vector2]),
		PackedVector3Array([nan_vector3]),
		PackedVector4Array([nan_vector4]),
		PackedColorArray([nan_color]),
	]
	var changed_values: Array[Variant] = [
		1.0,
		Vector2(0.0, NAN),
		Vector3(0.0, NAN, NAN),
		Vector4(0.0, NAN, NAN, NAN),
		Rect2(Vector2(0.0, NAN), nan_vector2),
		Transform2D(Vector2(0.0, NAN), nan_vector2, nan_vector2),
		Plane(Vector3(0.0, NAN, NAN), NAN),
		Quaternion(0.0, NAN, NAN, NAN),
		AABB(Vector3(0.0, NAN, NAN), nan_vector3),
		Basis(Vector3(0.0, NAN, NAN), nan_vector3, nan_vector3),
		Transform3D(nan_basis, Vector3(0.0, NAN, NAN)),
		Projection(Vector4(0.0, NAN, NAN, NAN), nan_vector4, nan_vector4, nan_vector4),
		Color(0.0, NAN, NAN, NAN),
		PackedFloat32Array([0.0]),
		PackedFloat64Array([0.0]),
		PackedVector2Array([Vector2(0.0, NAN)]),
		PackedVector3Array([Vector3(0.0, NAN, NAN)]),
		PackedVector4Array([Vector4(0.0, NAN, NAN, NAN)]),
		PackedColorArray([Color(0.0, NAN, NAN, NAN)]),
	]
	var families_are_exact: bool = true
	for index: int in range(nan_values.size()):
		families_are_exact = (
			families_are_exact
			and InputLog._supports_row_value(nan_values[index])
			and InputLog._exact_value_equal(nan_values[index], nan_values[index])
			and not InputLog._exact_value_equal(nan_values[index], changed_values[index])
		)
	@warning_ignore("unused_variable")
	var every_family_checked: GdUnitBoolAssert = assert_bool(families_are_exact).is_true()
	var nested_left: Dictionary = {"nested": [nan_values]}
	var nested_right: Dictionary = {"nested": [nan_values.duplicate()]}
	@warning_ignore("unused_variable")
	var nested_nan_equal: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal(nested_left, nested_right)).is_true()
	)
	@warning_ignore("unused_variable")
	var different_numeric_type: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal({"value": 1}, {"value": 1.0})).is_false()
	)
	@warning_ignore("unused_variable")
	var math_type_mismatch: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal(Vector2(1.0, 2.0), Vector2i(1, 2))).is_false()
	)
	@warning_ignore("unused_variable")
	var different_array_order: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal([1, 2], [2, 1])).is_false()
	)
	var nan_key: Dictionary = {}
	nan_key[NAN] = "value"
	@warning_ignore("unused_variable")
	var nan_key_rejected: GdUnitBoolAssert = (
		assert_bool(InputLog._supports_row_value(nan_key)).is_false()
	)


func test_fixture_append_cannot_finalize_a_sim_tick() -> void:
	var sim: MatchSim = MatchSim.new(MatchConfig.create_default())
	@warning_ignore("unused_variable")
	var ownership_claim: GdUnitIntAssert = assert_int(sim.claim_runner_ownership()).is_equal(OK)
	sim.state_changed.connect(_on_test_state_changed)
	sim.period_started.connect(_on_test_period_signal)
	sim.period_ended.connect(_on_test_period_signal)
	sim.finished.connect(_on_test_finished)
	_published_signal_count = 0
	var tick_result: TickResult = sim.tick_checked(_frame(0))
	@warning_ignore("unused_variable")
	var prepared_tick: GdUnitBoolAssert = (
		assert_bool(tick_result.status == TickResult.Status.PREPARED).is_true()
	)
	var log: InputLog = InputLog.new(_header())
	@warning_ignore("unused_variable")
	var append_error: Error = log.append_fixture_row(_frame(0))
	@warning_ignore("unused_variable")
	var fixture_append_succeeded: GdUnitIntAssert = assert_int(append_error).is_equal(OK)
	var post_fixture_row_count: int = log.frame_count()
	sim.finalize_prepared_tick(tick_result.prepared_tick, PreparedAppendToken.new())
	@warning_ignore("unused_variable")
	var tick_still_prepared: GdUnitBoolAssert = (
		assert_bool(tick_result.prepared_tick._active).is_true()
	)
	var inert_commit_error: Error = log.commit_append(PreparedAppendToken.new())
	@warning_ignore("unused_variable")
	var commit_assertion: GdUnitIntAssert = assert_int(inert_commit_error).is_equal(
		ERR_INVALID_PARAMETER
	)
	@warning_ignore("unused_variable")
	var invalid_commit_did_not_publish: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(
		post_fixture_row_count
	)
	@warning_ignore("unused_variable")
	var fixture_row_is_baseline: GdUnitIntAssert = assert_int(post_fixture_row_count).is_equal(1)
	@warning_ignore("unused_variable")
	var no_staged_signal_published: GdUnitIntAssert = assert_int(_published_signal_count).is_equal(
		0
	)
	@warning_ignore("return_value_discarded")
	sim.abort_prepared_tick(tick_result.prepared_tick)


func test_append_prepare_result_factories_have_closed_shapes() -> void:
	var token: PreparedAppendToken = PreparedAppendToken.new()
	var prepared: AppendPrepareResult = AppendPrepareResult.prepared(token)
	assert_bool(prepared.ok).is_true()
	assert_bool(prepared.token == token).is_true()
	assert_int(prepared.error).is_equal(OK)
	var null_prepared: AppendPrepareResult = AppendPrepareResult.prepared(null)
	assert_bool(null_prepared.ok).is_false()
	assert_object(null_prepared.token).is_null()
	assert_int(null_prepared.error).is_equal(ERR_INVALID_PARAMETER)
	var failed: AppendPrepareResult = AppendPrepareResult.failed(ERR_INVALID_DATA)
	assert_bool(failed.ok).is_false()
	assert_object(failed.token).is_null()
	assert_int(failed.error).is_equal(ERR_INVALID_DATA)
	var normalized_failure: AppendPrepareResult = AppendPrepareResult.failed(OK)
	assert_bool(normalized_failure.ok).is_false()
	assert_object(normalized_failure.token).is_null()
	assert_int(normalized_failure.error).is_equal(ERR_INVALID_PARAMETER)


func _on_test_state_changed(_from_state: StringName, _to_state: StringName) -> void:
	_published_signal_count += 1


func _on_test_period_signal(_period: int) -> void:
	_published_signal_count += 1


func _on_test_finished() -> void:
	_published_signal_count += 1


## C-30: from_bytes returns null for garbage bytes.
func test_c30_garbage_bytes_give_null() -> void:
	var garbage: PackedByteArray = PackedByteArray([7, 1, 255, 0, 42, 9, 9, 9])
	@warning_ignore("unused_variable")
	var result: GdUnitObjectAssert = assert_object(InputLog.from_bytes(garbage)).is_null()


## C-30: from_bytes returns null for a header whose format_version is newer than supported.
func test_c30_newer_format_version_gives_null() -> void:
	var header: ReplayHeader = _header()
	header.format_version = InputLog.FORMAT_VERSION + 1
	var log: InputLog = InputLog.new(header)
	@warning_ignore("unused_variable")
	var result: GdUnitObjectAssert = assert_object(InputLog.from_bytes(log.to_bytes())).is_null()
