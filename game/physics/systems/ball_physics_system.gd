class_name BallPhysicsSystem
extends SimSystem
## Deterministic ball force integration with the S2 rational 200 Hz accumulator.

const ACCUMULATOR_THRESHOLD: int = 60
const TICK_NUMERATOR: int = 200

var params: BallPhysicsParams
var surfaces: PitchSurfaceTable
var contact_source: BallContactSource
var contact_solver: BallContactSolver
var pitch_condition: int = -1
var stadium_id: int = -1
var extension_points: ExtensionPoints
var wind_policy_resolved: bool = false
var wind_enabled: bool = false
var wind_km_h: Vector3 = Vector3.ZERO
var state: BallState = BallState.new()
## Injected contacts are consumed in deterministic sorted order at the next solver step.
var pending_contacts: Array[BallContact] = []
## This is an explicit post-action lifecycle/mode input from the match composition layer.
var match_active: bool = false
var last_substeps: int = 0
var last_post_part: int = 0
var mod_issues: PackedStringArray = []


func _init(
	p_params: BallPhysicsParams = null,
	p_surfaces: PitchSurfaceTable = null,
	p_contact_source: BallContactSource = null,
	p_contact_solver: BallContactSolver = null
) -> void:
	params = p_params
	surfaces = p_surfaces
	contact_source = p_contact_source
	contact_solver = p_contact_solver


## Initializes a newly created body and consumes its observed per-axis spin jitter draws.
func initialize_new_body(position_m: Vector3, orientation: Quaternion, rng: SimRng) -> bool:
	if (
		params == null
		or rng == null
		or not position_m.is_finite()
		or not _quaternion_is_finite(orientation)
	):
		return false
	state.position_m = position_m
	state.orientation = orientation.normalized()
	var jitter: float = params.initial_spin_jitter_rad_s
	state.angular_velocity_rad_s = Vector3(
		rng.range_float(-jitter, jitter),
		rng.range_float(-jitter, jitter),
		rng.range_float(-jitter, jitter)
	)
	state.linear_velocity_m_s = Vector3.ZERO
	state.mode = BallState.Mode.UNRESOLVED
	state.goal_kick_state = BallState.GoalKickState.UNRESOLVED
	state.solver_accumulator = 0
	return true


## Stable system identifier included in MatchSim snapshots.
func system_id() -> StringName:
	return &"s2_ball_physics"


## Advances only when valid tuning has been injected and S2's active gate is true.
func tick(sim: MatchSim) -> void:
	last_substeps = 0
	match_active = sim.is_simulation_active()
	if params == null or not params.validate().is_empty():
		mod_issues += PackedStringArray(["ball physics parameters are missing or invalid"])
		return
	if (
		not match_active
		or (state.mode != BallState.Mode.FREE_FLIGHT and state.mode != BallState.Mode.ROLLING)
	):
		return
	if state.goal_kick_state == BallState.GoalKickState.UNRESOLVED:
		mod_issues += PackedStringArray(
			["ball goal-kick state is unresolved; solver step unavailable"]
		)
		return
	if state.goal_kick_state == BallState.GoalKickState.ACTIVE and not wind_policy_resolved:
		mod_issues += PackedStringArray(
			["goal-kick wind policy is unresolved; solver step unavailable"]
		)
		return
	var state_before_tick: BallState = _copy_ball_state(state)
	var accumulator_before_tick: int = state.solver_accumulator
	var post_part_before_tick: int = last_post_part
	state.solver_accumulator += TICK_NUMERATOR
	while state.solver_accumulator >= ACCUMULATOR_THRESHOLD:
		state.solver_accumulator -= ACCUMULATOR_THRESHOLD
		if not _integrate_step(
			float(params.solver_step_numerator) / float(params.solver_step_denominator)
		):
			state = state_before_tick
			state.solver_accumulator = accumulator_before_tick
			last_post_part = post_part_before_tick
			last_substeps = 0
			return
		last_substeps += 1


