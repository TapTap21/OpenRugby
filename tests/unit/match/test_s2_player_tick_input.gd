class_name TestS2PlayerTickInput
extends GdUnitTestSuite
## Direction intent is typed and replay-safe; it never samples live devices.


func _fatigue() -> PlayerFatigueSnapshot:
	var fatigue: PlayerFatigueSnapshot = PlayerFatigueSnapshot.new()
	fatigue.team_id = &"home"
	fatigue.player_id = &"home-1"
	fatigue.shirt_number = 1
	fatigue.fatigue_time_s = 0.0
	fatigue.energy_cap = 80.0
	fatigue.energy_percent = 100
	fatigue.effective_passing = 70
	fatigue.effective_tackling = 70
	fatigue.initial_sprint_energy = 80.0
	return fatigue


func _make_input() -> S2PlayerTickInput:
	var value: S2PlayerTickInput = S2PlayerTickInput.new()
	value.player_id = &"home-1"
	value.sprint_request = 0
	value.urgency = 0.5
	value.fatigue_snapshot = _fatigue()
	return value


## Direction values share InputFrame's signed quantization and survive command replay.
func test_m01_direction_intent_validates_and_round_trips() -> void:
	var value: S2PlayerTickInput = _make_input()
	value.move_x_q = 127
	value.move_z_q = -127
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(value.is_valid()).is_true()
	var command: S2RuntimeCommand = S2RuntimeCommand.player_tick_input(value)
	command.sequence = 0
	var restored: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(command.snapshot())
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(restored != null).is_true()
	if restored != null:
		@warning_ignore("unused_variable")
		var r3: GdUnitIntAssert = assert_int(restored.player_input.move_x_q).is_equal(127)
		@warning_ignore("unused_variable")
		var r4: GdUnitIntAssert = assert_int(restored.player_input.move_z_q).is_equal(-127)
	var legacy_snapshot: Dictionary = command.snapshot()
	var legacy_input: Dictionary = legacy_snapshot["player_input"]
	@warning_ignore("return_value_discarded")
	legacy_input.erase("move_x_q")
	@warning_ignore("return_value_discarded")
	legacy_input.erase("move_z_q")
	legacy_snapshot["player_input"] = legacy_input
	var legacy_restored: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(legacy_snapshot)
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(legacy_restored != null).is_true()
	if legacy_restored != null:
		@warning_ignore("unused_variable")
		var r6: GdUnitIntAssert = assert_int(legacy_restored.player_input.move_x_q).is_equal(0)
		@warning_ignore("unused_variable")
		var r7: GdUnitIntAssert = assert_int(legacy_restored.player_input.move_z_q).is_equal(0)
	var partial_snapshot: Dictionary = command.snapshot()
	var partial_input: Dictionary = partial_snapshot["player_input"]
	@warning_ignore("return_value_discarded")
	partial_input.erase("move_z_q")
	partial_snapshot["player_input"] = partial_input
	var partial_restored: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(partial_snapshot)
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(partial_restored == null).is_true()
	var wrong_type_snapshot: Dictionary = command.snapshot()
	var wrong_type_input: Dictionary = wrong_type_snapshot["player_input"]
	wrong_type_input["move_x_q"] = "127"
	wrong_type_snapshot["player_input"] = wrong_type_input
	var wrong_type_restored: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(wrong_type_snapshot)
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(wrong_type_restored == null).is_true()


## Out-of-range pitch-plane direction is rejected before it can enter the sim command queue.
func test_m02_direction_intent_rejects_out_of_range_axes() -> void:
	var value: S2PlayerTickInput = _make_input()
	value.move_x_q = 128
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(value.is_valid()).is_false()
	value.move_x_q = -128
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(value.is_valid()).is_false()
	value.move_x_q = 0
	value.move_z_q = 128
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(value.is_valid()).is_false()
	value.move_z_q = -128
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(value.is_valid()).is_false()


## Nonzero intent resolves desired heading; neutral retention is a provisional rebuild policy.
func test_m03_locomotion_resolves_direction_and_preserves_on_neutral() -> void:
	var state: PlayerMotionState = PlayerMotionState.new()
	state.player_id = &"home-1"
	state.team_id = &"home"
	state.shirt_number = 1
	state.desired_heading_turns = 0.125
	var locomotion: LocomotionSystem = LocomotionSystem.new()
	locomotion.players = [state]
	var east: S2PlayerTickInput = _make_input()
	east.move_x_q = 127
	var east_applied: bool = locomotion._apply_player_input(east)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(east_applied).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(locomotion.players[0].desired_heading_turns, 0.25)).is_true()
	)
	var neutral: S2PlayerTickInput = _make_input()
	var neutral_applied: bool = locomotion._apply_player_input(neutral)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(neutral_applied).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(locomotion.players[0].desired_heading_turns, 0.25)).is_true()
	)
