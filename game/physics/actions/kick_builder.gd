class_name KickBuilder
extends RefCounted
## Constructs observed kick launch values using injected patchable tuning.


## Builds launch from a known kick type and seeded RNG. Missing profiles/meter data stay unresolved.
static func build(
	kick_type: int,
	gauge: float,
	kicking_power: float,
	kick_accuracy: float,
	heading_radians: float,
	rng: SimRng,
	params: KickParams,
	difficulty: int,
	ai_place: bool,
	place_meter: PlaceKickMeterResult
) -> KickLaunch:
	var launch: KickLaunch = KickLaunch.new()
	launch.kick_type = kick_type
	var profile: KickProfile = params.get_profile(kick_type) if params != null else null
	if profile == null or rng == null or params == null or not params.validate().is_empty():
		launch.unresolved = true
		return launch
	if (
		not is_finite(gauge)
		or not is_finite(kicking_power)
		or not is_finite(kick_accuracy)
		or not is_finite(heading_radians)
	):
		launch.unresolved = true
		return launch
	if kick_type == 4 or kick_type == 5:
		if place_meter == null or not place_meter.is_valid():
			launch.unresolved = true
			return launch
		var meter_scale: float = _needle_multiplier(absf(place_meter.needle_error), params)
		var speed: float = (
			params.place_speed_min_m_s
			+ (
				(params.place_speed_max_m_s - params.place_speed_min_m_s)
				* place_meter.raw_gauge
				* meter_scale
			)
		)
		var place_elevation: float = (
			profile.elevation_low_degrees
			+ (
				(profile.elevation_high_degrees - profile.elevation_low_degrees)
				* place_meter.raw_gauge
			)
		)
		launch = _launch_vector(launch, speed, place_elevation, heading_radians)
		if ai_place:
			var spread: float = params.ai_place_spread
			launch.velocity_m_s.x *= 1.0 + (spread if rng.next_int() % 2 == 0 else -spread)
		return launch
	var power_rating: float = (
		(25.0 + 0.75 * kicking_power) / 100.0 if profile.power_rating_applies else 1.0
	)
	var bounded_gauge: float = clampf(gauge, 0.0, 1.0)
	var speed_value: float = (
		profile.speed_low_m_s
		+ (profile.speed_high_m_s - profile.speed_low_m_s) * bounded_gauge * power_rating
	)
	var elevation: float = (
		profile.elevation_low_degrees
		+ (profile.elevation_high_degrees - profile.elevation_low_degrees) * bounded_gauge
	)
	var aim_half_width: float = (
		(1.0 - (kick_accuracy - 50.0) / 50.0) * params.aim_error_scale_degrees
	)
	if kick_type == 8:
		if difficulty < 1 or difficulty >= params.drop_kick_difficulty_multipliers.size():
			launch.unresolved = true
			return launch
		aim_half_width *= params.drop_kick_difficulty_multipliers[difficulty]
	var aim_yaw: float = (
		rng.range_float(-aim_half_width, aim_half_width)
		if kick_type in [1, 2, 7, 8, 9, 10, 11, 12]
		else 0.0
	)
	if kick_type == 3:
		elevation += rng.range_float(
			-params.grubber_elevation_jitter_degrees, params.grubber_elevation_jitter_degrees
		)
	if kick_type == 2 or kick_type == 6:
		var spin_limit: float = params.random_spin_limit_rad_s
		launch.spin_rad_s = Vector3(
			rng.range_float(-spin_limit, spin_limit),
			rng.range_float(-spin_limit, spin_limit),
			rng.range_float(-spin_limit, spin_limit)
		)
	elif kick_type in [4, 5, 7, 8, 10]:
		launch.spin_rad_s = Vector3(0.0, params.fixed_spin_rad_s, 0.0)
	elif kick_type == 3:
		launch.spin_rad_s = Vector3(0.0, params.grubber_spin_rad_s, 0.0)
	elif kick_type == 13:
		launch.spin_rad_s = Vector3(0.0, 0.0, params.quick_tap_spin_rad_s)
	return _launch_vector(launch, speed_value, elevation, heading_radians + deg_to_rad(aim_yaw))


static func _needle_multiplier(error: float, params: KickParams) -> float:
	if error <= 1.0:
		return params.place_needle_error_full_factor
	if error <= 2.0:
		return (
			params.place_needle_floor
			+ (params.place_needle_error_full_factor - params.place_needle_floor) * (2.0 - error)
		)
	return params.place_needle_floor


static func _launch_vector(
	launch: KickLaunch, speed: float, elevation: float, heading: float
) -> KickLaunch:
	var angle: float = deg_to_rad(elevation)
	launch.velocity_m_s = (
		Vector3(sin(heading) * cos(angle), sin(angle), cos(heading) * cos(angle)) * speed
	)
	return launch