## Returns sim-owned state and diagnostic outputs for replay hashing.
func snapshot() -> Dictionary:
	return {
		"ball": state.snapshot(),
		"params": _resource_snapshot(params),
		"surfaces": _resource_snapshot(surfaces),
		"contact_source": contact_source.snapshot() if contact_source != null else {},
		"contact_solver": contact_solver.snapshot() if contact_solver != null else {},
		"pitch_condition": pitch_condition,
		"stadium_id": stadium_id,
		"match_active": match_active,
		"last_substeps": last_substeps,
		"last_post_part": last_post_part,
		"wind_policy_resolved": wind_policy_resolved,
		"wind_enabled": wind_enabled,
		"wind_km_h": [wind_km_h.x, wind_km_h.y, wind_km_h.z],
		"pending_contacts": _contacts_snapshot(pending_contacts),
		"mod_issues": Array(mod_issues),
	}


## Injects extension points and resolves the first non-null match wind provider once.
func configure_extensions(points: ExtensionPoints, config: MatchConfig) -> void:
	extension_points = points
	if extension_points == null:
		return
	for provider: Callable in extension_points.hooks(BaseExtensionPoints.PHYSICS_WIND_PROVIDER):
		var provided: Variant = provider.call(config)
		if provided == null:
			continue
		if not provided is Vector3:
			mod_issues += PackedStringArray(["physics.wind_provider returned an invalid vector"])
			return
		@warning_ignore("unsafe_cast")
		var provided_wind: Vector3 = provided
		if not provided_wind.is_finite():
			mod_issues += PackedStringArray(["physics.wind_provider returned an invalid vector"])
			return
		wind_km_h = provided_wind
		wind_enabled = true
		wind_policy_resolved = true
		return


## Allows the owning match environment to explicitly resolve wind off or inject its vector.
func set_wind_policy(enabled: bool, vector_km_h: Vector3) -> bool:
	if not vector_km_h.is_finite():
		return false
	wind_policy_resolved = true
	wind_enabled = enabled
	wind_km_h = vector_km_h
	return true


## Commits a validated launch after filters have completed.
func commit_kick(launch: KickLaunch) -> bool:
	if launch == null or launch.unresolved or not _valid_launch(launch):
		return false
	state.linear_velocity_m_s = launch.velocity_m_s
	state.angular_velocity_rad_s = launch.spin_rad_s
	state.mode = BallState.Mode.FREE_FLIGHT
	return true


func commit_pass(launch: PassLaunch) -> bool:
	if launch == null or launch.unresolved or not _valid_vector(launch.velocity_m_s):
		return false
	state.linear_velocity_m_s = launch.velocity_m_s
	state.mode = BallState.Mode.FREE_FLIGHT
	return true


## Holds the ball after a resolved catch or pickup.
func hold_ball() -> void:
	state.mode = BallState.Mode.HELD
	state.linear_velocity_m_s = Vector3.ZERO
	state.angular_velocity_rad_s = Vector3.ZERO


## Applies the typed spill output while keeping ball mutation under this system's ownership.
func apply_spill(result: TackleResult) -> bool:
	if (
		result == null
		or result.unresolved
		or not result.spilled_ball
		or not is_finite(result.ball_velocity_scale)
	):
		return false
	state.linear_velocity_m_s *= result.ball_velocity_scale
	state.mode = BallState.Mode.FREE_FLIGHT
	return true


