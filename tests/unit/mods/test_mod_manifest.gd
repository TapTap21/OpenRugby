class_name TestModManifest
extends GdUnitTestSuite
## Tests for ModManifest parsing and validation rules (S1-modloader sections 2 and 4,
## criteria M-04 to M-06).

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const EXAMPLE_ROOT: String = "res://mods/example-mod"


func _base_dict() -> Dictionary:
	return {
		"schema_version": 1,
		"id": "example-mod",
		"name": "Example",
		"version": "1.0.0",
		"game_version": ">=0.1.0 <0.2.0",
		"capabilities": ["data"],
	}


func _has_error(manifest: ModManifest, code: StringName) -> bool:
	for issue: ModIssue in manifest.issues:
		if issue.code == code and issue.is_error():
			return true
	return false


## M-04: a complete manifest parses with every field; absent optional keys take defaults.
func test_m04_complete_manifest_and_defaults() -> void:
	var data: Dictionary = {
		"schema_version": 1,
		"id": "example-mod",
		"name": "Example Mod",
		"version": "1.2.0",
		"author": "Someone",
		"description": "What it changes.",
		"game_version": ">=0.1.0 <0.2.0",
		"dependencies": [{"id": "other-mod", "version": "^1.0.0", "optional": false}],
		"load_priority": 4,
		"capabilities": ["data", "assets", "rules", "scripts", "ui"],
		"entry_script": "main.gd",
	}
	var full: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(full.is_valid()).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(String(full.id)).is_equal("example-mod")
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(full.name).is_equal("Example Mod")
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(full.author).is_equal("Someone")
	@warning_ignore("unused_variable")
	var r5: GdUnitStringAssert = assert_str(full.version_text).is_equal("1.2.0")
	@warning_ignore("unused_variable")
	var r6: GdUnitStringAssert = assert_str(full.game_version_text).is_equal(">=0.1.0 <0.2.0")
	@warning_ignore("unused_variable")
	var r7: GdUnitStringAssert = assert_str(full.entry_script).is_equal("main.gd")
	@warning_ignore("unused_variable")
	var r8: GdUnitIntAssert = assert_int(full.load_priority).is_equal(4)
	@warning_ignore("unused_variable")
	var r9: GdUnitIntAssert = assert_int(full.dependencies.size()).is_equal(1)
	@warning_ignore("unused_variable")
	var r10: GdUnitStringAssert = assert_str(String(full.dependencies[0].id)).is_equal("other-mod")
	@warning_ignore("unused_variable")
	var r11: GdUnitStringAssert = assert_str(full.dependencies[0].constraint_text).is_equal(
		"^1.0.0"
	)
	@warning_ignore("unused_variable")
	var r12: GdUnitBoolAssert = assert_bool(full.dependencies[0].optional).is_false()
	@warning_ignore("unused_variable")
	var r13: GdUnitBoolAssert = assert_bool(full.has_capability(&"scripts")).is_true()

	var minimal: Dictionary = _base_dict()
	var lean: ModManifest = ModManifest.parse(minimal, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var d1: GdUnitBoolAssert = assert_bool(lean.is_valid()).is_true()
	@warning_ignore("unused_variable")
	var d2: GdUnitStringAssert = assert_str(lean.author).is_equal("")
	@warning_ignore("unused_variable")
	var d3: GdUnitStringAssert = assert_str(lean.description).is_equal("")
	@warning_ignore("unused_variable")
	var d4: GdUnitIntAssert = assert_int(lean.load_priority).is_equal(0)
	@warning_ignore("unused_variable")
	var d5: GdUnitIntAssert = assert_int(lean.dependencies.size()).is_equal(0)
	@warning_ignore("unused_variable")
	var d6: GdUnitStringAssert = assert_str(lean.entry_script).is_equal("")

	var bare_dependency: Dictionary = _base_dict()
	bare_dependency["dependencies"] = [{"id": "other-mod"}]
	var with_bare: ModManifest = ModManifest.parse(
		bare_dependency, EXAMPLE_ROOT, ModManifest.Source.BUILTIN
	)
	@warning_ignore("unused_variable")
	var d7: GdUnitStringAssert = assert_str(with_bare.dependencies[0].constraint_text).is_equal("*")
	@warning_ignore("unused_variable")
	var d8: GdUnitBoolAssert = assert_bool(with_bare.dependencies[0].optional).is_false()


## M-05: a missing required key gives manifest_invalid_field.
func test_m05_missing_required_key() -> void:
	var data: Dictionary = _base_dict()
	@warning_ignore("return_value_discarded")
	data.erase("name")
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: a bad id pattern gives manifest_invalid_field.
func test_m05_bad_id_pattern() -> void:
	var data: Dictionary = _base_dict()
	data["id"] = "Bad_ID"
	var manifest: ModManifest = ModManifest.parse(
		data, "res://mods/Bad_ID", ModManifest.Source.BUILTIN
	)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: the reserved id base gives manifest_reserved_id.
func test_m05_reserved_id() -> void:
	var data: Dictionary = _base_dict()
	data["id"] = "base"
	var manifest: ModManifest = ModManifest.parse(
		data, "res://mods/base", ModManifest.Source.BUILTIN
	)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_reserved_id")).is_true()
	)


