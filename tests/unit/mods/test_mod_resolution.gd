class_name TestModResolution
extends GdUnitTestSuite
## Tests for ModLoader.resolve: rejections, dependencies, cycles, load order and the mod set hash
## (S1-modloader section 5, criteria M-11 to M-16).

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const GAME_VERSION: String = "0.1.0"


func _loader() -> ModLoader:
	return ModLoader.new(GAME_VERSION, PackedStringArray([FIXTURE_ROOT]))


func _resolve(enabled: Array) -> ModLoadPlan:
	var loader: ModLoader = _loader()
	return loader.resolve(loader.discover(), PackedStringArray(enabled))


func _order(plan: ModLoadPlan) -> String:
	return ",".join(plan.load_order_ids())


func _rejection_code(plan: ModLoadPlan, mod_id: StringName) -> StringName:
	if not plan.rejected.has(mod_id):
		return &""
	var issue: ModIssue = plan.rejected[mod_id]
	return issue.code


func _manifest(id: String, version: String, priority: int) -> ModManifest:
	var data: Dictionary = {
		"schema_version": 1,
		"id": id,
		"name": id,
		"version": version,
		"game_version": ">=0.1.0 <0.2.0",
		"load_priority": priority,
		"capabilities": [],
	}
	return ModManifest.parse(data, "res://mods/" + id, ModManifest.Source.BUILTIN)


## M-11: with no enabled ids the order is [base] and the hash is that of base@<game version>.
func test_m11_no_enabled_mods_hash() -> void:
	var plan: ModLoadPlan = _resolve([])
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_order(plan)).is_equal("base")
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(plan.mod_set_hash()).is_equal(
		"base@0.1.0".sha256_text()
	)


## M-12: a dependency loads before its dependent regardless of priority and enabled order.
func test_m12_dependency_loads_first() -> void:
	var plan: ModLoadPlan = _resolve(["fx-optional", "fx-alpha"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(_order(plan)).is_equal("base,fx-alpha,fx-optional")


## M-13: independent mods order by (load_priority, id).
func test_m13_priority_then_id_order() -> void:
	var plan: ModLoadPlan = _resolve(["fx-prio-b", "fx-prio-high", "fx-prio-a", "fx-prio-low"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(_order(plan)).is_equal(
		"base,fx-prio-low,fx-prio-a,fx-prio-b,fx-prio-high"
	)


## M-14: unknown ids are not_found.
func test_m14_unknown_id_not_found() -> void:
	var plan: ModLoadPlan = _resolve(["fx-nope"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(String(_rejection_code(plan, &"fx-nope"))).is_equal(
		"not_found"
	)


## M-14: a manifest with errors is invalid_manifest.
func test_m14_invalid_manifest_rejected() -> void:
	var plan: ModLoadPlan = _resolve(["fx-badmanifest"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = (
		assert_str(String(_rejection_code(plan, &"fx-badmanifest"))).is_equal("invalid_manifest")
	)


## M-14: a required dependency that is not enabled gives missing_dependency.
func test_m14_missing_dependency() -> void:
	var plan: ModLoadPlan = _resolve(["fx-needs-missing"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = (
		assert_str(String(_rejection_code(plan, &"fx-needs-missing")))
		. is_equal("missing_dependency")
	)


## M-14: a dependency whose version does not match gives dependency_version_mismatch.
func test_m14_dependency_version_mismatch() -> void:
	var plan: ModLoadPlan = _resolve(["fx-dep-mismatch", "fx-alpha"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = (
		assert_str(String(_rejection_code(plan, &"fx-dep-mismatch")))
		. is_equal("dependency_version_mismatch")
	)


## M-14: a game version mismatch gives game_version_mismatch.
func test_m14_game_version_mismatch() -> void:
	var plan: ModLoadPlan = _resolve(["fx-gv-old"])
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = (
		assert_str(String(_rejection_code(plan, &"fx-gv-old"))).is_equal("game_version_mismatch")
	)


## M-14: both mods of a two-mod cycle are rejected with dependency_cycle.
func test_m14_two_mod_cycle() -> void:
	var plan: ModLoadPlan = _resolve(["fx-cycle-a", "fx-cycle-b"])
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(String(_rejection_code(plan, &"fx-cycle-a"))).is_equal(
		"dependency_cycle"
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(String(_rejection_code(plan, &"fx-cycle-b"))).is_equal(
		"dependency_cycle"
	)


## M-14: a mod depending on a rejected mod is rejected too.
func test_m14_dependent_of_rejected_mod_is_rejected() -> void:
	var plan: ModLoadPlan = _resolve(["fx-needs-rejected", "fx-gv-old"])
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(_rejection_code(plan, &"fx-needs-rejected") != &"").is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(plan.load_order_ids().has("fx-needs-rejected")).is_false()
	)


## M-15: an optional dependency that is not enabled is ignored.
func test_m15_optional_dependency_not_enabled_is_ignored() -> void:
	var plan: ModLoadPlan = _resolve(["fx-optional"])
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_order(plan)).is_equal("base,fx-optional")
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(plan.rejected.is_empty()).is_true()


## M-15: an enabled optional dependency is loaded first (ordering and version check apply).
func test_m15_enabled_optional_dependency_loads_first() -> void:
	var plan: ModLoadPlan = _resolve(["fx-optional", "fx-alpha"])
	var alpha_index: int = plan.load_order_ids().find("fx-alpha")
	var optional_index: int = plan.load_order_ids().find("fx-optional")
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(alpha_index >= 0 and alpha_index < optional_index).is_true()
	)


## M-16: the hash is identical for two resolutions of the same input.
func test_m16_hash_stable_for_same_input() -> void:
	var first: String = _resolve(["fx-alpha", "fx-beta"]).mod_set_hash()
	var second: String = _resolve(["fx-alpha", "fx-beta"]).mod_set_hash()
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(second).is_equal(first)


## M-16: the hash changes when a mod's version changes.
func test_m16_hash_changes_with_version() -> void:
	var loader: ModLoader = _loader()
	var before: Array[ModManifest] = [_manifest("mod-x", "1.0.0", 0)]
	var after: Array[ModManifest] = [_manifest("mod-x", "1.0.1", 0)]
	var hash_before: String = loader.resolve(before, PackedStringArray(["mod-x"])).mod_set_hash()
	var hash_after: String = loader.resolve(after, PackedStringArray(["mod-x"])).mod_set_hash()
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(hash_before != hash_after).is_true()


## M-16: the hash changes when the load order changes.
func test_m16_hash_changes_with_order() -> void:
	var loader: ModLoader = _loader()
	var same_priority: Array[ModManifest] = [
		_manifest("mod-p", "1.0.0", 0), _manifest("mod-q", "1.0.0", 0)
	]
	var reordered: Array[ModManifest] = [
		_manifest("mod-p", "1.0.0", 0), _manifest("mod-q", "1.0.0", -1)
	]
	var enabled: PackedStringArray = PackedStringArray(["mod-p", "mod-q"])
	var plan_a: ModLoadPlan = loader.resolve(same_priority, enabled)
	var plan_b: ModLoadPlan = loader.resolve(reordered, enabled)
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_order(plan_a)).is_equal("base,mod-p,mod-q")
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(_order(plan_b)).is_equal("base,mod-q,mod-p")
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(plan_a.mod_set_hash() != plan_b.mod_set_hash()).is_true()
