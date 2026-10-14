class_name TestMatchPurity
extends GdUnitTestSuite
## Purity scan of the simulation folders (S1-core sections 2.5 and criterion C-43).
## Comments are scanned too, so sim files must not mention banned names at all.

const MATCH_DIR: String = "res://game/match"
const RUNNER_FILE_NAME: String = "match_runner.gd"
const PURE_DIRS: PackedStringArray = [
	"res://game/ball",
	"res://game/player",
	"res://game/rules",
	"res://game/setpiece",
	"res://game/ai",
]
## Global random calls, not preceded by an identifier character or a dot (so rng.randi( and
## range_int( do not match).
const RANDOM_PATTERN: String = (
	"(?<![\\w.])(randi|randf|randfn|randi_range|randf_range|randomize|seed)" + "\\s*\\("
)
const CLOCK_INPUT_PATTERN: String = "(?<![\\w])(Input|Time)\\.|OS\\.get_ticks"
const EVENT_BUS_PATTERN: String = "(?<![\\w])EventBus"


func _gd_files(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if file_name.get_extension() == "gd":
			@warning_ignore("return_value_discarded")
			out.append(dir_path.path_join(file_name))
	for sub_dir: String in dir.get_directories():
		_gd_files(dir_path.path_join(sub_dir), out)


func _match_files_without_runner() -> Array[String]:
	var all_files: Array[String] = []
	_gd_files(MATCH_DIR, all_files)
	var files: Array[String] = []
	for path: String in all_files:
		if path.get_file() != RUNNER_FILE_NAME:
			@warning_ignore("return_value_discarded")
			files.append(path)
	return files


func _hits(files: Array[String], pattern: String) -> Array[String]:
	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile(pattern)
	var hits: Array[String] = []
	if compile_error != OK:
		@warning_ignore("return_value_discarded")
		hits.append("pattern does not compile: %s" % pattern)
		return hits
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		if regex.search(text) != null:
			@warning_ignore("return_value_discarded")
			hits.append(path)
	return hits


## C-43: no EventBus, Input., Time., OS.get_ticks or global random calls under game/match
## (except match_runner.gd).
func test_c43_match_folder_has_no_banned_names() -> void:
	var files: Array[String] = _match_files_without_runner()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(files.size() > 0).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(_hits(files, EVENT_BUS_PATTERN)).is_empty()
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(_hits(files, CLOCK_INPUT_PATTERN)).is_empty()
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(_hits(files, RANDOM_PATTERN)).is_empty()


## C-43: the same ban on Input, Time, OS.get_ticks and global random applies to the other
## pure folders from section 2.5 (those that exist).
func test_c43_other_pure_folders_have_no_clock_input_or_random() -> void:
	var files: Array[String] = []
	for dir_path: String in PURE_DIRS:
		if DirAccess.dir_exists_absolute(dir_path):
			_gd_files(dir_path, files)
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(_hits(files, CLOCK_INPUT_PATTERN)).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(_hits(files, RANDOM_PATTERN)).is_empty()


## Sanity check on the patterns themselves, so the scans above cannot pass vacuously.
func test_c43_patterns_detect_banned_calls() -> void:
	var sample: String = "var n := randi()\nvar t := Time.get_ticks_msec()\nvar e := EventBus\n"
	var random_regex: RegEx = RegEx.new()
	@warning_ignore("unused_variable")
	var compile_error: Error = random_regex.compile(RANDOM_PATTERN)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(random_regex.search(sample) != null).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(random_regex.search("var x := rng.range_int(1, 2)") == null).is_true()
	)
	var clock_regex: RegEx = RegEx.new()
	@warning_ignore("unused_variable")
	var compile_error_two: Error = clock_regex.compile(CLOCK_INPUT_PATTERN)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(clock_regex.search(sample) != null).is_true()