## M-05: an id that differs from the folder name gives manifest_id_mismatch.
func test_m05_id_must_equal_folder_name() -> void:
	var manifest: ModManifest = ModManifest.parse(
		_base_dict(), "res://mods/other-folder", ModManifest.Source.BUILTIN
	)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_id_mismatch")).is_true()
	)


## M-05: a bad mod version gives manifest_invalid_field.
func test_m05_bad_version() -> void:
	var data: Dictionary = _base_dict()
	data["version"] = "1.2"
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: a bad game version constraint gives manifest_invalid_field.
func test_m05_bad_game_version_constraint() -> void:
	var data: Dictionary = _base_dict()
	data["game_version"] = ">=x"
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: an unknown capability gives manifest_invalid_field.
func test_m05_unknown_capability() -> void:
	var data: Dictionary = _base_dict()
	data["capabilities"] = ["fly"]
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: the scripts capability without entry_script gives manifest_invalid_field.
func test_m05_scripts_without_entry_script() -> void:
	var data: Dictionary = _base_dict()
	data["capabilities"] = ["scripts"]
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: entry_script without the scripts capability gives manifest_invalid_field.
func test_m05_entry_script_without_scripts() -> void:
	var data: Dictionary = _base_dict()
	data["entry_script"] = "main.gd"
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_invalid_field")).is_true()
	)


## M-05: schema_version 2 gives manifest_unsupported_schema.
func test_m05_unsupported_schema_version() -> void:
	var data: Dictionary = _base_dict()
	data["schema_version"] = 2
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_unsupported_schema")).is_true()
	)


## M-05: an invalid JSON mod.json gives manifest_parse_error.
func test_m05_invalid_json_file() -> void:
	var manifest: ModManifest = ModManifest.load_file(
		FIXTURE_ROOT + "/fx-badjson", ModManifest.Source.BUILTIN
	)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = (
		assert_bool(_has_error(manifest, &"manifest_parse_error")).is_true()
	)


## M-06: an unknown top-level key is a warning and the manifest stays valid.
func test_m06_unknown_key_is_warning() -> void:
	var data: Dictionary = _base_dict()
	data["bogus_key"] = "x"
	var manifest: ModManifest = ModManifest.parse(data, EXAMPLE_ROOT, ModManifest.Source.BUILTIN)
	var found_warning: bool = false
	for issue: ModIssue in manifest.issues:
		if issue.code == &"manifest_unknown_key" and not issue.is_error():
			found_warning = true
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(found_warning).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(manifest.is_valid()).is_true()