## Applies gravity and goal-kick drag for a caller-provided velocity and wind policy.
func acceleration_m_s2(velocity: Vector3, wind_km_h: Vector3) -> Vector3:
	if params == null:
		return Vector3.ZERO
	var acceleration: Vector3 = params.gravity_m_s2
	if state.goal_kick_state == BallState.GoalKickState.UNRESOLVED:
		return Vector3(NAN, NAN, NAN)
	if state.goal_kick_state == BallState.GoalKickState.ACTIVE:
		var relative_air: Vector3 = wind_km_h * params.wind_km_h_to_m_s - velocity
		var speed: float = relative_air.length()
		var cd: float = params.drag_coefficient_low
		if speed >= params.drag_speed_high_m_s:
			cd = params.drag_coefficient_high
		elif speed > params.drag_speed_low_m_s:
			var blend: float = (
				(speed - params.drag_speed_low_m_s)
				/ (params.drag_speed_high_m_s - params.drag_speed_low_m_s)
			)
			cd = lerpf(params.drag_coefficient_low, params.drag_coefficient_high, blend)
		var area: float = (
			_projected_area(relative_air)
			if speed > params.drag_reference_speed_threshold_m_s
			else params.reference_area_slow_m2
		)
		var drag: Vector3 = (
			Vector3(
				absf(relative_air.x) * relative_air.x,
				absf(relative_air.y) * relative_air.y,
				absf(relative_air.z) * relative_air.z
			)
			* (0.5 * params.air_density_kg_m3 * cd * area / params.mass_kg)
		)
		acceleration += drag
	return acceleration


func launch_kick(
	kick_type: int,
	gauge: float,
	kicking_power: float,
	kick_accuracy: float,
	heading_radians: float,
	rng: SimRng,
	kick_params: KickParams,
	difficulty: int,
	ai_place: bool,
	place_meter: PlaceKickMeterResult
) -> KickLaunch:
	var launch: KickLaunch = KickBuilder.build(
		kick_type,
		gauge,
		kicking_power,
		kick_accuracy,
		heading_radians,
		rng,
		kick_params,
		difficulty,
		ai_place,
		place_meter
	)
	if launch.unresolved or extension_points == null:
		return launch
	var filtered: Variant = extension_points.filter(
		BaseExtensionPoints.PHYSICS_KICK_LAUNCH, _copy_kick_launch(launch)
	)
	if not filtered is KickLaunch:
		mod_issues += PackedStringArray(["physics.kick_launch returned an invalid result"])
		return launch
	@warning_ignore("unsafe_cast")
	var filtered_launch: KickLaunch = filtered
	if not _valid_launch(filtered_launch) or filtered_launch.kick_type != launch.kick_type:
		mod_issues += PackedStringArray(["physics.kick_launch returned an invalid result"])
		return launch
	launch.velocity_m_s = filtered_launch.velocity_m_s
	launch.spin_rad_s = filtered_launch.spin_rad_s
	return launch


func filter_pass_launch(launch: PassLaunch) -> PassLaunch:
	if launch == null or launch.unresolved or extension_points == null:
		return launch
	var filtered: Variant = extension_points.filter(
		BaseExtensionPoints.PHYSICS_PASS_LAUNCH, _copy_pass_launch(launch)
	)
	if not filtered is PassLaunch:
		mod_issues += PackedStringArray(["physics.pass_launch returned an invalid result"])
		return launch
	@warning_ignore("unsafe_cast")
	var filtered_launch: PassLaunch = filtered
	if not _valid_vector(filtered_launch.velocity_m_s):
		mod_issues += PackedStringArray(["physics.pass_launch returned an invalid result"])
		return launch
	if (
		filtered_launch.flight_time_s != launch.flight_time_s
		or filtered_launch.target_m != launch.target_m
	):
		mod_issues += PackedStringArray(["physics.pass_launch changed immutable target data"])
		return launch
	launch.velocity_m_s = filtered_launch.velocity_m_s
	return launch


