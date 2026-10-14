class_name TestMatchRunner
extends GdUnitTestSuite
## Tests for MatchRunner: start validation, stepping, input end and EventBus relays
## (S1-core section 3.4, criteria C-31 to C-34).

var _bus_callable: Callable = Callable()
var _bus_pairs: Array[String] = []


func after_test() -> void:
	if _bus_callable.is_valid() and EventBus.match_state_changed.is_connected(_bus_callable):
		EventBus.match_state_changed.disconnect(_bus_callable)
	_bus_callable = Callable()
	_bus_pairs.clear()


func _replay_source(frame_count: int) -> ReplayInputSource:
	var header: ReplayHeader = ReplayHeader.new()
	header.game_version = "0.1.0"
	var log: InputLog = InputLog.new(header)
	for index: int in range(frame_count):
		var frame: InputFrame = InputFrame.new(1, 2)
		frame.tick = index
		@warning_ignore("return_value_discarded")
		log.append(frame)
	return ReplayInputSource.new(log)


## C-31: start with the default config and a base InputSource, then five steps.
func test_c31_start_and_five_steps() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var ticked: Array[int] = []
	@warning_ignore("unused_variable")
	var connect_result: Error = runner.ticked.connect(
		func(tick_number: int) -> void: ticked.append(tick_number)
	)
	var source: InputSource = InputSource.new()
	var start_result: Error = runner.start(MatchConfig.create_default(), source)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
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


## C-33: a three-frame replay source ends on the fourth step.
func test_c33_replay_source_end_emits_input_ended() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var ended: Array[int] = []
	@warning_ignore("unused_variable")
	var connect_result: Error = runner.input_ended.connect(func() -> void: ended.append(1))
	var start_result: Error = runner.start(MatchConfig.create_default(), _replay_source(3))
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
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
	_bus_callable = Callable(self, "_on_bus_state_changed")
	@warning_ignore("unused_variable")
	var bus_connect: Error = EventBus.match_state_changed.connect(_bus_callable)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var start_result: Error = runner.start(MatchConfig.create_default(), InputSource.new())
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	var sim_pairs: Array[String] = []
	@warning_ignore("unused_variable")
	var sim_connect: Error = runner.sim.state_changed.connect(
		func(from_state: StringName, to_state: StringName) -> void:
			@warning_ignore("return_value_discarded")
			sim_pairs.append("%s>%s" % [from_state, to_state])
	)
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
