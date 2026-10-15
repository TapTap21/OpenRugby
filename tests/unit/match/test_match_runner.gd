class_name TestMatchRunner
extends GdUnitTestSuite
## Tests for MatchRunner: start validation, stepping, input end and EventBus relays
## (S1-core section 3.4, criteria C-31 to C-34).

const S2_TEST_SETUP = preload("res://tests/helpers/s2_match_test_setup.gd")


class _FixedLayoutInputSource:
	extends InputSource

	func layout_hash() -> String:
		return "test-runner-replay-layout-v1"


class _CounterSystem:
	extends SimSystem

	var id: StringName = &""
	var ticks: int = 0

	func _init(p_id: StringName) -> void:
		id = p_id

	func system_id() -> StringName:
		return id

	func tick(_sim: MatchSim) -> void:
		ticks += 1

	func snapshot() -> Dictionary:
		return {"id": id, "ticks": ticks}

	func snapshot_is_complete() -> bool:
		return true

	func transaction_checkpoint() -> SimDependencyCheckpoint:
		var checkpoint: SimDependencyCheckpoint = SimDependencyCheckpoint.new()
		checkpoint.complete = true
		checkpoint.state = {"ticks": ticks}
		return checkpoint

	func restore_transaction_checkpoint(checkpoint: SimDependencyCheckpoint) -> bool:
		if checkpoint == null or not checkpoint.complete:
			return false
		var raw_ticks: Variant = checkpoint.state.get("ticks")
		if not raw_ticks is int:
			return false
		ticks = raw_ticks
		return true


var _bus_callable: Callable = Callable()
var _bus_pairs: Array[String] = []
var _event_bus_node: Node
var _owns_event_bus: bool = false


func _start_runner(
	runner: MatchRunner, config: MatchConfig, source: InputSource, systems: Array[SimSystem] = []
) -> Error:
	return runner.start(config, source, systems, "", null, null, null, S2_TEST_SETUP.runtime_port())


func _ensure_event_bus() -> Node:
	var existing_bus: Node = EventBusAccess.resolve()
	if existing_bus != null:
		_event_bus_node = existing_bus
		return existing_bus
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var test_bus: EventBusImpl = EventBusImpl.new()
	test_bus.name = "EventBus"
	tree.root.add_child(test_bus)
	_event_bus_node = test_bus
	_owns_event_bus = true
	return test_bus


func after_test() -> void:
	if (
		is_instance_valid(_event_bus_node)
		and _bus_callable.is_valid()
		and _event_bus_node.is_connected(&"match_state_changed", _bus_callable)
	):
		_event_bus_node.disconnect(&"match_state_changed", _bus_callable)
	if _owns_event_bus and is_instance_valid(_event_bus_node):
		_event_bus_node.queue_free()
	_event_bus_node = null
	_owns_event_bus = false
	_bus_callable = Callable()
	_bus_pairs.clear()


func _replay_source(frame_count: int, config: MatchConfig) -> ReplayInputSource:
	var bootstrap: MatchRunner = auto_free(MatchRunner.new())
	var start_result: Error = _start_runner(bootstrap, config, _FixedLayoutInputSource.new())
	@warning_ignore("unused_variable")
	var start_assert: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return null
	var header: ReplayHeader = ReplayHeader.from_dict(bootstrap.input_log.header.to_dict())
	bootstrap.stop()
	if header == null:
		return null
	@warning_ignore("unused_variable")
	var version_assert: GdUnitIntAssert = assert_int(header.format_version).is_equal(
		ReplayHeader.CURRENT_FORMAT_VERSION
	)
	@warning_ignore("unused_variable")
	var mod_hash_assert: GdUnitStringAssert = assert_str(header.mod_set_hash).is_equal("")
	@warning_ignore("unused_variable")
	var layout_assert: GdUnitStringAssert = assert_str(header.action_layout_hash).is_equal(
		"test-runner-replay-layout-v1"
	)
	@warning_ignore("unused_variable")
	var setup_assert: GdUnitBoolAssert = assert_bool(header.setup_fingerprint.is_empty()).is_false()
	var log: InputLog = InputLog.new(header)
	for index: int in range(frame_count):
		var frame: InputFrame = InputFrame.new(header.slot_count, header.axes_per_slot)
		frame.tick = index
		log.append(frame)
	@warning_ignore("unused_variable")
	var frame_count_assert: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(frame_count)
	return ReplayInputSource.new(log)


## C-31: start with the default config and a base InputSource, then five steps.
func test_c31_start_and_five_steps() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var ticked: Array[int] = []
	var connect_result: Error = runner.ticked.connect(
		func(tick_number: int) -> void: ticked.append(tick_number)
	)
	@warning_ignore("unused_variable")
	var connect_assert: GdUnitIntAssert = assert_int(connect_result).is_equal(OK)
	if connect_result != OK:
		return
	var source: InputSource = InputSource.new()
	var start_result: Error = _start_runner(runner, S2_TEST_SETUP.match_config(), source)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return
	var stepped: int = 0
	for i: int in range(5):
		if runner.step_once():
			stepped += 1
	runner.stop()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(stepped).is_equal(5)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(runner.sim.tick_count).is_equal(5)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(runner.input_log.frame_count()).is_equal(5)
	@warning_ignore("unused_variable")
	var r5: GdUnitArrayAssert = assert_array(ticked).is_equal([1, 2, 3, 4, 5])


## C-32: start with an invalid config returns ERR_INVALID_PARAMETER.
func test_c32_start_with_invalid_config_fails() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var config: MatchConfig = MatchConfig.create_default()
	config.rules = null
	var start_result: Error = runner.start(config, InputSource.new())
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(ERR_INVALID_PARAMETER)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(runner.is_running()).is_false()