func _integrate_step(dt: float) -> bool:
	if state.goal_kick_state == BallState.GoalKickState.UNRESOLVED:
		mod_issues += PackedStringArray(
			["ball goal-kick state is unresolved; solver step unavailable"]
		)
		return false
	if state.goal_kick_state == BallState.GoalKickState.ACTIVE and not wind_policy_resolved:
		mod_issues += PackedStringArray(
			["goal-kick wind policy is unresolved; solver step unavailable"]
		)
		return false
	var wind: Vector3 = wind_km_h if wind_enabled else Vector3.ZERO
	state.linear_velocity_m_s += acceleration_m_s2(state.linear_velocity_m_s, wind) * dt
	state.position_m += state.linear_velocity_m_s * dt
	var angular_speed: float = state.angular_velocity_rad_s.length()
	if angular_speed > 0.0:
		state.orientation = (
			(
				Quaternion(state.angular_velocity_rad_s / angular_speed, angular_speed * dt)
				* state.orientation
			)
			. normalized()
		)
	var contacts: Array[BallContact] = _detect_contacts()
	contacts.sort_custom(_contact_less)
	if contacts.size() > params.max_contacts_per_step:
		var resize_error: Error = contacts.resize(params.max_contacts_per_step)
		if resize_error != OK:
			mod_issues += PackedStringArray(["could not apply deterministic contact cap"])
	var responses: Array[ContactResult] = []
	for contact: BallContact in contacts:
		var response: ContactResult = _filter_contact(contact)
		if response == null:
			return false
		responses.append(response)
	if not contacts.is_empty():
		if contact_source == null or contact_solver == null:
			mod_issues += PackedStringArray(
				["ball contact path unavailable: stadium geometry and contact solver are required"]
			)
			return false
		if not contact_solver.solve_contacts(state, contacts, responses, dt):
			mod_issues += PackedStringArray(
				["ball contact path unavailable: injected contact solver did not resolve rows"]
			)
			return false
		for contact: BallContact in contacts:
			_classify_post_hit(contact.point_m)
	pending_contacts.clear()
	return true


func _detect_contacts() -> Array[BallContact]:
	var contacts: Array[BallContact] = []
	var up: Vector3 = Vector3.UP
	var body_x: Vector3 = state.orientation * Vector3.RIGHT
	var body_y: Vector3 = state.orientation * Vector3.UP
	var body_z: Vector3 = state.orientation * Vector3.BACK
	var axes: Vector3 = params.semi_axes_m
	var ground_radius: float = sqrt(
		pow(body_x.y * axes.x, 2.0) + pow(body_y.y * axes.y, 2.0) + pow(body_z.y * axes.z, 2.0)
	)
	if state.position_m.y <= ground_radius:
		var ground: BallContact = BallContact.new()
		ground.body_id = 0
		ground.feature_id = 0
		ground.contact_kind = 0
		ground.point_m = Vector3(state.position_m.x, 0.0, state.position_m.z)
		ground.normal = up
		ground.penetration_m = ground_radius - state.position_m.y
		contacts += [ground]
	if contact_source != null:
		contacts.append_array(contact_source.detect_contacts(state.position_m, state.orientation))
	contacts.append_array(pending_contacts)
	var valid_contacts: Array[BallContact] = []
	for contact: BallContact in contacts:
		if _valid_contact_data(contact):
			valid_contacts += [contact]
	return valid_contacts


func _valid_contact_data(contact: BallContact) -> bool:
	if contact == null:
		mod_issues += PackedStringArray(["collision geometry returned a null contact"])
		return false
	if (
		contact.body_id < 0
		or contact.feature_id < 0
		or contact.contact_kind < 0
		or contact.source_subfeature_id < 0
		or contact.detection_ordinal < 0
	):
		mod_issues += PackedStringArray(
			["collision geometry lacks stable nonnegative contact identifiers"]
		)
		return false
	if (
		not contact.point_m.is_finite()
		or not contact.normal.is_finite()
		or not is_finite(contact.penetration_m)
		or contact.penetration_m < 0.0
		or absf(contact.normal.length() - 1.0) > 0.001
	):
		mod_issues += PackedStringArray(["collision geometry returned invalid contact geometry"])
		return false
	return true


