class_name TestMatchRunner
extends GdUnitTestSuite
## Production runner remains unavailable until the reviewed typed S2 codec is present.


class CountingSource:
	extends InputSource
	var calls: int = 0

	func fill_frame(
		_tick: int, _frame: InputFrame, _commands: DetachedCommandBundleBuilder
	) -> bool:
		calls += 1
		return true


func test_start_fails_closed_without_typed_codec() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var result: Error = runner.start(MatchConfig.create_default(), InputSource.new())
	@warning_ignore("unused_variable")
	var start_error: GdUnitIntAssert = assert_int(result).is_equal(ERR_UNCONFIGURED)
	@warning_ignore("unused_variable")
	var stopped: GdUnitBoolAssert = assert_bool(runner.is_running()).is_false()
	@warning_ignore("unused_variable")
	var no_sim: GdUnitBoolAssert = assert_bool(runner.sim == null).is_true()


func test_step_returns_before_sampling_or_ticking_without_codec() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var source: CountingSource = CountingSource.new()
	runner._source = source
	runner._running = true
	runner.sim = MatchSim.new(MatchConfig.create_default())
	var advanced: bool = runner.step_once()
	@warning_ignore("unused_variable")
	var did_not_advance: GdUnitBoolAssert = assert_bool(advanced).is_false()
	@warning_ignore("unused_variable")
	var not_sampled: GdUnitIntAssert = assert_int(source.calls).is_equal(0)
	@warning_ignore("unused_variable")
	var not_ticked: GdUnitIntAssert = assert_int(runner.sim.tick_count).is_equal(0)
