class_name TestPitchGeometry
extends GdUnitTestSuite
## Tests for PitchGeometry: field dimensions and line/zone queries (S1-core section 4,
## criteria C-35 to C-37).

const DEFAULT_PITCH_PATH: String = "res://game/match/pitch/default_pitch.tres"

## Expected defaults of section 4, field name to value.
const EXPECTED_DEFAULTS: Dictionary = {
	"field_length": 100.0,
	"field_width": 67.4,
	"in_goal_depth": 14.1,
	"line_22_from_try": 22.0,
	"line_10_from_halfway": 10.0,
	"line_5_from_try": 5.0,
	"line_15_from_touch": 15.0,
	"line_5_from_touch": 5.0,
	"goal_post_gap": 5.6,
	"crossbar_height": 3.0,
	"goal_post_radius": 0.045,
	"goal_post_bottom": 2.0,
	"goal_post_top": 13.41,
	"goal_pad_size": 0.49,
	"goal_pad_height": 2.0,
}


## C-35: default_pitch.tres has the section 4 defaults and validates.
func test_c35_default_pitch_resource_matches_defaults() -> void:
	var res: Resource = ResourceLoader.load(
		DEFAULT_PITCH_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	var pitch: PitchGeometry = res as PitchGeometry
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(pitch != null).is_true()
	if pitch == null:
		return
	var mismatches: Array[String] = []
	for field_name: String in EXPECTED_DEFAULTS.keys():
		var actual: float = pitch.get(field_name)
		var expected: float = EXPECTED_DEFAULTS[field_name]
		if not is_equal_approx(actual, expected):
			@warning_ignore("return_value_discarded")
			mismatches.append(field_name)
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(mismatches).is_empty()
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(pitch.validate().size()).is_equal(0)


## C-36: derived lines and zone queries with default dimensions.
func test_c36_lines_and_zones_with_defaults() -> void:
	var pitch: PitchGeometry = PitchGeometry.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitFloatAssert = assert_float(pitch.try_line_z(1)).is_equal(50.0)
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(pitch.dead_ball_line_z(-1)).is_equal(-64.1)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(pitch.line_22_z(1)).is_equal(28.0)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(pitch.is_in_field_of_play(Vector3(0, 0, 0))).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(pitch.is_in_goal(Vector3(0, 0, 50), 1)).is_true()
	@warning_ignore("unused_variable")
	var r6: GdUnitBoolAssert = assert_bool(pitch.is_in_field_of_play(Vector3(0, 0, 50))).is_false()
	@warning_ignore("unused_variable")
	var r7: GdUnitBoolAssert = (
		assert_bool(pitch.is_in_field_of_play(Vector3(33.6, 0, 49.9))).is_true()
	)
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(pitch.is_in_touch(Vector3(33.7, 0, 10))).is_true()
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = (
		assert_bool(pitch.is_beyond_dead_ball_line(Vector3(0, 0, 64.11))).is_true()
	)
	@warning_ignore("unused_variable")
	var r10: GdUnitBoolAssert = assert_bool(pitch.is_in_goal(Vector3(0, 0, 64.11), 1)).is_false()


## C-37: validate reports a zero field length and a line 22 that is not inside the half length.
func test_c37_validate_reports_bad_dimensions() -> void:
	var zero_length: PitchGeometry = PitchGeometry.new()
	zero_length.field_length = 0.0
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(zero_length.validate().size() > 0).is_true()
	var bad_line: PitchGeometry = PitchGeometry.new()
	bad_line.line_22_from_try = 60.0
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(bad_line.validate().size() > 0).is_true()
