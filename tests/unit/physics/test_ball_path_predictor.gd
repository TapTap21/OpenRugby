class_name TestBallPathPredictor
extends GdUnitTestSuite
## Acceptance tests for the analytic predictor, independent of the rigid-body solver.


func _state(position: Vector3, velocity: Vector3) -> BallPredictionState:
	var result: BallPredictionState = BallPredictionState.new()
	result.position_m = position
	result.velocity_m_s = velocity
	return result


## RE 06 §2.5 uses the 0.1 m centre height and later quadratic root.
func test_b02_ballistic_segment_and_first_bounce_match_observed_values() -> void:
	var params: BallPhysicsParams = BallPhysicsParams.new()
	var initial: BallPredictionState = _state(Vector3(0.0, 2.1, 0.0), Vector3(5.0, 0.0, 0.0))
	var before_contact: BallPredictionState = BallPathPredictor.advance(initial, 0.5, params)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(before_contact.position_m.y, 0.875)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(before_contact.velocity_m_s.y, -4.9)).is_true()
	)
	var bounced: BallPredictionState = BallPathPredictor.advance(initial, 0.7, params)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(bounced.velocity_m_s.y, 2.844535)).is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(is_equal_approx(bounced.velocity_m_s.x, 4.425)).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(bounced.position_m.y, 0.292175)).is_true()
	)


## The first hop does not roll; a later hop below 0.01 s rolls, capped at 1.25 s.
func test_b03_later_short_hop_enters_capped_rolling_segment() -> void:
	var params: BallPhysicsParams = BallPhysicsParams.new()
	var initial: BallPredictionState = _state(Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.05, 0.0))
	var short_first_hop: BallPredictionState = _state(
		Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.02, 0.0)
	)
	var first_hop: BallPredictionState = BallPathPredictor.advance(short_first_hop, 0.005, params)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(first_hop.rolling).is_false()
	var long_step: BallPredictionState = BallPathPredictor.advance(initial, 5.0, params)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(long_step.rolling).is_true()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = (
		assert_bool(is_equal_approx(long_step.position_m.x, 0.5683)).is_true()
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(is_equal_approx(long_step.velocity_m_s.x, 0.0)).is_true()
	@warning_ignore("unused_variable")
	var r5: GdUnitFloatAssert = assert_float(long_step.velocity_m_s.y).is_equal(0.0)
	@warning_ignore("unused_variable")
	var r6: GdUnitBoolAssert = assert_bool(is_equal_approx(long_step.position_m.y, 0.1)).is_true()


## A state already marked rolling ignores any residual vertical speed before integration.
func test_b03_existing_rolling_state_keeps_vertical_position_fixed() -> void:
	var params: BallPhysicsParams = BallPhysicsParams.new()
	var initial: BallPredictionState = _state(Vector3(0.0, 0.1, 0.0), Vector3(1.0, 4.0, 0.0))
	initial.rolling = true
	var result: BallPredictionState = BallPathPredictor.advance(initial, 0.5, params)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(is_equal_approx(result.position_m.y, 0.1)).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(result.velocity_m_s.y).is_equal(0.0)


## A non-finite contact time terminates prediction without ballistic extrapolation.
func test_b15_non_finite_contact_time_stops_without_advancing() -> void:
	var params: BallPhysicsParams = BallPhysicsParams.new()
	params.gravity_m_s2 = Vector3.ZERO
	var initial: BallPredictionState = _state(Vector3(2.0, 0.1, -3.0), Vector3(1.0, 1.0, 0.0))
	var result: BallPredictionState = BallPathPredictor.advance(initial, 2.0, params)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = (
		assert_bool(result.position_m.is_equal_approx(initial.position_m)).is_true()
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = (
		assert_bool(result.velocity_m_s.is_equal_approx(initial.velocity_m_s)).is_true()
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(is_inf(result.hop_time_s)).is_true()
