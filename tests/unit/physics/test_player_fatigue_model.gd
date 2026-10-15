class_name TestPlayerFatigueModel
extends GdUnitTestSuite
## RE 09 fatigue curve, ordered owner state, accrual, recovery, and rollback.


func _model() -> PlayerFatigueModel:
	return PlayerFatigueModel.new()


func _add(
	model: PlayerFatigueModel,
	team: StringName,
	player: StringName,
	shirt: int,
	stamina: int,
	fatigue: float,
	pitch: bool
) -> bool:
	return model.add_player(team, player, shirt, stamina, 94, 94, fatigue, pitch, -1.0)


## The observed full-time curve and percent conversion preserve the exact truncate boundary.
func test_f01_energy_curve_matches_re09_endpoints() -> void:
	var model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r1: GdUnitFloatAssert = assert_float(model.energy(100, 0.0)).is_equal(100.0)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(model.energy_percent(model.energy(100, 0.0))).is_equal(100)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(model.energy(40, 4800.0)).is_equal(40.0)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(model.energy_percent(model.energy(40, 4800.0))).is_equal(9)
	@warning_ignore("unused_variable")
	var r5: GdUnitFloatAssert = assert_float(model.energy(100, 4800.0)).is_equal(90.0)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(model.energy_percent(model.energy(100, 4800.0))).is_equal(
		84
	)
	@warning_ignore("unused_variable")
	var r7: GdUnitFloatAssert = assert_float(model.energy(100, 2400.0)).is_equal(97.5)


## Stable snapshots sort team/shirt, while derived skill penalties use integer truncation.
func test_f02_snapshot_order_and_skill_penalty_rounding() -> void:
	var model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(_add(model, &"away", &"away_1", 1, 100, 4800.0, true)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"home_1", 1, 40, 0.0, true)).is_true()
	)
	var entries: Array = model.snapshot()["entries"]
	var first_team_id: StringName = entries[0]["team_id"]
	var second_team_id: StringName = entries[1]["team_id"]
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(first_team_id == &"away").is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(second_team_id == &"home").is_true()
	var fatigue: PlayerFatigueSnapshot = model.fatigue_snapshot(&"away", 1)
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(fatigue.energy_percent).is_equal(84)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(fatigue.effective_passing).is_equal(89)
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(fatigue.effective_tackling).is_equal(86)
	@warning_ignore("unused_variable")
	var r8: GdUnitFloatAssert = assert_float(fatigue.initial_sprint_energy).is_equal(-1.0)


## Raw Tackling may fall to −45; Passing keeps the S2-required zero clamp.
func test_f03_low_stats_keep_raw_tackling_and_clamped_passing() -> void:
	var model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(model.add_player(&"home", &"low_stats", 1, 40, 0, 0, 4800.0, true, -1.0))
		. is_true()
	)
	var fatigue: PlayerFatigueSnapshot = model.fatigue_snapshot(&"home", 1)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(fatigue != null).is_true()
	if fatigue != null:
		@warning_ignore("unused_variable")
		var r3: GdUnitIntAssert = assert_int(fatigue.energy_percent).is_equal(9)
		@warning_ignore("unused_variable")
		var r4: GdUnitIntAssert = assert_int(fatigue.effective_passing).is_equal(0)
		@warning_ignore("unused_variable")
		var r5: GdUnitIntAssert = assert_int(fatigue.effective_tackling).is_equal(-45)
		@warning_ignore("unused_variable")
		var r6: GdUnitBoolAssert = assert_bool(fatigue.is_valid()).is_true()


## The owner accrues only the caller-designated on-pitch player and rejects invalid deltas.
func test_f03_accrual_is_on_pitch_only_and_delta_is_injected() -> void:
	var model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"starter", 1, 75, 10.0, true)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"bench", 16, 75, 20.0, false)).is_true()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"extra", 17, 75, 30.0, true)).is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(model.advance_frame(0.25)).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitFloatAssert = (
		assert_float(model.fatigue_snapshot(&"home", 1).fatigue_time_s).is_equal(10.25)
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitFloatAssert = (
		assert_float(model.fatigue_snapshot(&"home", 16).fatigue_time_s).is_equal(20.0)
	)
	@warning_ignore("unused_variable")
	var r7: GdUnitFloatAssert = (
		assert_float(model.fatigue_snapshot(&"home", 17).fatigue_time_s).is_equal(30.0)
	)
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = assert_bool(model.advance_frame(-0.1)).is_false()
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(model.advance_frame(NAN)).is_false()


## Halftime recovery is 300 match-seconds for registered matchday shirts, floored at zero.
func test_f04_halftime_recovers_on_and_off_pitch_entries() -> void:
	var model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"low", 1, 60, 200.0, true)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"bench", 22, 60, 450.0, false)).is_true()
	)
	model.recover_at_halftime()
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = (
		assert_float(model.fatigue_snapshot(&"home", 1).fatigue_time_s).is_equal(0.0)
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitFloatAssert = (
		assert_float(model.fatigue_snapshot(&"home", 22).fatigue_time_s).is_equal(150.0)
	)


## Restore returns exact fatigue results and rejects malformed state without partial mutation.
func test_f05_snapshot_restore_is_deterministic_and_atomic() -> void:
	var model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(_add(model, &"home", &"home_1", 1, 88, 77.25, true)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(_add(model, &"away", &"away_1", 1, 44, 120.5, false)).is_true()
	)
	var checkpoint: Dictionary = model.snapshot()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(model.advance_frame(1.0)).is_true()
	model.recover_at_halftime()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(model.restore_snapshot(checkpoint)).is_true()
	var restored_snapshot: Dictionary = model.snapshot()
	@warning_ignore("unused_variable")
	var r5: GdUnitDictionaryAssert = assert_dict(restored_snapshot).is_equal(checkpoint)
	var restored_fatigue: PlayerFatigueSnapshot = model.fatigue_snapshot(&"home", 1)
	var expected_model: PlayerFatigueModel = _model()
	@warning_ignore("unused_variable")
	var r6: GdUnitBoolAssert = (
		assert_bool(_add(expected_model, &"home", &"home_1", 1, 88, 77.25, true)).is_true()
	)
	@warning_ignore("unused_variable")
	var r7: GdUnitFloatAssert = assert_float(restored_fatigue.energy_cap).is_equal(
		expected_model.fatigue_snapshot(&"home", 1).energy_cap
	)
	var different_params: PlayerFatigueParams = PlayerFatigueParams.new()
	different_params.halftime_recovery_s = 301.0
	var differently_configured: PlayerFatigueModel = PlayerFatigueModel.new(different_params)
	@warning_ignore("unused_variable")
	var r8: GdUnitBoolAssert = (
		assert_bool(differently_configured.restore_snapshot(checkpoint)).is_false()
	)
	var malformed: Dictionary = checkpoint.duplicate(true)
	malformed["entries"][0]["shirt"] = 0
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(model.restore_snapshot(malformed)).is_false()
	@warning_ignore("unused_variable")
	var r10: GdUnitDictionaryAssert = assert_dict(model.snapshot()).is_equal(checkpoint)
