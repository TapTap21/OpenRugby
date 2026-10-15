class_name TestMatchDeterminism
extends GdUnitTestSuite
## Determinism tests: identical config, mod set and input log give identical state hashes, and
## a recorded input log replays to the same final hash (ADR-004, S1-core sections 2.5 and 3.3;
## criteria C-24 to C-27).

const TICK_COUNT: int = 600
const SLOT_COUNT: int = 2
const AXES_PER_SLOT: int = 2
const SCRIPT_SEED: int = 777
const SIM_SEED: int = 4242
const MOD_SET_HASH: String = "test-mod-set"
const LAYOUT_HASH: String = "test-layout"
const BUTTON_BITS: int = 6


## Test-only system: consumes sim.rng and raises triggers from input.
class TriggerSystem:
	extends SimSystem

	func setup(_sim: MatchSim) -> SetupResult:
		var claim: ParticipantClaim = ParticipantClaim.new(
			"trigger_test", "1", "test_config", "test_initial"
		)
		return SetupResult.new(true, OK, TransactionCapability.EXPLICITLY_STATELESS, claim, [])

	func system_id() -> StringName:
		return &"trigger_test"

	func tick(sim: MatchSim) -> void:
		var roll: int = sim.rng.range_int(0, 99)
		if sim.is_held(0, 1) and roll < 10:
			sim.raise_trigger(MatchTriggers.WHISTLE_BLOWN)
		elif roll >= 95:
			sim.raise_trigger(MatchTriggers.PLAY_RESUMED)


func _config(seed_value: int) -> MatchConfig:
	var config: MatchConfig = MatchConfig.create_default()
	config.seed = seed_value
	config.slot_count = SLOT_COUNT
	config.axes_per_slot = AXES_PER_SLOT
	config.period_real_seconds = 1
	return config


func _systems() -> Array[SimSystem]:
	var systems: Array[SimSystem] = [TriggerSystem.new()]
	return systems


## Scripted input: pseudo-random buttons and axes from a separate fixed-seed generator.
func _scripted_frames() -> Array[InputFrame]:
	var generator: SimRng = SimRng.new(SCRIPT_SEED)
	var frames: Array[InputFrame] = []
	for tick_index: int in range(TICK_COUNT):
		var frame: InputFrame = InputFrame.new(SLOT_COUNT, AXES_PER_SLOT)
		frame.tick = tick_index
		for slot: int in range(SLOT_COUNT):
			for bit: int in range(BUTTON_BITS):
				if generator.chance(0.3):
					frame.set_held(slot, bit, true)
			for axis: int in range(AXES_PER_SLOT):
				frame.set_axis(slot, axis, generator.range_int(-127, 127))
		@warning_ignore("return_value_discarded")
		frames.append(frame)
	return frames


func _run(config: MatchConfig, frames: Array[InputFrame], hashes: Array[String]) -> MatchSim:
	var sim: MatchSim = MatchSim.new(config)
	for system: SimSystem in _systems():
		sim.add_system(system)
	for frame: InputFrame in frames:
		sim.tick(frame)
		@warning_ignore("return_value_discarded")
		hashes.append(sim.state_hash())
	return sim


## C-24: same seed and same scripted input give identical state_hash after every tick.
func test_c24_same_seed_and_input_same_hashes() -> void:
	var frames: Array[InputFrame] = _scripted_frames()
	var hashes_a: Array[String] = []
	var hashes_b: Array[String] = []
	@warning_ignore("unused_variable")
	var sim_a: MatchSim = _run(_config(SIM_SEED), frames, hashes_a)
	@warning_ignore("unused_variable")
	var sim_b: MatchSim = _run(_config(SIM_SEED), frames, hashes_b)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(hashes_a.size()).is_equal(TICK_COUNT)
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(hashes_a).is_equal(hashes_b)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(hashes_a[0] != hashes_a[TICK_COUNT - 1]).is_true()


## C-25: changing only the seed changes state_hash after tick 1.
func test_c25_different_seed_changes_first_tick_hash() -> void:
	var frames: Array[InputFrame] = _scripted_frames()
	var first: Array[String] = []
	var second: Array[String] = []
	@warning_ignore("unused_variable")
	var sim_one: MatchSim = _run_one_tick(_config(1), frames, first)
	@warning_ignore("unused_variable")
	var sim_two: MatchSim = _run_one_tick(_config(2), frames, second)
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(first[0] != second[0]).is_true()


func _run_one_tick(
	config: MatchConfig, frames: Array[InputFrame], hashes: Array[String]
) -> MatchSim:
	var sim: MatchSim = MatchSim.new(config)
	for system: SimSystem in _systems():
		sim.add_system(system)
	sim.tick(frames[0])
	@warning_ignore("return_value_discarded")
	hashes.append(sim.state_hash())
	return sim


## C-26: manual rows serialize, while production replay stays unavailable.
func test_c26_recorded_log_replays_to_same_hash() -> void:
	var frames: Array[InputFrame] = _scripted_frames()
	var header: ReplayHeader = ReplayHeader.new()
	header.game_version = "0.1.0"
	header.seed = SIM_SEED
	header.mod_set_hash = MOD_SET_HASH
	header.action_layout_hash = LAYOUT_HASH
	header.slot_count = SLOT_COUNT
	header.axes_per_slot = AXES_PER_SLOT
	var log: InputLog = InputLog.new(header)
	for frame: InputFrame in frames:
		@warning_ignore("return_value_discarded")
		log.append_fixture_row(frame)
	var restored: InputLog = InputLog.from_bytes(log.to_bytes())
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(restored).is_not_null()
	if restored == null:
		return
	var replay: MatchSim = MatchReplay.run(_config(SIM_SEED), restored, MOD_SET_HASH, _systems())
	@warning_ignore("unused_variable")
	var r2: GdUnitObjectAssert = assert_object(replay).is_null()


## C-27: MatchReplay.run returns null when the mod set hash differs from the header's.
func test_c27_replay_refuses_different_mod_set() -> void:
	var frames: Array[InputFrame] = _scripted_frames()
	var header: ReplayHeader = ReplayHeader.new()
	header.seed = SIM_SEED
	header.mod_set_hash = MOD_SET_HASH
	header.action_layout_hash = LAYOUT_HASH
	header.slot_count = SLOT_COUNT
	header.axes_per_slot = AXES_PER_SLOT
	var log: InputLog = InputLog.new(header)
	for index: int in range(10):
		@warning_ignore("return_value_discarded")
		log.append_fixture_row(frames[index])
	var replay: MatchSim = MatchReplay.run(_config(SIM_SEED), log, "some-other-mod-set", _systems())
	@warning_ignore("unused_variable")
	var result: GdUnitObjectAssert = assert_object(replay).is_null()
