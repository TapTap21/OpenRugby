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
		log.append(_frame(index))
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


## C-29: append with a wrong-shaped frame is ignored.
func test_c29_wrong_shape_frame_is_ignored() -> void:
	var log: InputLog = InputLog.new(_header())
	@warning_ignore("return_value_discarded")
	log.append(InputFrame.new(SLOT_COUNT + 1, AXES_PER_SLOT))
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(0)


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
