class_name TestModApplyData
extends GdUnitTestSuite
## Runtime-level data layer tests: patches from mod folders applied through ModLoader, with
## conflicts, revert and capability checks (S1-modloader sections 6 to 8, criteria M-17, M-21 to
## M-24). Every applied runtime is reverted in after_test.

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const GAME_VERSION: String = "0.1.0"
const PROBE_PATH: String = "res://tests/fixtures/data/probe.tres"
const RULES_PATH: String = "res://tests/fixtures/data/fixture_rules.tres"

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


func _snapshot(probe: FixtureProbe, rules: RulesConfig) -> Dictionary:
	return {
		"count": probe.count,
		"ratio": probe.ratio,
		"strength": probe.strength,
		"enabled": probe.enabled,
		"label": probe.label,
		"tag": probe.tag,
		"level": probe.level,
		"tint": probe.tint,
		"offset": probe.offset,
		"kit_id": probe.kit.id,
		"kit_color": probe.kit.primary_color,
		"bag": probe.bag.duplicate(),
		"values": probe.values.duplicate(),
		"kits": probe.kits.size(),
		"points_try": rules.points_try,
		"extra": rules.extra.duplicate(),
	}


## M-17 at runtime: the patched instance is the one every later load() of the path returns.
func test_m17_second_load_returns_patched_instance() -> void:
	var runtime: ModRuntime = _apply(["fx-alpha"])
	var first: FixtureProbe = runtime.load_resource(PROBE_PATH) as FixtureProbe
	var second: FixtureProbe = ResourceLoader.load(PROBE_PATH) as FixtureProbe
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(second).is_same(first)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(second.count).is_equal(7)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(second.level).is_equal(FixtureProbe.Level.HIGH)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(second.tint.is_equal_approx(Color("#c8102e"))).is_true()


## M-21 at runtime: missing target and invalid JSON are reported; other fields still apply.
func test_m21_missing_target_and_invalid_json_reported() -> void:
	var runtime: ModRuntime = _apply(["fx-errors"])
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"patch_target_missing")).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"patch_parse_error")).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"patch_unknown_field")).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"patch_type_mismatch")).is_true()
	var probe: FixtureProbe = ResourceLoader.load(PROBE_PATH) as FixtureProbe
	@warning_ignore("unused_variable")
	var r5: GdUnitStringAssert = assert_str(probe.label).is_equal("errors")
	@warning_ignore("unused_variable")
	var r6: GdUnitFloatAssert = assert_float(probe.strength).is_equal(0.25)
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(probe.count).is_equal(1)


## M-22: two mods patching one field; the later in load order wins and the ledger shows it.
func test_m22_later_mod_wins_and_conflict_is_listed() -> void:
	var runtime: ModRuntime = _apply(["fx-alpha", "fx-beta"])
	var probe: FixtureProbe = ResourceLoader.load(PROBE_PATH) as FixtureProbe
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(probe.count).is_equal(9)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = (
		assert_str(String(runtime.ledger.last_writer(PROBE_PATH, "count"))).is_equal("fx-beta")
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = (
		assert_array(runtime.ledger.field_writers(PROBE_PATH, "count"))
		. is_equal([&"fx-alpha", &"fx-beta"])
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = (
		assert_str(String(runtime.ledger.last_writer(PROBE_PATH, "ratio"))).is_equal("base")
	)
	var field_conflicts: Array[Dictionary] = []
	for entry: Dictionary in runtime.ledger.conflicts():
		if entry["kind"] == &"field":
			@warning_ignore("return_value_discarded")
			field_conflicts.append(entry)
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(field_conflicts.size()).is_equal(1)
	if field_conflicts.size() == 1:
		var conflict: Dictionary = field_conflicts[0]
		@warning_ignore("unused_variable")
		var r6: GdUnitStringAssert = assert_str(str(conflict["field"])).is_equal("count")
		@warning_ignore("unused_variable")
		var r7: GdUnitArrayAssert = assert_array(conflict["mods"]).is_equal(
			[&"fx-alpha", &"fx-beta"]
		)
		@warning_ignore("unused_variable")
		var r8: GdUnitBoolAssert = assert_bool(conflict["winner"] == &"fx-beta").is_true()


## M-23: revert restores every patched value, including dictionary and array contents.
func test_m23_revert_restores_exact_values() -> void:
	var probe: FixtureProbe = ResourceLoader.load(PROBE_PATH) as FixtureProbe
	var rules: RulesConfig = ResourceLoader.load(RULES_PATH) as RulesConfig
	var before: Dictionary = _snapshot(probe, rules)
	var runtime: ModRuntime = _apply(["fx-alpha", "fx-beta"])
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(probe.count).is_equal(9)
	runtime.revert()
	var after: Dictionary = _snapshot(probe, rules)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(after == before).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(probe.count).is_equal(1)


## M-24: a data/ folder without the data capability is skipped with capability_missing.
func test_m24_data_without_capability_is_skipped() -> void:
	var runtime: ModRuntime = _apply(["fx-nodata"])
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"capability_missing")).is_true()
	var probe: FixtureProbe = ResourceLoader.load(PROBE_PATH) as FixtureProbe
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(probe.ratio).is_equal(0.5)


## M-24: a RulesConfig patch without the rules capability warns and still applies.
func test_m24_rules_patch_without_rules_capability_still_applies() -> void:
	var runtime: ModRuntime = _apply(["fx-beta"])
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(_has_issue(runtime, &"capability_undeclared_rules")).is_true()
	)
	var rules: RulesConfig = ResourceLoader.load(RULES_PATH) as RulesConfig
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(rules.points_try).is_equal(6)
