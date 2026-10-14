class_name TestMatchClock
extends GdUnitTestSuite
## Tests for MatchClock: integer tick clock with period bookkeeping (S1-core section 2.4).


## C-09: MatchClock.new(2, 60, 2400) game time, expiry and next period behaviour.
func test_c09_clock_period_and_game_time() -> void:
	var clock: MatchClock = MatchClock.new(2, 60, 2400)
	for i: int in range(30):
		clock.advance()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(clock.game_time_seconds()).is_equal(1200)
	for i: int in range(30):
		clock.advance()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(clock.is_period_expired()).is_true()
	clock.start_next_period()
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(clock.period).is_equal(2)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(clock.elapsed_ticks).is_equal(0)
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(clock.game_time_seconds()).is_equal(2400)
	@warning_ignore("unused_variable")
	var r6: GdUnitBoolAssert = assert_bool(clock.is_last_period()).is_true()
