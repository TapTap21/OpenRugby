class_name TestMatchRunner
extends GdUnitTestSuite
## S1 runner currently commits only commandless ticks with no typed outputs.


class CountingSource:
	extends InputSource
	var calls: int = 0

	func fill_frame(
		_tick: int, _frame: InputFrame, _commands: DetachedCommandBundleBuilder
	) -> bool:
		calls += 1
		return true


class TestCommand:
	extends RefCounted

	func detached_copy() -> RefCounted:
		return TestCommand.new()


class CommandSource:
	extends InputSource
	var calls: int = 0
	var append_error: Error = OK

	func fill_frame(_tick: int, _frame: InputFrame, commands: DetachedCommandBundleBuilder) -> bool:
		calls += 1
		append_error = commands.append(TestCommand.new())
		return true


func test_start_and_step_commit_one_commandless_tick_before_publication() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var source: CountingSource = CountingSource.new()
	var result: Error = runner.start(MatchConfig.create_default(), source)
	@warning_ignore("unused_variable")
	var start_error: GdUnitIntAssert = assert_int(result).is_equal(OK)
	@warning_ignore("unused_variable")
	var running: GdUnitBoolAssert = assert_bool(runner.is_running()).is_true()
	@warning_ignore("unused_variable")
	var has_sim: GdUnitBoolAssert = assert_bool(runner.sim != null).is_true()
	var published_ticks: Array[int] = []
	var reentrant_steps: Array[bool] = []
	var state_connection: Error = runner.sim.state_changed.connect(
		func(_from_state: StringName, _to_state: StringName) -> void:
			reentrant_steps.append(runner.step_once())
	)
	@warning_ignore("unused_variable")
	var state_connected: GdUnitIntAssert = assert_int(state_connection).is_equal(OK)
	var tick_connection: Error = runner.ticked.connect(
		func(tick: int) -> void: published_ticks.append(tick)
	)
	@warning_ignore("unused_variable")
	var connected: GdUnitIntAssert = assert_int(tick_connection).is_equal(OK)
	var advanced: bool = runner.step_once()
	@warning_ignore("unused_variable")
	var step_assertion: GdUnitBoolAssert = assert_bool(advanced).is_true()
	@warning_ignore("unused_variable")
	var tick_count: GdUnitIntAssert = assert_int(runner.sim.tick_count).is_equal(1)
	@warning_ignore("unused_variable")
	var source_sampled: GdUnitIntAssert = assert_int(source.calls).is_equal(1)
	@warning_ignore("unused_variable")
	var row_committed: GdUnitIntAssert = assert_int(runner.input_log.frame_count()).is_equal(1)
	@warning_ignore("unused_variable")
	var notification_tick: GdUnitArrayAssert = assert_array(published_ticks).is_equal([1])
	@warning_ignore("unused_variable")
	var reentry_was_blocked: GdUnitBoolAssert = (
		assert_bool(reentrant_steps.size() == 1 and not reentrant_steps[0]).is_true()
	)
	var stored_frame: InputFrame = InputFrame.new(1, 2)
	@warning_ignore("unused_variable")
	var readable_frame: GdUnitBoolAssert = (
		assert_bool(runner.input_log.read_frame(0, stored_frame)).is_true()
	)
	@warning_ignore("unused_variable")
	var stored_tick: GdUnitIntAssert = assert_int(stored_frame.tick).is_equal(0)
	@warning_ignore("unused_variable")
	var empty_commands: GdUnitIntAssert = (
		assert_int(runner.input_log.frame_commands(0).size()).is_equal(0)
	)
	@warning_ignore("unused_variable")
	var empty_outputs: GdUnitIntAssert = (
		assert_int(runner.input_log.frame_outputs(0).size()).is_equal(0)
	)


func test_replay_stays_disabled_until_typed_codec_exists() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	@warning_ignore("unused_variable")
	var initial_start: GdUnitIntAssert = (
		assert_int(runner.start(MatchConfig.create_default(), CountingSource.new())).is_equal(OK)
	)
	@warning_ignore("unused_variable")
	var initial_tick: GdUnitBoolAssert = assert_bool(runner.step_once()).is_true()
	runner.stop()
	var result: Error = runner.start(
		MatchConfig.create_default(), ReplayInputSource.new(InputLog.new(ReplayHeader.new()))
	)
	@warning_ignore("unused_variable")
	var unavailable: GdUnitIntAssert = assert_int(result).is_equal(ERR_UNCONFIGURED)
	@warning_ignore("unused_variable")
	var not_running: GdUnitBoolAssert = assert_bool(runner.is_running()).is_false()
	@warning_ignore("unused_variable")
	var no_sim: GdUnitBoolAssert = assert_bool(runner.sim == null).is_true()
	@warning_ignore("unused_variable")
	var no_log: GdUnitBoolAssert = assert_bool(runner.input_log == null).is_true()


func test_command_bearing_source_is_rejected_before_sim_tick() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var source: CommandSource = CommandSource.new()
	@warning_ignore("unused_variable")
	var start_error: GdUnitIntAssert = (
		assert_int(runner.start(MatchConfig.create_default(), source)).is_equal(OK)
	)
	var advanced: bool = runner.step_once()
	@warning_ignore("unused_variable")
	var did_not_advance: GdUnitBoolAssert = assert_bool(advanced).is_false()
	@warning_ignore("unused_variable")
	var source_sampled_once: GdUnitIntAssert = assert_int(source.calls).is_equal(1)
	@warning_ignore("unused_variable")
	var command_was_valid: GdUnitIntAssert = assert_int(source.append_error).is_equal(OK)
	@warning_ignore("unused_variable")
	var no_tick: GdUnitIntAssert = assert_int(runner.sim.tick_count).is_equal(0)
	@warning_ignore("unused_variable")
	var no_row: GdUnitIntAssert = assert_int(runner.input_log.frame_count()).is_equal(0)
