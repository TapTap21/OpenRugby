class_name TestInputLog
extends GdUnitTestSuite
## Tests for ReplayHeader and InputLog serialisation (S1-core section 3.2, criteria C-28 to C-30).

const TMP_DIR: String = "user://s1_tests"
const SLOT_COUNT: int = 2
const AXES_PER_SLOT: int = 4
const FRAME_COUNT: int = 3


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
	var left: Dictionary = {"unused": [nan_value, {"axis": NAN}]}
	var right: Dictionary = {"unused": [nan_value, {"axis": NAN}]}
	@warning_ignore("unused_variable")
	var equal_nan: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal(left, right)).is_true()
	)
	@warning_ignore("unused_variable")
	var different_numeric_type: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal({"value": 1}, {"value": 1.0})).is_false()
	)
	@warning_ignore("unused_variable")
	var different_array_order: GdUnitBoolAssert = (
		assert_bool(InputLog._exact_value_equal([1, 2], [2, 1])).is_false()
	)


func test_fixture_append_cannot_finalize_a_sim_tick() -> void:
	var sim: MatchSim = MatchSim.new(MatchConfig.create_default())
	var tick_result: TickResult = sim.tick_checked(_frame(0))
	var log: InputLog = InputLog.new(_header())
	@warning_ignore("unused_variable")
	var append_error: Error = log.append_fixture_row(_frame(0))
	var finalize_error: Error = sim.finalize_prepared_tick(
		tick_result.prepared_tick, PreparedAppendToken.new()
	)
	@warning_ignore("unused_variable")
	var finalize_assertion: GdUnitIntAssert = assert_int(finalize_error).is_equal(
		ERR_INVALID_PARAMETER
	)
	@warning_ignore("unused_variable")
	var tick_still_prepared: GdUnitBoolAssert = (
		assert_bool(tick_result.prepared_tick._active).is_true()
	)
	var visible_rows_before_commit: int = log.frame_count()
	var inert_commit_error: Error = log.commit_append(PreparedAppendToken.new())
	@warning_ignore("unused_variable")
	var commit_assertion: GdUnitIntAssert = assert_int(inert_commit_error).is_equal(
		ERR_INVALID_PARAMETER
	)
	@warning_ignore("unused_variable")
	var invalid_commit_did_not_publish: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(
		visible_rows_before_commit
	)
	@warning_ignore("return_value_discarded")
	sim.abort_prepared_tick(tick_result.prepared_tick)


func test_finalized_commit_only_publishes_the_sealed_row() -> void:
	var log: InputLog = InputLog.new(_header())
	var token: PreparedAppendToken = PreparedAppendToken.new()
	var owner: RefCounted = RefCounted.new()
	# This private fixture represents the reservation after its deep prepare-time proof.
	log._reservation["token"] = token
	log._reservation["active"] = true
	log._reservation["sealed"] = true
	log._reservation["sim"] = owner
	log._reservation["finalized_by"] = owner
	log._reservation["index"] = 0
	var commit_error: Error = log.commit_append(token)
	@warning_ignore("unused_variable")
	var committed: GdUnitIntAssert = assert_int(commit_error).is_equal(OK)
	@warning_ignore("unused_variable")
	var row_published: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(1)
	@warning_ignore("unused_variable")
	var reservation_cleared: GdUnitBoolAssert = assert_bool(log._reservation.is_empty()).is_true()


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
