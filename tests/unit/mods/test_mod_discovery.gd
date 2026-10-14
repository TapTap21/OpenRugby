class_name TestModDiscovery
extends GdUnitTestSuite
## Tests for ModLoader discovery: folders, duplicate ids, .pck mounts and missing roots
## (S1-modloader section 4, criteria M-07 to M-10).

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const DUP_ROOT: String = "res://tests/fixtures/mods_dup"
const GAME_VERSION: String = "0.1.0"
const WORK_ROOT: String = "user://s1_tests"


## M-07: one manifest per fixture folder that has mod.json, sorted by folder name, BUILTIN.
func test_m07_discovers_every_fixture_folder_sorted() -> void:
	var loader: ModLoader = ModLoader.new(GAME_VERSION, PackedStringArray([FIXTURE_ROOT]))
	var manifests: Array[ModManifest] = loader.discover()
	var expected_count: int = 0
	var dir: DirAccess = DirAccess.open(FIXTURE_ROOT)
	for folder: String in dir.get_directories():
		if FileAccess.file_exists(FIXTURE_ROOT + "/" + folder + "/mod.json"):
			expected_count += 1
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(manifests.size()).is_equal(expected_count)
	var sorted_ok: bool = true
	var all_builtin: bool = true
	var all_have_root: bool = true
	for index: int in range(manifests.size()):
		var manifest: ModManifest = manifests[index]
		if manifest.source != ModManifest.Source.BUILTIN:
			all_builtin = false
		if manifest.root_path == "":
			all_have_root = false
		if index > 0 and manifests[index - 1].root_path.get_file() > manifest.root_path.get_file():
			sorted_ok = false
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(sorted_ok).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(all_builtin).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(all_have_root).is_true()


## M-08: the first root's manifest wins; the second root's manifest gets duplicate_id.
func test_m08_duplicate_id_across_roots() -> void:
	var loader: ModLoader = ModLoader.new(GAME_VERSION, PackedStringArray([FIXTURE_ROOT, DUP_ROOT]))
	var manifests: Array[ModManifest] = loader.discover()
	var alphas: Array[ModManifest] = []
	for manifest: ModManifest in manifests:
		if manifest.id == &"fx-alpha":
			@warning_ignore("return_value_discarded")
			alphas.append(manifest)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(alphas.size()).is_equal(2)
	if alphas.size() != 2:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(alphas[0].root_path.begins_with(FIXTURE_ROOT)).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(alphas[0].is_valid()).is_true()
	var has_duplicate: bool = false
	for issue: ModIssue in alphas[1].issues:
		if issue.code == &"duplicate_id" and issue.is_error():
			has_duplicate = true
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(has_duplicate).is_true()


## M-09: a .pck written at test time into user:// is mounted and its mod discovered as USER_PCK.
func test_m09_pck_mod_is_mounted_and_discovered() -> void:
	var stamp: String = str(Time.get_ticks_usec())
	var mod_id: String = "pck-" + stamp
	var work_dir: String = WORK_ROOT + "/pck_" + stamp
	var source_dir: String = work_dir + "/src"
	var pack_dir: String = work_dir + "/packs"
	@warning_ignore("unused_variable")
	var made_source: Error = DirAccess.make_dir_recursive_absolute(source_dir)
	@warning_ignore("unused_variable")
	var made_packs: Error = DirAccess.make_dir_recursive_absolute(pack_dir)
	var manifest_path: String = source_dir + "/mod.json"
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	@warning_ignore("unused_variable")
	var written: bool = file != null
	if file != null:
		@warning_ignore("return_value_discarded")
		file.store_string(
			(
				(
					'{"schema_version": 1, "id": "%s", "name": "Pck Mod", "version": "1.0.0", '
					+ '"game_version": ">=0.1.0 <0.2.0", "capabilities": []}'
				)
				% mod_id
			)
		)
		file.close()
	var pck_path: String = pack_dir + "/" + mod_id + ".pck"
	var packer: PCKPacker = PCKPacker.new()
	@warning_ignore("unused_variable")
	var start_error: Error = packer.pck_start(ProjectSettings.globalize_path(pck_path))
	@warning_ignore("unused_variable")
	var add_error: Error = packer.add_file(
		"res://mods/%s/mod.json" % mod_id, ProjectSettings.globalize_path(manifest_path)
	)
	@warning_ignore("unused_variable")
	var flush_error: Error = packer.flush()
	var loader: ModLoader = ModLoader.new(GAME_VERSION, PackedStringArray([pack_dir]))
	var manifests: Array[ModManifest] = loader.discover()
	var found: ModManifest = null
	for manifest: ModManifest in manifests:
		if String(manifest.id) == mod_id:
			found = manifest
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(found).is_not_null()
	if found == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(found.source).is_equal(ModManifest.Source.USER_PCK)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(found.pck_path != "").is_true()


## M-10: a missing search root is skipped silently.
func test_m10_missing_root_is_skipped() -> void:
	var loader: ModLoader = ModLoader.new(
		GAME_VERSION, PackedStringArray(["res://tests/fixtures/no_such_root"])
	)
	var manifests: Array[ModManifest] = loader.discover()
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(manifests).is_empty()
