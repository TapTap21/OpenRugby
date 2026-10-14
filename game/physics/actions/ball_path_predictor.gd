class_name BallPathPredictor
extends RefCounted
## Stateless analytic path stepper kept separate from the rigid-body contact solver.


## Advances one bounded interval and applies the observed predictor bounce/roll response.
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
	var rest_height_m: float = params.predictor_rest_height_m
	if result.rolling:
		var deceleration: Vector3 = Vector3(
			-result.velocity_m_s.x * params.predictor_roll_acceleration,
			0.0,
			-result.velocity_m_s.z * params.predictor_roll_acceleration
		)
		result.position_m += result.velocity_m_s * dt + 0.5 * deceleration * dt * dt
		result.velocity_m_s += deceleration * dt
		result.velocity_m_s.y = 0.0
		return result
	var gravity_y: float = params.gravity_m_s2.y
	var contact_time: float = _time_to_height(
		result.position_m.y, result.velocity_m_s.y, gravity_y, rest_height_m
	)
	result.hop_time_s = contact_time
	if contact_time > dt:
		result.position_m += result.velocity_m_s * dt + 0.5 * params.gravity_m_s2 * dt * dt
		result.velocity_m_s += params.gravity_m_s2 * dt
		return result
	var flight_dt: float = maxf(contact_time, 0.0)
	result.position_m += (
		result.velocity_m_s * flight_dt + 0.5 * params.gravity_m_s2 * flight_dt * flight_dt
	)
	result.velocity_m_s += params.gravity_m_s2 * flight_dt
	result.position_m.y = rest_height_m
	var remainder: float = dt - flight_dt
	result.velocity_m_s.x *= params.predictor_roll_horizontal_retention
	result.velocity_m_s.z *= params.predictor_roll_horizontal_retention
	result.velocity_m_s.y = -result.velocity_m_s.y * params.predictor_roll_restitution
	var next_hop: float = _time_to_height(
		rest_height_m, result.velocity_m_s.y, gravity_y, rest_height_m
	)
	if next_hop < params.predictor_roll_hop_time_s:
		result.rolling = true
		result.hop_time_s = next_hop
		var roll_acceleration: Vector3 = Vector3(
			-result.velocity_m_s.x * params.predictor_roll_acceleration,
			0.0,
			-result.velocity_m_s.z * params.predictor_roll_acceleration
		)
		result.position_m += (
			result.velocity_m_s * remainder + 0.5 * roll_acceleration * remainder * remainder
		)
		result.velocity_m_s += roll_acceleration * remainder
		result.velocity_m_s.y = 0.0
	else:
		result.hop_time_s = next_hop
		result.position_m += (
			result.velocity_m_s * remainder + 0.5 * params.gravity_m_s2 * remainder * remainder
		)
		result.velocity_m_s += params.gravity_m_s2 * remainder
	return result


static func _time_to_height(
	height: float, vertical_speed: float, gravity_y: float, target_height: float
) -> float:
	if (
		gravity_y >= 0.0
		or height < target_height
		or (height == target_height and vertical_speed <= 0.0)
	):
		return 0.0
	var discriminant: float = (
		vertical_speed * vertical_speed - 2.0 * gravity_y * (height - target_height)
	)
	if discriminant < 0.0:
		return INF
	var root_a: float = (-vertical_speed - sqrt(discriminant)) / gravity_y
	var root_b: float = (-vertical_speed + sqrt(discriminant)) / gravity_y
	if root_a > 0.000001 and root_b > 0.000001:
		return minf(root_a, root_b)
	if root_a > 0.000001:
		return root_a
	if root_b > 0.000001:
		return root_b
	return 0.0