func _projected_area(relative_air: Vector3) -> float:
	var body_flow: Vector3 = state.orientation.inverse() * relative_air.normalized()
	var first_axis: Vector3 = body_flow.cross(Vector3.RIGHT)
	if first_axis.length_squared() < 0.000001:
		first_axis = body_flow.cross(Vector3.UP)
	first_axis = first_axis.normalized()
	var second_axis: Vector3 = body_flow.cross(first_axis).normalized()
	var first_radius: float = _ellipsoid_radius(first_axis)
	var second_radius: float = _ellipsoid_radius(second_axis)
	return PI * first_radius * second_radius


func _ellipsoid_radius(direction: Vector3) -> float:
	var axes: Vector3 = params.semi_axes_m
	var denominator: float = direction.x * direction.x / (axes.x * axes.x)
	denominator += direction.y * direction.y / (axes.y * axes.y)
	denominator += direction.z * direction.z / (axes.z * axes.z)
	return 1.0 / sqrt(denominator)


func _filter_contact(contact: BallContact) -> ContactResult:
	var surface: PitchSurfaceParams = null
	if surfaces != null and pitch_condition >= 0 and pitch_condition <= 5:
		surface = surfaces.get_for(pitch_condition, stadium_id)
	if surface == null:
		mod_issues += PackedStringArray(["pitch surface response is unresolved"])
		return null
	var local_normal: Vector3 = state.orientation.inverse() * contact.normal.normalized()
	var response: ContactResult = ContactResult.create(contact)
	response.restitution = surface.restitution(local_normal.y)
	response.friction = surface.friction
	response.rolling_resistance = surface.rolling_resistance
	if extension_points != null:
		var filtered: Variant = extension_points.filter(
			BaseExtensionPoints.PHYSICS_BALL_CONTACT, _copy_contact_result(response)
		)
		if filtered is ContactResult:
			@warning_ignore("unsafe_cast")
			var filtered_contact: ContactResult = filtered
			if _same_contact_identity(response, filtered_contact):
				if _valid_contact_response(filtered_contact):
					response.restitution = filtered_contact.restitution
					response.friction = filtered_contact.friction
					response.rolling_resistance = filtered_contact.rolling_resistance
				else:
					mod_issues += PackedStringArray(
						["physics.ball_contact response is outside bounds"]
					)
			else:
				mod_issues += PackedStringArray(
					["physics.ball_contact changed immutable contact identity"]
				)
		else:
			mod_issues += PackedStringArray(["physics.ball_contact returned the wrong type"])
	return response


func _valid_contact_response(contact: ContactResult) -> bool:
	return (
		is_finite(contact.restitution)
		and contact.restitution >= 0.0
		and contact.restitution <= 1.0
		and is_finite(contact.friction)
		and contact.friction >= 0.0
		and contact.friction <= 2.0
		and is_finite(contact.rolling_resistance)
		and contact.rolling_resistance >= 0.0
		and contact.rolling_resistance <= 1.0
	)


func _same_contact_identity(left: ContactResult, right: ContactResult) -> bool:
	return (
		left.body_id == right.body_id
		and left.feature_id == right.feature_id
		and left.contact_kind == right.contact_kind
		and left.point_m == right.point_m
		and left.normal == right.normal
		and left.penetration_m == right.penetration_m
		and left.source_subfeature_id == right.source_subfeature_id
		and left.detection_ordinal == right.detection_ordinal
	)


func _valid_launch(launch: KickLaunch) -> bool:
	return (
		launch.kick_type >= 0
		and _valid_vector(launch.velocity_m_s)
		and _valid_vector(launch.spin_rad_s, 100.0)
	)


func _quaternion_is_finite(value: Quaternion) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)


func _valid_vector(value: Vector3, limit: float = 100.0) -> bool:
	return (
		value.is_finite()
		and absf(value.x) <= limit
		and absf(value.y) <= limit
		and absf(value.z) <= limit
	)


func _classify_post_hit(point: Vector3) -> void:
	if (
		absf(absf(point.z) - params.goal_line_z_m) >= params.post_monitor_range_m
		or absf(point.x) >= params.post_monitor_range_m
	):
		return
	if (
		absf(point.y - params.crossbar_height_m) < params.post_hit_band_m
		and absf(point.x) < params.goal_width_m * 0.5 - params.post_hit_band_m
	):
		last_post_part = 2
	elif point.y < params.post_low_zone_height_m:
		last_post_part = 3
	else:
		last_post_part = 1


