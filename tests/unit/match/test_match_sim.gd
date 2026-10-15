class_name TestMatchSim
extends GdUnitTestSuite
## Tests for MatchSim: tick order, flow timeline, triggers, systems, input edges, hashing
## (S1-core sections 2.5 to 2.8, criteria C-12 to C-23).

const TICK_FULL_TIME: int = 124
const PERIOD_SECONDS_FOR_TESTS: int = 1


## Default config with one-second periods (P = 60 ticks), the shape used by the timeline tests.
func _short_config() -> MatchConfig:
	var config: MatchConfig = MatchConfig.create_default()
	config.period_real_seconds = PERIOD_SECONDS_FOR_TESTS
	return config


func _frame() -> InputFrame:
	return InputFrame.new(1, 2)


func _tick_n(sim: MatchSim, count: int) -> void:
	for i: int in range(count):
		sim.tick(_frame())


func _state(sim: MatchSim) -> String:
	return String(sim.current_state())


## C-12: timeline of the default flow with 60-tick periods.
func test_c12_default_timeline_with_short_periods() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_state(sim)).is_equal("kick_off")
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")
	_tick_n(sim, 59)
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(_state(sim)).is_equal("half_time")
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r5: GdUnitStringAssert = assert_str(_state(sim)).is_equal("kick_off")
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(sim.clock.period).is_equal(2)
	sim.tick(_frame())
	_tick_n(sim, 59)
	@warning_ignore("unused_variable")
	var r7: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(sim.is_finished()).is_false()
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r9: GdUnitStringAssert = assert_str(_state(sim)).is_equal("full_time")
	@warning_ignore("unused_variable")
	var r10: GdUnitBoolAssert = assert_bool(sim.is_finished()).is_true()


## C-13: signals over the full run, in order.
func test_c13_signals_over_full_run() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	var changes: Array[String] = []
	var started: Array[int] = []
	var ended: Array[int] = []
	var finished_count: Array[int] = []
	@warning_ignore("unused_variable")
	var c1: Error = sim.state_changed.connect(
		func(from_state: StringName, to_state: StringName) -> void:
			@warning_ignore("return_value_discarded")
			changes.append("%s>%s" % [from_state, to_state])
	)
	@warning_ignore("unused_variable")
	var c2: Error = sim.period_started.connect(func(period: int) -> void: started.append(period))
	@warning_ignore("unused_variable")
	var c3: Error = sim.period_ended.connect(func(period: int) -> void: ended.append(period))
	@warning_ignore("unused_variable")
	var c4: Error = sim.finished.connect(func() -> void: finished_count.append(1))
	_tick_n(sim, TICK_FULL_TIME)
	var expected_changes: Array[String] = [
		"pre_match>kick_off",
		"kick_off>in_play",
		"in_play>half_time",
		"half_time>kick_off",
		"kick_off>in_play",
		"in_play>full_time",
	]
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(changes).is_equal(expected_changes)
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(started).is_equal([1, 2])
	@warning_ignore("unused_variable")
	var r3: GdUnitArrayAssert = assert_array(ended).is_equal([1, 2])
	@warning_ignore("unused_variable")
	var r4: GdUnitArrayAssert = assert_array(finished_count).is_equal([1])


## C-14: after finishing, further ticks leave tick_count and state_hash unchanged.
func test_c14_finished_sim_ignores_further_ticks() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	_tick_n(sim, TICK_FULL_TIME)
	var count_before: int = sim.tick_count
	var hash_before: String = sim.state_hash()
	_tick_n(sim, 5)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(sim.tick_count).is_equal(count_before)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(sim.state_hash()).is_equal(hash_before)


## C-15: a whistle moves in_play to stoppage; play_resumed moves back.
func test_c15_whistle_and_resume_triggers() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	_tick_n(sim, 2)
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")
	sim.raise_trigger(MatchTriggers.WHISTLE_BLOWN)
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(_state(sim)).is_equal("stoppage")
	sim.raise_trigger(MatchTriggers.PLAY_RESUMED)
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")


## C-16: a trigger that matches no transition of the current state is consumed.
func test_c16_unmatched_trigger_is_consumed() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	_tick_n(sim, 2)
	sim.raise_trigger(MatchTriggers.PLAY_RESUMED)
	sim.tick(_frame())
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")


## Clock probe: records elapsed_ticks as seen at step 4 of each tick, before the clock advances.
class ElapsedProbe:
	extends SimSystem
	var seen: Array[int] = []

	func setup(_sim: MatchSim) -> SetupResult:
		return TestMatchSim._stateless_setup("elapsed_probe")

	func tick(sim: MatchSim) -> void:
		@warning_ignore("return_value_discarded")
		seen.append(sim.clock.elapsed_ticks)


## C-17: the clock advances in in_play and stoppage, not in pre_match or kick_off.
## half_time is not observable here: the period reset on ADVANCE hides the advance, and the
## clock_runs flag of half_time is checked directly in the flow config tests (C-10).
func test_c17_clock_runs_only_in_play_and_stoppage() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	var probe: ElapsedProbe = ElapsedProbe.new()
	sim.add_system(probe)
	var deltas: Array[int] = []
	for step: int in range(7):
		if step == 4:
			sim.raise_trigger(MatchTriggers.WHISTLE_BLOWN)
		if step == 6:
			sim.raise_trigger(MatchTriggers.PLAY_RESUMED)
		sim.tick(_frame())
		@warning_ignore("return_value_discarded")
		deltas.append(sim.clock.elapsed_ticks - probe.seen[step])
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(deltas).is_equal([0, 0, 1, 1, 1, 1, 1])


