class_name TestContactLcpContract
extends GdUnitTestSuite
## Acceptance checks for response behavior recovered from RE 06 §2.4.


func test_b07_condition_two_restitution_endpoints_and_interpolation() -> void:
	var surfaces: PitchSurfaceTable = PitchSurfaceTable.create_classic()
	var condition_two: PitchSurfaceParams = surfaces.get_for(2, 0)

	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(condition_two.restitution(0.0), 0.5)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(condition_two.restitution(1.0), 0.4)).is_true()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(condition_two.restitution(-1.0), 0.4)).is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(condition_two.restitution(0.5), 0.475)).is_true()
	)
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(is_equal_approx(condition_two.friction, 0.7)).is_true()


func test_compiled_out_bounce_randomness_does_not_change_restitution() -> void:
	var surface: PitchSurfaceParams = PitchSurfaceParams.new()
	var original_restitution: float = surface.restitution(0.4)
	surface.unused_bounce_randomness = 0.0
	var zero_randomness_result: float = surface.restitution(0.4)
	surface.unused_bounce_randomness = 0.2
	var configured_randomness_result: float = surface.restitution(0.4)

	@warning_ignore("unused_variable")
	var r1: GdUnitFloatAssert = assert_float(zero_randomness_result).is_equal(original_restitution)
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(configured_randomness_result).is_equal(
		original_restitution
	)


func test_unimplemented_solver_cannot_claim_availability_or_mutate_state() -> void:
	var solver: BallContactSolver = BallContactSolver.new()
	var state: BallState = BallState.new()
	state.position_m = Vector3(3.0, 1.0, -2.0)
	state.linear_velocity_m_s = Vector3(5.0, 2.0, -1.0)
	state.angular_velocity_rad_s = Vector3(0.5, 0.2, -0.3)
	var before: Dictionary = state.snapshot()
	var solved: bool = solver.solve_contacts(state, [], [], 1.0 / 200.0)

	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(solver.is_available()).is_false()
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(solved).is_false()
	@warning_ignore("unused_variable")
	var r3: GdUnitDictionaryAssert = assert_dict(state.snapshot()).is_equal(before)