func _contact_less(left: BallContact, right: BallContact) -> bool:
	var left_key: Array[int] = left.sort_key()
	var right_key: Array[int] = right.sort_key()
	for index: int in range(left_key.size()):
		if left_key[index] != right_key[index]:
			return left_key[index] < right_key[index]
	return false


func _copy_kick_launch(source: KickLaunch) -> KickLaunch:
	var copy: KickLaunch = KickLaunch.new()
	copy.velocity_m_s = source.velocity_m_s
	copy.spin_rad_s = source.spin_rad_s
	copy.kick_type = source.kick_type
	copy.unresolved = source.unresolved
	return copy


func _copy_pass_launch(source: PassLaunch) -> PassLaunch:
	var copy: PassLaunch = PassLaunch.new()
	copy.velocity_m_s = source.velocity_m_s
	copy.target_m = source.target_m
	copy.flight_time_s = source.flight_time_s
	copy.unresolved = source.unresolved
	return copy


func _copy_contact_result(source: ContactResult) -> ContactResult:
	var copy: ContactResult = ContactResult.new()
	copy.body_id = source.body_id
	copy.feature_id = source.feature_id
	copy.contact_kind = source.contact_kind
	copy.point_m = source.point_m
	copy.normal = source.normal
	copy.penetration_m = source.penetration_m
	copy.source_subfeature_id = source.source_subfeature_id
	copy.detection_ordinal = source.detection_ordinal
	copy.restitution = source.restitution
	copy.friction = source.friction
	copy.rolling_resistance = source.rolling_resistance
	return copy


func _copy_ball_state(source: BallState) -> BallState:
	var copy: BallState = BallState.new()
	copy.position_m = source.position_m
	copy.orientation = source.orientation
	copy.linear_velocity_m_s = source.linear_velocity_m_s
	copy.angular_velocity_rad_s = source.angular_velocity_rad_s
	copy.mode = source.mode
	copy.goal_kick_state = source.goal_kick_state
	copy.solver_accumulator = source.solver_accumulator
	return copy


func _resource_snapshot(resource: Resource) -> Dictionary:
	var result: Dictionary = {}
	if resource == null:
		return result
	var names: Array[String] = []
	for property: Dictionary in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names += [_property_name(property)]
	names.sort()
	for property_name: String in names:
		result[property_name] = resource.get(property_name)
	return result


func _property_name(property: Dictionary) -> String:
	@warning_ignore("unsafe_cast")
	var name_value: StringName = property["name"]
	return String(name_value)


func _contacts_snapshot(contacts: Array[BallContact]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contact: BallContact in contacts:
		result += [
			{
				"key": contact.sort_key(),
				"body_id": contact.body_id,
				"feature_id": contact.feature_id,
				"contact_kind": contact.contact_kind,
				"point_m": [contact.point_m.x, contact.point_m.y, contact.point_m.z],
				"normal": [contact.normal.x, contact.normal.y, contact.normal.z],
				"penetration_m": contact.penetration_m,
				"source_subfeature_id": contact.source_subfeature_id,
				"detection_ordinal": contact.detection_ordinal,
				"response": _contact_response_snapshot(contact),
			}
		]
	return result


func _contact_response_snapshot(contact: BallContact) -> Dictionary:
	if surfaces == null or pitch_condition < 0 or pitch_condition > 5:
		return {}
	var surface: PitchSurfaceParams = surfaces.get_for(pitch_condition, stadium_id)
	if surface == null:
		return {}
	var local_normal: Vector3 = state.orientation.inverse() * contact.normal.normalized()
	return {
		"restitution": surface.restitution(local_normal.y),
		"friction": surface.friction,
		"rolling_resistance": surface.rolling_resistance,
	}
