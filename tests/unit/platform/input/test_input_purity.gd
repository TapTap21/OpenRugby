class_name TestInputPurity
extends GdUnitTestSuite
## Purity scan of the input platform folder (S9-input criterion I-18): no script under
## game/platform/input writes to a res:// path.

const INPUT_DIR: String = "res://game/platform/input"
## Write calls whose argument list mentions a res:// path.
const WRITE_TO_RES_PATTERN: String = (
	"(FileAccess\\.open|ResourceSaver\\.save|ConfigFile\\.save"
	+ "|DirAccess\\.(make_dir|remove|rename|copy)\\w*)\\s*\\([^)]*res://"
)
## Instance-style writes (file.save(...), file.store_string(...)) mentioning a res:// path.
const STORE_TO_RES_PATTERN: String = "\\.(save|store_\\w+)\\s*\\([^)]*res://"


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


func _hits(files: Array[String], pattern: String) -> Array[String]:
	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile(pattern)
	var hits: Array[String] = []
	if compile_error != OK:
		@warning_ignore("return_value_discarded")
		hits.append("pattern does not compile")
		return hits
	for path: String in files:
		if regex.search(FileAccess.get_file_as_string(path)) != null:
			@warning_ignore("return_value_discarded")
			hits.append(path)
	return hits


## I-18: the input folder has scripts (so the scan is not vacuous) and none write to res://.
func test_i18_input_scripts_never_write_to_res() -> void:
	var files: Array[String] = []
	_gd_files(INPUT_DIR, files)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(files.size() > 0).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(_hits(files, WRITE_TO_RES_PATTERN)).is_empty()
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(_hits(files, STORE_TO_RES_PATTERN)).is_empty()
