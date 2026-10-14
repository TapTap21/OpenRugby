class_name TestModEndToEnd
extends GdUnitTestSuite
## End-to-end mod loader checks: the empty mod set and the Classic invariance check (S1-modloader
## sections 6 and 10, criteria M-35 and M-36). Applied runtimes are reverted in after_test.

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const GAME_VERSION: String = "0.1.0"
const PROBE_PATH: String = "res://tests/fixtures/data/probe.tres"
const RULES_PATH: String = "res://tests/fixtures/data/fixture_rules.tres"
## Every fixture mod that is valid and does not fail resolution.
const ALL_VALID_FIXTURES: Array = [
	"fx-alpha",
	"fx-beta",
	"fx-nodata",
	"fx-noassets",
	"fx-gamma",
	"fx-delta",
	"fx-zeta",
	"fx-undeclared",
	"fx-errors",
	"fx-optional",
	"fx-prio-low",
	"fx-prio-a",
	"fx-prio-b",
	"fx-prio-high",
]

var _runtimes: Array[ModRuntime] = []
var _hashes: Array[String] = []
var _hash_callable: Callable = Callable()


func before_test() -> void:
	_hashes.clear()


func after_test() -> void:
	for index: int in range(_runtimes.size() - 1, -1, -1):
		var runtime: ModRuntime = _runtimes[index]
		if runtime.is_active():
			runtime.revert()
	_runtimes.clear()
	if _hash_callable.is_valid() and EventBus.mods_loaded.is_connected(_hash_callable):
		EventBus.mods_loaded.disconnect(_hash_callable)
	_hash_callable = Callable()


func _record_hash(mod_set_hash: String) -> void:
	@warning_ignore("return_value_discarded")
	_hashes.append(mod_set_hash)


func _loader() -> ModLoader:
	return ModLoader.new(GAME_VERSION, PackedStringArray([FIXTURE_ROOT]))


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


## M-35: load_mods with no enabled ids gives only base, no errors, and emits mods_loaded.
func test_m35_empty_mod_set_loads_base_and_emits() -> void:
	_hash_callable = Callable(self, "_record_hash")
	@warning_ignore("unused_variable")
	var connected: Error = EventBus.mods_loaded.connect(_hash_callable)
	var runtime: ModRuntime = _loader().load_mods(PackedStringArray())
	@warning_ignore("return_value_discarded")
	_runtimes.append(runtime)
	EventBus.mods_loaded.disconnect(_hash_callable)
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(",".join(runtime.load_order)).is_equal("base")
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(runtime.has_errors()).is_false()
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(_hashes).is_equal(["base@0.1.0".sha256_text()])
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(runtime.mod_set_hash).is_equal(
		"base@0.1.0".sha256_text()
	)


## M-36: applying every valid fixture mod and reverting leaves every patched field unchanged.
func test_m36_classic_invariance_after_revert() -> void:
	var probe: FixtureProbe = ResourceLoader.load(PROBE_PATH) as FixtureProbe
	var rules: RulesConfig = ResourceLoader.load(RULES_PATH) as RulesConfig
	var before: Dictionary = _snapshot(probe, rules)
	var runtime: ModRuntime = _loader().load_mods(PackedStringArray(ALL_VALID_FIXTURES))
	@warning_ignore("return_value_discarded")
	_runtimes.append(runtime)
	@warning_ignore("unused_variable")
	var applied: GdUnitIntAssert = assert_int(probe.count).is_not_equal(1)
	runtime.revert()
	var after: Dictionary = _snapshot(probe, rules)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(after == before).is_true()
