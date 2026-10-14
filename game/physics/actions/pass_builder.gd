class_name PassBuilder
extends RefCounted
## Builds known ballistic pass primitives from caller-resolved target data.


## Returns observed flight time; unknown category mappings must be resolved by the caller.
static func flight_time(
	pass_type: int,
	passing: float,
	params: PassParams,
	lead: bool = false,
	non_natural_nine: bool = false,
	training: bool = false
) -> float:
	if params == null:
		return NAN
	var duration: float
	if pass_type == 0:
		duration = params.lead_time_s if lead else params.normal_time_s
	elif pass_type in params.fixed_time_050_types:
		duration = params.fixed_time_050_s
	elif pass_type in params.fixed_time_070_types:
		duration = params.fixed_time_070_s
	elif pass_type in [1, 2, 4, 5, 9, 10]:
		duration = (
			params.passing_time_low_s
			- (
				params.passing_time_span_s
				* clampf(passing, 0.0, params.passing_stat_max)
				/ params.passing_stat_max
			)
		)
	else:
		return NAN
	if non_natural_nine and not training and pass_type in params.non_natural_nine_types:
		duration *= params.passing_multiplier_non_natural_nine
	return duration


## Ballistic solution; target height must be injected, never guessed.
static func ballistic_launch(
	start_m: Vector3, target_m: Vector3, flight_time_s: float, gravity_m_s2: Vector3
) -> PassLaunch:
	var launch: PassLaunch = PassLaunch.new()
	launch.target_m = target_m
	launch.flight_time_s = flight_time_s
	if not is_finite(flight_time_s) or flight_time_s <= 0.0 or not gravity_m_s2.is_finite():
		launch.unresolved = true
		return launch
	launch.velocity_m_s = (
		(target_m - start_m - 0.5 * gravity_m_s2 * flight_time_s * flight_time_s) / flight_time_s
	)
	return launch


## Applies observed forward-assist flattening. Setting zero is a no-op.
static func apply_forward_assist(
	velocity: Vector3, setting: int, attack_direction: float, rng: SimRng, params: PassParams
) -> Vector3:
	if params == null or setting <= 0:
		return velocity
	if velocity.z * attack_direction >= 0.0:
		return velocity
	if absf(velocity.z) < params.forward_assist_min_speed_m_s:
		velocity.z = -params.forward_flatten_speed_m_s * attack_direction
		return velocity
	if rng == null:
		return Vector3(NAN, NAN, NAN)
	var probability: float = params.forward_assist_probabilities[clampi(
		setting - 1, 0, params.forward_assist_probabilities.size() - 1
	)]
	if rng.next_float() < probability:
		velocity.z = -params.forward_flatten_speed_m_s * attack_direction
	return velocity


## Adds observed ahead offset and lead x scaling to a caller-predicted receiver position.
static func resolve_target(
	predicted_receiver_m: Vector3, attack_direction: float, lead: bool, params: PassParams
) -> Vector3:
	if params == null:
		return Vector3(NAN, NAN, NAN)
	var target: Vector3 = predicted_receiver_m
	target.x *= params.lead_receiver_x_scale if lead else 1.0
	target.z += (
		attack_direction
		* (params.lead_forward_offset_m if lead else params.normal_forward_offset_m)
	)
	return target


## Observed cap used only when the caller explicitly has no receiver.
static func cap_without_receiver(velocity: Vector3, params: PassParams) -> Vector3:
	if params == null:
		return Vector3(NAN, NAN, NAN)
	var speed: float = velocity.length()
	if speed > params.no_receiver_speed_cap_m_s:
		return velocity.normalized() * params.no_receiver_speed_cap_m_s
	return velocity
