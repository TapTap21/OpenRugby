class_name TestModAssets
extends GdUnitTestSuite
## Asset layer tests: overrides/ shadow files resolved through ModRuntime (S1-modloader
## section 6, criteria M-26 to M-28). Every applied runtime is reverted in after_test.

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const GAME_VERSION: String = "0.1.0"
const KIT_PATH: String = "res://tests/fixtures/data/kit_extra.tres"
const PROBE_PATH: String = "res://tests/fixtures/data/probe.tres"
const SHADOW_REL_PATH: String = "tests/fixtures/data/kit_extra.tres"
const ALPHA_SHADOW: String = "res://tests/fixtures/mods/fx-alpha/overrides/" + SHADOW_REL_PATH
const BETA_SHADOW: String = "res://tests/fixtures/mods/fx-beta/overrides/" + SHADOW_REL_PATH

var _runtimes: Array[ModRuntime] = []


func after_test() -> void:
	for index: int in range(_runtimes.size() - 1, -1, -1):
		var runtime: ModRuntime = _runtimes[index]
		if runtime.is_active():
			runtime.revert()
	_runtimes.clear()


func _apply(enabled: Array) -> ModRuntime:
	var loader: ModLoader = ModLoader.new(GAME_VERSION, PackedStringArray([FIXTURE_ROOT]))
	var runtime: ModRuntime = loader.load_mods(PackedStringArray(enabled))
	@warning_ignore("return_value_discarded")
	_runtimes.append(runtime)
	return runtime


func _has_issue(runtime: ModRuntime, code: StringName) -> bool:
	for issue: ModIssue in runtime.issues:
		if issue.code == code:
			return true
	return false


## M-26: an overrides/ file shadows its res:// path; unshadowed paths are unchanged; load_resource
## loads the shadow.
func test_m26_single_shadow_resolves_and_loads() -> void:
	var runtime: ModRuntime = _apply(["fx-alpha"])
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(runtime.resolve_asset_path(KIT_PATH)).is_equal(
		ALPHA_SHADOW
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(runtime.resolve_asset_path(PROBE_PATH)).is_equal(
		PROBE_PATH
	)
	var kit: Kit = runtime.load_resource(KIT_PATH) as Kit
	@warning_ignore("unused_variable")
	var r3: GdUnitObjectAssert = assert_object(kit).is_not_null()
	if kit != null:
		@warning_ignore("unused_variable")
		var r4: GdUnitStringAssert = assert_str(String(kit.id)).is_equal("kit_shadow_alpha")


## M-27: two mods shadowing one path; the later mod wins and the conflict is listed.
func test_m27_later_shadow_wins_and_asset_conflict_listed() -> void:
	var runtime: ModRuntime = _apply(["fx-alpha", "fx-beta"])
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(runtime.resolve_asset_path(KIT_PATH)).is_equal(
		BETA_SHADOW
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(String(runtime.ledger.asset_owner(KIT_PATH))).is_equal(
		"fx-beta"
	)
	var asset_conflicts: Array[Dictionary] = []
	for entry: Dictionary in runtime.ledger.conflicts():
		if entry["kind"] == &"asset":
			@warning_ignore("return_value_discarded")
			asset_conflicts.append(entry)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(asset_conflicts.size()).is_equal(1)
	if asset_conflicts.size() == 1:
		@warning_ignore("unused_variable")
		var r4: GdUnitStringAssert = assert_str(str(asset_conflicts[0]["target"])).is_equal(
			KIT_PATH
		)
		@warning_ignore("unused_variable")
		var r5: GdUnitBoolAssert = assert_bool(asset_conflicts[0]["winner"] == &"fx-beta").is_true()


## M-28: an overrides/ folder without the assets capability is ignored with capability_missing.
func test_m28_overrides_without_assets_capability_ignored() -> void:
	var runtime: ModRuntime = _apply(["fx-noassets"])
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"capability_missing")).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(runtime.resolve_asset_path(KIT_PATH)).is_equal(KIT_PATH)