## Registration-order probe: appends its id to a shared log on every tick.
class RecordSystem:
	extends SimSystem
	var _id: StringName
	var _log: Array[StringName]

	func _init(id: StringName, log: Array[StringName]) -> void:
		_id = id
		_log = log

	func system_id() -> StringName:
		return _id

	func setup(_sim: MatchSim) -> SetupResult:
		return TestMatchSim._stateless_setup(String(_id))

	func tick(_sim: MatchSim) -> void:
		@warning_ignore("return_value_discarded")
		_log.append(_id)


## Whistle system: raises WHISTLE_BLOWN from its tick while the state is in_play.
class WhistleSystem:
	extends SimSystem

	func setup(_sim: MatchSim) -> SetupResult:
		return TestMatchSim._stateless_setup("whistle_system")

	func tick(sim: MatchSim) -> void:
		if sim.current_state() == MatchStateIds.IN_PLAY:
			sim.raise_trigger(MatchTriggers.WHISTLE_BLOWN)


class HintedSystem:
	extends SimSystem
	var setup_calls: int = 0

	func participant_id_hint() -> String:
		return "shared-hint"

	func setup(_sim: MatchSim) -> SetupResult:
		setup_calls += 1
		return TestMatchSim._stateless_setup("shared-hint")


static func _stateless_setup(participant_id: String) -> SetupResult:
	var claim: ParticipantClaim = ParticipantClaim.new(participant_id, "1", "cfg", "initial")
	return SetupResult.new(true, OK, TransactionCapability.EXPLICITLY_STATELESS, claim, [])


func test_default_checkpoint_is_empty_success() -> void:
	var result: CheckpointResult = SimSystem.new().checkpoint()
	@warning_ignore("unused_variable")
	var checkpoint_succeeded: GdUnitBoolAssert = assert_bool(result.ok).is_true()
	@warning_ignore("unused_variable")
	var checkpoint_empty: GdUnitBoolAssert = (
		assert_bool(OwnerCapture._is_empty_checkpoint_value(result.value)).is_true()
	)


func test_duplicate_hinted_identity_is_rejected_before_second_setup() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	var first: HintedSystem = HintedSystem.new()
	var duplicate: HintedSystem = HintedSystem.new()
	@warning_ignore("unused_variable")
	var first_added: Error = sim.add_system(first)
	@warning_ignore("unused_variable")
	var rejected: GdUnitIntAssert = assert_int(sim.add_system(duplicate)).is_equal(
		ERR_ALREADY_EXISTS
	)
	@warning_ignore("unused_variable")
	var no_setup_side_effect: GdUnitIntAssert = assert_int(duplicate.setup_calls).is_equal(0)


## C-18: a system that raises WHISTLE_BLOWN in in_play moves the flow on the same tick.
func test_c18_system_trigger_applies_same_tick() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	sim.add_system(WhistleSystem.new())
	_tick_n(sim, 2)
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_state(sim)).is_equal("in_play")
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(_state(sim)).is_equal("stoppage")


## C-19: systems tick in registration order.
func test_c19_systems_tick_in_registration_order() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	var log: Array[StringName] = []
	sim.add_system(RecordSystem.new(&"first", log))
	sim.add_system(RecordSystem.new(&"second", log))
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(log).is_equal([&"first", &"second"])
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(log).is_equal(
		[&"first", &"second", &"first", &"second"]
	)


## C-20: add_system after the first tick is ignored and the system never ticks.
func test_c20_add_system_after_first_tick_is_ignored() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	sim.tick(_frame())
	var log: Array[StringName] = []
	sim.add_system(RecordSystem.new(&"late", log))
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(log).is_empty()


## C-21: button edges derived from consecutive frames.
func test_c21_just_pressed_and_just_released_edges() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	var pressed: Array[bool] = []
	var released: Array[bool] = []
	for tick_number: int in range(1, 6):
		var frame: InputFrame = _frame()
		if tick_number >= 2 and tick_number <= 4:
			frame.set_held(0, 3, true)
		sim.tick(frame)
		@warning_ignore("return_value_discarded")
		pressed.append(sim.just_pressed(0, 3))
		@warning_ignore("return_value_discarded")
		released.append(sim.just_released(0, 3))
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(pressed).is_equal([false, true, false, false, false])
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(released).is_equal([false, false, false, false, true])


## C-22: an invalid config (null rules) makes the sim invalid and tick a no-op.
func test_c22_invalid_config_makes_tick_no_op() -> void:
	var config: MatchConfig = _short_config()
	config.rules = null
	var sim: MatchSim = MatchSim.new(config)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(sim.is_valid()).is_false()
	sim.tick(_frame())
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(sim.tick_count).is_equal(0)


## C-23: state_hash is 64 lowercase hex characters and changes after a tick.
func test_c23_state_hash_format_and_change() -> void:
	var sim: MatchSim = MatchSim.new(_short_config())
	var before: String = sim.state_hash()
	sim.tick(_frame())
	var after: String = sim.state_hash()
	var hex_regex: RegEx = RegEx.new()
	@warning_ignore("unused_variable")
	var compile_error: Error = hex_regex.compile("^[0-9a-f]{64}$")
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(hex_regex.search(after) != null).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(hex_regex.search(before) != null).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(before != after).is_true()
