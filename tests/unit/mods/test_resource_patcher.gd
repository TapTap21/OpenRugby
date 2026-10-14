class_name TestResourcePatcher
extends GdUnitTestSuite
## Direct tests of ResourcePatcher on fresh fixture instances (S1-modloader section 7, criteria
## M-17 to M-21 at the patcher level, and M-25). Each target is loaded with CACHE_MODE_IGNORE,
## so nothing shared is changed; patchers are reverted in after_test anyway.

const PROBE_PATH: String = "res://tests/fixtures/data/probe.tres"
const KIT_EXTRA_PATH: String = "res://tests/fixtures/data/kit_extra.tres"
const MOD_ID: StringName = &"test-mod"

var _patchers: Array[ResourcePatcher] = []


func after_test() -> void:
	for patcher: ResourcePatcher in _patchers:
		patcher.revert()
	_patchers.clear()


func _fresh_probe() -> FixtureProbe:
	var res: Resource = ResourceLoader.load(PROBE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as FixtureProbe


func _apply(probe: FixtureProbe, fields: Dictionary) -> Array[ModIssue]:
	var patcher: ResourcePatcher = ResourcePatcher.new()
	@warning_ignore("return_value_discarded")
	_patchers.append(patcher)
	return patcher.apply(probe, PROBE_PATH, fields, MOD_ID)


func _has_code(issues: Array[ModIssue], code: StringName) -> bool:
	for issue: ModIssue in issues:
		if issue.code == code:
			return true
	return false


## M-17: int, float, bool, String, StringName, enum by name, Color (hex and array) and Vector3.
func test_m17_scalar_kinds_are_set() -> void:
	var probe: FixtureProbe = _fresh_probe()
	var issues: Array[ModIssue] = _apply(
		probe,
		{
			"count": 7,
			"strength": 2.5,
			"enabled": true,
			"label": "patched",
			"tag": "patched_tag",
			"level": "HIGH",
			"tint": "#c8102e",
			"offset": [1, 2, 3],
			"kit/primary_color": [0.5, 0.25, 1.0],
		}
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(issues).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(probe.count).is_equal(7)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(probe.strength).is_equal(2.5)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(probe.enabled).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitStringAssert = assert_str(probe.label).is_equal("patched")
	@warning_ignore("unused_variable")
	var r6: GdUnitStringAssert = assert_str(String(probe.tag)).is_equal("patched_tag")
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(probe.level).is_equal(FixtureProbe.Level.HIGH)
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(probe.tint.is_equal_approx(Color("#c8102e"))).is_true()
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(probe.offset.is_equal_approx(Vector3(1, 2, 3))).is_true()
	@warning_ignore("unused_variable")
	var r10: GdUnitBoolAssert = (
		assert_bool(probe.kit.primary_color.is_equal_approx(Color(0.5, 0.25, 1.0, 1.0))).is_true()
	)


## M-18: dictionary merge (null erases, other values set) and $replace.
func test_m18_dictionary_merge_and_replace() -> void:
	var merged: FixtureProbe = _fresh_probe()
	var merge_issues: Array[ModIssue] = _apply(merged, {"bag": {"a": 1, "b": null}})
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(merge_issues).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitDictionaryAssert = assert_dict(merged.bag).is_equal({&"c": 3, &"a": 1})
	var replaced: FixtureProbe = _fresh_probe()
	var replace_issues: Array[ModIssue] = _apply(replaced, {"bag": {"$replace": {"z": 9}}})
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(replace_issues).is_empty()
	@warning_ignore("unused_variable")
	var r4: GdUnitDictionaryAssert = assert_dict(replaced.bag).is_equal({&"z": 9})


## M-19: a plain array replaces, $append appends, and a resource array accepts resource paths.
func test_m19_array_replace_append_and_resources() -> void:
	var replaced: FixtureProbe = _fresh_probe()
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(_apply(replaced, {"values": [4, 5]})).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(replaced.values).is_equal([4, 5])
	var appended: FixtureProbe = _fresh_probe()
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = (
		assert_array(_apply(appended, {"values": {"$append": [6]}})).is_empty()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(appended.values).is_equal([1, 2, 3, 6])
	var resources: FixtureProbe = _fresh_probe()
	@warning_ignore("unused_variable")
	var r5: GdUnitArrayAssert = (
		assert_array(_apply(resources, {"kits": {"$append": [KIT_EXTRA_PATH]}})).is_empty()
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(resources.kits.size()).is_equal(1)
	if resources.kits.size() == 1:
		@warning_ignore("unused_variable")
		var r7: GdUnitStringAssert = assert_str(String(resources.kits[0].id)).is_equal("kit_extra")


## M-20: a nested field path and a nested object merge both change the nested resource.
func test_m20_nested_path_and_nested_merge() -> void:
	var by_path: FixtureProbe = _fresh_probe()
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = (
		assert_array(_apply(by_path, {"kit/primary_color": "#00ff00"})).is_empty()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(by_path.kit.primary_color.is_equal_approx(Color("#00ff00"))).is_true()
	)
	var by_object: FixtureProbe = _fresh_probe()
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = (
		assert_array(_apply(by_object, {"kit": {"primary_color": "#ff0000"}})).is_empty()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(by_object.kit.primary_color.is_equal_approx(Color("#ff0000"))).is_true()
	)


## M-21 (patcher level): unknown field, wrong type and non-integral number give the right
## codes, and the other fields in the same patch still apply.
func test_m21_field_errors_do_not_stop_other_fields() -> void:
	var probe: FixtureProbe = _fresh_probe()
	var issues: Array[ModIssue] = _apply(
		probe, {"nope": 1, "count": "seven", "label": "still applied"}
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(_has_code(issues, &"patch_unknown_field")).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(_has_code(issues, &"patch_type_mismatch")).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(probe.label).is_equal("still applied")
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(probe.count).is_equal(1)
	var fractional: FixtureProbe = _fresh_probe()
	var fractional_issues: Array[ModIssue] = _apply(fractional, {"count": 2.5})
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = (
		assert_bool(_has_code(fractional_issues, &"patch_type_mismatch")).is_true()
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(fractional.count).is_equal(1)


## M-25: ResourcePatcher.fill builds a Team with a nested kit and an attribute dictionary.
func test_m25_fill_builds_team_from_json_object() -> void:
	var team: Team = Team.new()
	team.home_kit = Kit.new()
	var data: Dictionary = {
		"id": "fx-team",
		"name": "Fixture Team",
		"short_name": "FXT",
		"home_kit": {"id": "home", "primary_color": "#112233"},
		"ratings": {"speed": 60, "tackling": 55},
	}
	var issues: Array[ModIssue] = ResourcePatcher.fill(team, data)
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(issues).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(String(team.id)).is_equal("fx-team")
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(team.short_name).is_equal("FXT")
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(String(team.home_kit.id)).is_equal("home")
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = (
		assert_bool(team.home_kit.primary_color.is_equal_approx(Color("#112233"))).is_true()
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitDictionaryAssert = assert_dict(team.ratings).is_equal(
		{&"speed": 60, &"tackling": 55}
	)
