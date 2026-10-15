class_name BallPathPredictor
extends RefCounted
## Stateless analytic path stepper kept separate from the rigid-body contact solver.
## Uses configured gravity only; the optional controller force is omitted until its caller supplies
## an explicit force policy.


## Advances one bounded interval using the observed predictor bounce/roll response.
## A non-finite ground-contact time stops prediction without advancing that segment.
static func advance(
	input_state: BallPredictionState, dt: float, params: BallPhysicsParams
) -> BallPredictionState:
	var result: BallPredictionState = BallPredictionState.new()
	result.position_m = input_state.position_m
	result.velocity_m_s = input_state.velocity_m_s
	result.rolling = input_state.rolling
	result.hop_time_s = input_state.hop_time_s
	if params == null or not is_finite(dt) or dt < 0.0:
		return result
	var remaining: float = dt
	var segment_count: int = 0
	while remaining > 0.0:
		if result.rolling:
			_advance_roll(result, minf(remaining, 1.25), params)
			break
		var contact_time: float = _time_to_height(
			result.position_m.y,
			result.velocity_m_s.y,
			params.gravity_m_s2.y,
			params.predictor_rest_height_m
		)
		result.hop_time_s = contact_time
		if not is_finite(contact_time):
			break
		if contact_time > remaining:
			_advance_ballistic(result, remaining, params.gravity_m_s2)
			break
		var flight_time: float = maxf(contact_time, 0.0)
		_advance_ballistic(result, flight_time, params.gravity_m_s2)
		result.position_m.y = params.predictor_rest_height_m
		remaining -= flight_time
		if segment_count > 0 and flight_time < params.predictor_roll_hop_time_s:
			result.rolling = true
			_advance_roll(result, minf(remaining, 1.25), params)
			break
		result.velocity_m_s.y = -result.velocity_m_s.y * params.predictor_roll_restitution
		result.velocity_m_s.x *= params.predictor_roll_horizontal_retention
		result.velocity_m_s.z *= params.predictor_roll_horizontal_retention
		segment_count += 1
		if flight_time <= 0.0:
			break
	return result


static func _time_to_height(
	height: float, vertical_speed: float, gravity_y: float, target_height: float
) -> float:
	var height_above_target: float = maxf(height - target_height, 0.0)
	if gravity_y == 0.0:
		if height_above_target == 0.0 and vertical_speed <= 0.0:
			return 0.0
		return -height_above_target / vertical_speed if vertical_speed < 0.0 else INF
	if gravity_y > 0.0:
		return INF
	if height_above_target == 0.0 and vertical_speed <= 0.0:
		return 0.0
	var discriminant: float = (
		vertical_speed * vertical_speed - 2.0 * gravity_y * height_above_target
	)
	if discriminant < 0.0:
		return INF
	return (-vertical_speed - sqrt(discriminant)) / gravity_y


static func _advance_ballistic(
	state: BallPredictionState, duration: float, gravity: Vector3
) -> void:
	state.position_m += state.velocity_m_s * duration + 0.5 * gravity * duration * duration
	state.velocity_m_s += gravity * duration


static func _advance_roll(
	state: BallPredictionState, duration: float, params: BallPhysicsParams
) -> void:
	state.velocity_m_s.y = 0.0
	var acceleration: Vector3 = Vector3(
		-state.velocity_m_s.x * params.predictor_roll_acceleration,
		0.0,
		-state.velocity_m_s.z * params.predictor_roll_acceleration
	)
	state.position_m += state.velocity_m_s * duration + 0.5 * acceleration * duration * duration
	state.velocity_m_s += acceleration * duration