## C-33 partial: checks three-frame exhaustion and a well-formed v3 header.
## Current MatchRunner lacks an independent action-layout identity seam for compatibility.
func test_c33_partial_replay_source_end_emits_input_ended() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var ended: Array[int] = []
	var connect_result: Error = runner.input_ended.connect(func() -> void: ended.append(1))
	@warning_ignore("unused_variable")
	var connect_assert: GdUnitIntAssert = assert_int(connect_result).is_equal(OK)
	if connect_result != OK:
		return
	var config: MatchConfig = S2_TEST_SETUP.match_config()
	var source: ReplayInputSource = _replay_source(3, config)
	@warning_ignore("unused_variable")
	var source_assert: GdUnitObjectAssert = assert_object(source).is_not_null()
	if source == null:
		return
	var start_result: Error = _start_runner(runner, config, source)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return
	var results: Array[bool] = []
	for i: int in range(4):
		@warning_ignore("return_value_discarded")
		results.append(runner.step_once())
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(results).is_equal([true, true, true, false])
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(ended).is_equal([1])
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(runner.is_running()).is_false()


func _on_bus_state_changed(from_state: StringName, to_state: StringName, _tick: int) -> void:
	@warning_ignore("return_value_discarded")
	_bus_pairs.append("%s>%s" % [from_state, to_state])


## C-34: EventBus.match_state_changed carries the same from/to pairs as the sim's signal.
func test_c34_event_bus_relays_state_changes() -> void:
	_event_bus_node = _ensure_event_bus()
	@warning_ignore("unused_variable")
	var bus_ready: GdUnitBoolAssert = (
		assert_bool(_event_bus_node != null and _event_bus_node.is_inside_tree()).is_true()
	)
	if _event_bus_node == null:
		return
	_bus_callable = Callable(self, "_on_bus_state_changed")
	var bus_connect: Error = _event_bus_node.connect(&"match_state_changed", _bus_callable)
	@warning_ignore("unused_variable")
	var bus_connect_assert: GdUnitIntAssert = assert_int(bus_connect).is_equal(OK)
	if bus_connect != OK:
		return
	var runner: MatchRunner = auto_free(MatchRunner.new())
	runner.set_physics_process(false)
	get_tree().root.add_child(runner)
	var start_result: Error = _start_runner(runner, S2_TEST_SETUP.match_config(), InputSource.new())
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return
	var sim_pairs: Array[String] = []
	var sim_connect: Error = runner.sim.state_changed.connect(
		func(from_state: StringName, to_state: StringName) -> void:
			@warning_ignore("return_value_discarded")
			sim_pairs.append("%s>%s" % [from_state, to_state])
	)
	@warning_ignore("unused_variable")
	var sim_connect_assert: GdUnitIntAssert = assert_int(sim_connect).is_equal(OK)
	if sim_connect != OK:
		return
	for i: int in range(3):
		@warning_ignore("unused_variable")
		var stepped: bool = runner.step_once()
	runner.stop()
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(sim_pairs).is_equal(
		["pre_match>kick_off", "kick_off>in_play"]
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(_bus_pairs).is_equal(sim_pairs)


## Main passes its owned runtime to MatchRunner: caller systems precede extension systems, and
## both precede the required S2 systems.
func test_main_starts_match_with_mod_extension_points() -> void:
	var main: Main = auto_free(Main.new())
	var runtime: ModRuntime = ModRuntime.new()
	main._mod_runtime = runtime
	var hook_system: _CounterSystem = _CounterSystem.new(&"hook_system")
	var base_system: _CounterSystem = _CounterSystem.new(&"base_system")
	var flow_filter: Callable = func(
		flow: MatchFlowConfig, _config: MatchConfig
	) -> MatchFlowConfig:
		flow.initial_state = MatchStateIds.KICK_OFF
		return flow
	var system_provider: Callable = func(_config: MatchConfig) -> SimSystem: return hook_system
	var filter_result: Error = runtime.extension_points.register(
		BaseExtensionPoints.MATCH_FLOW_CONFIG,
		&"test-mod",
		flow_filter,
		0,
		true,
		"test-flow-config-v1"
	)
	var provider_result: Error = runtime.extension_points.register(
		BaseExtensionPoints.MATCH_SIM_SYSTEMS,
		&"test-mod",
		system_provider,
		0,
		true,
		"test-system-provider-v1"
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(filter_result).is_equal(OK)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(provider_result).is_equal(OK)
	var systems: Array[SimSystem] = [base_system]
	var start_result: Error = main.start_match(
		S2_TEST_SETUP.match_config(), InputSource.new(), systems, S2_TEST_SETUP.runtime_port()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return
	var runner: MatchRunner = main.get_child(0) as MatchRunner
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(String(runner.sim.current_state())).is_equal("kick_off")
	@warning_ignore("unused_variable")
	var stepped: GdUnitBoolAssert = assert_bool(runner.step_once()).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(base_system.ticks).is_equal(1)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(hook_system.ticks).is_equal(1)
	var rows: Array = runner.sim.snapshot()["systems"]
	var ids: Array[StringName] = []
	for row: Dictionary in rows:
		@warning_ignore("return_value_discarded")
		ids.append(row["id"])
	@warning_ignore("unused_variable")
	var r7: GdUnitArrayAssert = (
		assert_array(ids)
		. is_equal(
			[
				&"base_system",
				&"hook_system",
				&"s2_locomotion",
				&"s2_ball_physics",
				&"s2_interactions",
			]
		)
	)
