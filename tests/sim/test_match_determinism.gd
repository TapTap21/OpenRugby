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
const S2_TEST_SETUP = preload("res://tests/helpers/s2_match_test_setup.gd")


class _FrameInputSource:
	extends InputSource

	var _frames: Array[InputFrame] = []
	var _action_layout_hash: String = ""

	func _init(frames: Array[InputFrame], action_layout_hash: String) -> void:
		_action_layout_hash = action_layout_hash
		for frame: InputFrame in frames:
			var copy: InputFrame = InputFrame.new(frame.slot_count, frame.axes_per_slot)
			copy.copy_from(frame)
			_frames.append(copy)

	func fill_frame(tick: int, frame: InputFrame) -> bool:
		if tick < 0 or tick >= _frames.size():
			return false
		frame.copy_from(_frames[tick])
		return true

	func layout_hash() -> String:
		return _action_layout_hash


## Test-only system: consumes sim.rng and raises triggers from input.
class TriggerSystem:
	extends SimSystem

	func system_id() -> StringName:
		return &"trigger_test"

	func tick(sim: MatchSim) -> void:
		var roll: int = sim.rng.range_int(0, 99)
		if sim.is_held(0, 1) and roll < 10:
			sim.raise_trigger(MatchTriggers.WHISTLE_BLOWN)
		elif roll >= 95:
			sim.raise_trigger(MatchTriggers.PLAY_RESUMED)

	func is_transaction_stateless() -> bool:
		return true

	func snapshot_is_complete() -> bool:
		return true


func _config(seed_value: int) -> MatchConfig:
	var config: MatchConfig = S2_TEST_SETUP.match_config(seed_value)
	config.slot_count = SLOT_COUNT
	config.axes_per_slot = AXES_PER_SLOT
	config.period_real_seconds = 1
	return config


func _systems() -> Array[SimSystem]:
	var systems: Array[SimSystem] = [TriggerSystem.new()]
	return systems


func _replay_request(
	config: MatchConfig, mod_set_hash: String, action_layout_hash: String
) -> MatchCompositionRequest:
	var request: MatchCompositionRequest = MatchCompositionRequest.new()
	request.config = config
	request.systems = _systems()
	request.mod_set_hash = mod_set_hash
	request.action_layout_hash = action_layout_hash
	request.s2 = S2_TEST_SETUP.runtime_port()
	return request


func _record_ball_state_log(frame_count: int) -> InputLog:
	var frames: Array[InputFrame] = _scripted_frames(frame_count)
	var config: MatchConfig = _config(SIM_SEED)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var start_result: Error = runner.start(
		config,
		_FrameInputSource.new(frames, LAYOUT_HASH),
		_systems(),
		MOD_SET_HASH,
		null,
		null,
		null,
		S2_TEST_SETUP.runtime_port()
	)
	if start_result != OK:
		return null
	for tick_index: int in frame_count:
		var sequence: int = runner.runtime_port.enqueue(
			S2RuntimeCommand.ball_state(BallState.Mode.HELD, BallState.GoalKickState.OFF)
		)
		if sequence != tick_index or not runner.step_once():
			return null
	return InputLog.from_bytes(runner.input_log.to_bytes())


## Scripted input: pseudo-random buttons and axes from a separate fixed-seed generator.
func _scripted_frames(frame_count: int = TICK_COUNT) -> Array[InputFrame]:
	var generator: SimRng = SimRng.new(SCRIPT_SEED)
	var frames: Array[InputFrame] = []
	for tick_index: int in range(frame_count):
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


