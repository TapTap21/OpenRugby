class_name TestModScriptLayer
extends GdUnitTestSuite
## Script layer tests: entry scripts, hooks, extension points and EventBus connections
## (S1-modloader sections 9 and 10, criteria M-29 to M-34). Fixture entry scripts report through
## Engine metadata, which is cleared before each test. Every applied runtime is reverted.

const FIXTURE_ROOT: String = "res://tests/fixtures/mods"
const GAME_VERSION: String = "0.1.0"
const META_GAMMA_INIT: String = "fx_gamma_init_count"
const META_GAMMA_SHUTDOWN: String = "fx_gamma_shutdown_count"
const META_GAMMA_FINISHED: String = "fx_gamma_finished_count"
const META_UNDECLARED: String = "fx_undeclared_error"
const META_NAMES: PackedStringArray = [
	"fx_gamma_init_count",
	"fx_gamma_shutdown_count",
	"fx_gamma_finished_count",
	"fx_undeclared_error",
]

var _runtimes: Array[ModRuntime] = []


func before_test() -> void:
	_clear_meta()


func after_test() -> void:
	for index: int in range(_runtimes.size() - 1, -1, -1):
		var runtime: ModRuntime = _runtimes[index]
		if runtime.is_active():
			runtime.revert()
	_runtimes.clear()
	_clear_meta()


func _clear_meta() -> void:
	for meta_name: String in META_NAMES:
		if Engine.has_meta(meta_name):
			Engine.remove_meta(meta_name)


func _counter(meta_name: String) -> int:
	var value: int = Engine.get_meta(meta_name, 0)
	return value


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


func _flow_with_filters(runtime: ModRuntime) -> MatchFlowConfig:
	var base: MatchFlowConfig = MatchFlowConfig.new()
	var config: MatchConfig = MatchConfig.create_default()
	var result: MatchFlowConfig = runtime.extension_points.filter(
		&"match.flow_config", base, [config]
	)
	return result


## M-29: a script mod's FILTER hook returns the value, _mod_init ran once, and an OBSERVER point
## notifies its hooks.
## Note: the OBSERVER leg uses a point declared after apply, because ModLoader creates the
## extension points during apply (no base OBSERVER point exists). It checks ExtensionPoints, not
## the mod script.
func test_m29_filter_hook_runs_and_init_runs_once() -> void:
	var runtime: ModRuntime = _apply(["fx-gamma"])
	var base: MatchFlowConfig = MatchFlowConfig.new()
	var filtered: MatchFlowConfig = runtime.extension_points.filter(
		&"match.flow_config", base, [MatchConfig.create_default()]
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(filtered).is_same(base)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(str(filtered.get_meta("trace", ""))).is_equal("gamma,")
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(_counter(META_GAMMA_INIT)).is_equal(1)
	var observed: Array[Variant] = []
	@warning_ignore("unused_variable")
	var declared: Error = runtime.extension_points.declare(
		&"test.observed", ExtensionPoints.Kind.OBSERVER
	)
	@warning_ignore("unused_variable")
	var registered: Error = runtime.extension_points.register(
		&"test.observed", &"test-harness", func(value: Variant) -> void: observed.append(value)
	)
	runtime.extension_points.notify(&"test.observed", [5])
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(observed).is_equal([5])


## M-30: hooks run in ascending priority; ties follow load order.
func test_m30_hooks_order_by_priority_then_load_order() -> void:
	var runtime: ModRuntime = _apply(["fx-delta", "fx-gamma", "fx-zeta"])
	var filtered: MatchFlowConfig = _flow_with_filters(runtime)
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(str(filtered.get_meta("trace", ""))).is_equal(
		"delta,gamma,zeta,"
	)


## M-31: register_hook on an undeclared point returns ERR_DOES_NOT_EXIST and is reported.
func test_m31_undeclared_point_registration_fails() -> void:
	var runtime: ModRuntime = _apply(["fx-undeclared"])
	@warning_ignore("unused_variable")
	var undeclared_error: int = Engine.get_meta(META_UNDECLARED, 0)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(undeclared_error).is_equal(ERR_DOES_NOT_EXIST)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"hook_undeclared_point")).is_true()


## M-32: an entry script that does not extend ModEntry gives entry_script_invalid.
func test_m32_entry_script_must_extend_mod_entry() -> void:
	var runtime: ModRuntime = _apply(["fx-bad-entry"])
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(_has_issue(runtime, &"entry_script_invalid")).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(runtime.has_errors()).is_true()


## M-33: connect_event receives EventBus signals; after revert the callback stops, _mod_shutdown
## ran, and the point has no hooks.
func test_m33_event_connection_and_shutdown_on_revert() -> void:
	var runtime: ModRuntime = _apply(["fx-gamma"])
	EventBus.match_finished.emit(5)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(_counter(META_GAMMA_FINISHED)).is_equal(1)
	runtime.revert()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(_counter(META_GAMMA_SHUTDOWN)).is_equal(1)
	EventBus.match_finished.emit(6)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(_counter(META_GAMMA_FINISHED)).is_equal(1)
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = (
		assert_array(runtime.extension_points.hooks(&"match.flow_config")).is_empty()
	)


## M-34: BaseExtensionPoints declares match.sim_systems (PROVIDER) and match.flow_config (FILTER).
func test_m34_base_points_declared_with_kinds() -> void:
	var points: ExtensionPoints = ExtensionPoints.new()
	BaseExtensionPoints.declare_into(points)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(points.is_declared(&"match.sim_systems")).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(points.is_declared(&"match.flow_config")).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(points.kind_of(&"match.sim_systems")).is_equal(
		ExtensionPoints.Kind.PROVIDER
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(points.kind_of(&"match.flow_config")).is_equal(
		ExtensionPoints.Kind.FILTER
	)