## C-26: v3 runner/replay hashes held-ball, off-pitch setup.
## It excludes S1 owner lifecycle and collision behavior.
func test_c26_recorded_log_replays_to_same_hash() -> void:
	var frames: Array[InputFrame] = _scripted_frames(20)
	var config: MatchConfig = _config(SIM_SEED)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var start_result: Error = runner.start(
		config,
		_FrameInputSource.new(frames, LAYOUT_HASH),
		_systems(),
		MOD_SET_HASH,
		null,
		null,
		null,
		S2_TEST_SETUP.runtime_port()
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return
	var command_sequence: int = runner.runtime_port.enqueue(
		S2RuntimeCommand.ball_state(BallState.Mode.HELD, BallState.GoalKickState.OFF)
	)
	@warning_ignore("unused_variable")
	var r2a: GdUnitIntAssert = assert_int(command_sequence).is_equal(0)
	if command_sequence < 0:
		return
	for index: int in frames.size():
		var advanced: bool = runner.step_once()
		if not advanced:
			break
	var expected_hash: String = runner.sim.state_hash()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(runner.input_log.frame_count()).is_equal(frames.size())
	var restored: InputLog = InputLog.from_bytes(runner.input_log.to_bytes())
	@warning_ignore("unused_variable")
	var r3: GdUnitObjectAssert = assert_object(restored).is_not_null()
	if restored == null:
		return
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(restored.header.format_version).is_equal(3)
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(restored.header.setup_fingerprint.is_empty()).is_false()
	@warning_ignore("unused_variable")
	var r5a: GdUnitIntAssert = assert_int(restored.frame_commands(0).size()).is_equal(1)
	@warning_ignore("unused_variable")
	var r5b: GdUnitIntAssert = assert_int(restored.frame_outputs(0).size()).is_equal(1)
	var replay_result: MatchReplayResult = MatchReplay.run(
		_replay_request(config, MOD_SET_HASH, LAYOUT_HASH), restored
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitObjectAssert = assert_object(replay_result).is_not_null()
	if replay_result == null:
		return
	@warning_ignore("unused_variable")
	var r6a: GdUnitIntAssert = assert_int(replay_result.error).is_equal(OK)
	@warning_ignore("unused_variable")
	var r6b: GdUnitIntAssert = assert_int(replay_result.replay_failure).is_equal(
		MatchReplayResult.ReplayFailure.NONE
	)
	if replay_result.sim == null:
		return
	@warning_ignore("unused_variable")
	var r7: GdUnitStringAssert = assert_str(replay_result.sim.state_hash()).is_equal(expected_hash)


## C-27: a mod-set mismatch yields typed INCOMPATIBLE_HEADER, non-OK, and no sim.
func test_c27_replay_refuses_different_mod_set() -> void:
	var frames: Array[InputFrame] = _scripted_frames(10)
	var config: MatchConfig = _config(SIM_SEED)
	var runner: MatchRunner = auto_free(MatchRunner.new())
	var start_result: Error = runner.start(
		config,
		_FrameInputSource.new(frames, LAYOUT_HASH),
		_systems(),
		MOD_SET_HASH,
		null,
		null,
		null,
		S2_TEST_SETUP.runtime_port()
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(start_result).is_equal(OK)
	if start_result != OK:
		return
	for index: int in frames.size():
		var advanced: bool = runner.step_once()
		if not advanced:
			break
	var log: InputLog = InputLog.from_bytes(runner.input_log.to_bytes())
	@warning_ignore("unused_variable")
	var r2: GdUnitObjectAssert = assert_object(log).is_not_null()
	if log == null:
		return
	@warning_ignore("unused_variable")
	var recorded_frame_count: GdUnitIntAssert = assert_int(log.frame_count()).is_equal(
		frames.size()
	)
	var compatible_result: MatchReplayResult = MatchReplay.run(
		_replay_request(config, MOD_SET_HASH, LAYOUT_HASH), log
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitObjectAssert = assert_object(compatible_result).is_not_null()
	if compatible_result == null:
		return
	@warning_ignore("unused_variable")
	var r3a: GdUnitIntAssert = assert_int(compatible_result.error).is_equal(OK)
	@warning_ignore("unused_variable")
	var r3b: GdUnitIntAssert = assert_int(compatible_result.replay_failure).is_equal(
		MatchReplayResult.ReplayFailure.NONE
	)
	if compatible_result.sim == null:
		return
	@warning_ignore("unused_variable")
	var r3c: GdUnitStringAssert = assert_str(compatible_result.sim.state_hash()).is_equal(
		runner.sim.state_hash()
	)
	var mismatch_result: MatchReplayResult = MatchReplay.run(
		_replay_request(config, "some-other-mod-set", LAYOUT_HASH), log
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitObjectAssert = assert_object(mismatch_result).is_not_null()
	if mismatch_result == null:
		return
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(mismatch_result.error).is_not_equal(OK)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(mismatch_result.replay_failure).is_equal(
		MatchReplayResult.ReplayFailure.INCOMPATIBLE_HEADER
	)
	@warning_ignore("unused_variable")
	var r7: GdUnitObjectAssert = assert_object(mismatch_result.readiness).is_not_null()
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(mismatch_result.readiness.is_ready()).is_true()
	@warning_ignore("unused_variable")
	var r9: GdUnitObjectAssert = assert_object(mismatch_result.sim).is_null()


## Consecutive frame outputs remain linked to the matching per-frame commands during replay.
func test_replay_compares_outputs_from_consecutive_frames() -> void:
	var log: InputLog = _record_ball_state_log(3)
	@warning_ignore("unused_variable")
	var log_assert: GdUnitObjectAssert = assert_object(log).is_not_null()
	if log == null:
		return
	var output_sequences: Array[int] = []
	var frame_output_counts: Array[int] = []
	for frame_index: int in log.frame_count():
		var commands: Array[Dictionary] = log.frame_commands(frame_index)
		var outputs: Array[Dictionary] = log.frame_outputs(frame_index)
		@warning_ignore("unused_variable")
		var shape_assert: GdUnitBoolAssert = (
			assert_bool(commands.size() == 1 and outputs.size() == 1).is_true()
		)
		if commands.size() != 1 or outputs.size() != 1:
			return
		var output: S2RuntimeResult = S2RuntimeResult.from_snapshot(outputs[0])
		@warning_ignore("unused_variable")
		var output_assert: GdUnitObjectAssert = assert_object(output).is_not_null()
		if output == null:
			return
		@warning_ignore("return_value_discarded")
		frame_output_counts.append(outputs.size())
		@warning_ignore("return_value_discarded")
		output_sequences.append(output.command_sequence)
	@warning_ignore("unused_variable")
	var count_assert: GdUnitArrayAssert = assert_array(frame_output_counts).is_equal([1, 1, 1])
	@warning_ignore("unused_variable")
	var sequence_assert: GdUnitArrayAssert = assert_array(output_sequences).is_equal([0, 1, 2])
	var config: MatchConfig = _config(SIM_SEED)
	var replay_result: MatchReplayResult = MatchReplay.run(
		_replay_request(config, MOD_SET_HASH, LAYOUT_HASH), log
	)
	@warning_ignore("unused_variable")
	var replay_assert: GdUnitIntAssert = assert_int(replay_result.error).is_equal(OK)
	@warning_ignore("unused_variable")
	var failure_assert: GdUnitIntAssert = assert_int(replay_result.replay_failure).is_equal(
		MatchReplayResult.ReplayFailure.NONE
	)
	if replay_result.sim == null:
		return
	@warning_ignore("unused_variable")
	var tick_count_assert: GdUnitIntAssert = assert_int(replay_result.sim.tick_count).is_equal(3)


## A structurally valid but altered second-frame output fails at output comparison.
func test_replay_rejects_tampered_second_frame_output() -> void:
	var source_log: InputLog = _record_ball_state_log(3)
	@warning_ignore("unused_variable")
	var source_assert: GdUnitObjectAssert = assert_object(source_log).is_not_null()
	if source_log == null:
		return
	var tampered_log: InputLog = InputLog.new(source_log.header)
	for frame_index: int in source_log.frame_count():
		var frame: InputFrame = InputFrame.new(
			source_log.header.slot_count, source_log.header.axes_per_slot
		)
		var read_succeeded: bool = source_log.read_frame(frame_index, frame)
		@warning_ignore("unused_variable")
		var read_assert: GdUnitBoolAssert = assert_bool(read_succeeded).is_true()
		if not read_succeeded:
			return
		var commands: Array[Dictionary] = source_log.frame_commands(frame_index)
		var outputs: Array[Dictionary] = source_log.frame_outputs(frame_index)
		if frame_index == 1:
			@warning_ignore("unused_variable")
			var second_frame_shape_assert: GdUnitBoolAssert = (
				assert_bool(commands.size() == 1 and outputs.size() == 1).is_true()
			)
			if commands.size() != 1 or outputs.size() != 1:
				return
			outputs[0]["detail"] = "tampered second-frame result"
		tampered_log.append(frame, commands, outputs)
	@warning_ignore("unused_variable")
	var frame_count_assert: GdUnitIntAssert = assert_int(tampered_log.frame_count()).is_equal(3)
	var tampered_output: S2RuntimeResult = S2RuntimeResult.from_snapshot(
		tampered_log.frame_outputs(1)[0]
	)
	@warning_ignore("unused_variable")
	var valid_shape_assert: GdUnitBoolAssert = assert_bool(tampered_output != null).is_true()
	if tampered_output == null:
		return
	@warning_ignore("unused_variable")
	var detail_assert: GdUnitStringAssert = assert_str(tampered_output.detail).is_equal(
		"tampered second-frame result"
	)
	var config: MatchConfig = _config(SIM_SEED)
	var replay_result: MatchReplayResult = MatchReplay.run(
		_replay_request(config, MOD_SET_HASH, LAYOUT_HASH), tampered_log
	)
	@warning_ignore("unused_variable")
	var error_assert: GdUnitIntAssert = assert_int(replay_result.error).is_not_equal(OK)
	@warning_ignore("unused_variable")
	var failure_assert: GdUnitIntAssert = assert_int(replay_result.replay_failure).is_equal(
		MatchReplayResult.ReplayFailure.OUTPUT_MISMATCH
	)
	@warning_ignore("unused_variable")
	var sim_assert: GdUnitObjectAssert = assert_object(replay_result.sim).is_null()
