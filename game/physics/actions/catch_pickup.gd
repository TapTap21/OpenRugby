class_name CatchPickup
extends RefCounted
## Known catch reach and pickup geometry primitives; unknown candidate scoring stays injected.


## Inclusive segment reach test; returns false for invalid segment indices.
static func within_hand_reach(distance_m: float, segment_index: int, params: CatchParams) -> bool:
	return (
		params != null
		and is_finite(distance_m)
		and distance_m >= 0.0
		and segment_index >= 0
		and segment_index < params.hand_segment_reach_m.size()
		and distance_m <= params.hand_segment_reach_m[segment_index]
	)


## Resolves only the observed pickup gates; caller supplies capsule intersection result.
static func pickup(
	ball_held: bool,
	vertical_separation_m: float,
	hand_capsule_intersects: bool,
	params: CatchParams
) -> PickupResult:
	var result: PickupResult = PickupResult.new()
	if params == null or not is_finite(vertical_separation_m):
		return result
	if ball_held:
		result.outcome = PickupResult.Outcome.REJECTED_HELD
	elif absf(vertical_separation_m) > params.pickup_vertical_limit_m:
		result.outcome = PickupResult.Outcome.REJECTED_HEIGHT
	elif not hand_capsule_intersects:
		result.outcome = PickupResult.Outcome.REJECTED_CAPSULE
	else:
		result.outcome = PickupResult.Outcome.ACCEPTED
		result.accepted = true
	return result


## Base table plus surface and setting multipliers; all external fields are required inputs.
static func fumble_probability(
	catch_quality: int, handling: int, slippery: bool, settings: int, params: CatchParams
) -> float:
	if params == null or params.fumble_table.size() != 4:
		return NAN
	var quality: int = clampi(catch_quality, 0, 3)
	var thresholds: PackedInt32Array = params.handling_bucket_thresholds
	var handling_column: int = (
		0
		if handling >= thresholds[0]
		else (1 if handling >= thresholds[1] else (2 if handling >= thresholds[2] else 3))
	)
	if settings < 0 or settings > params.fumble_setting_high_end:
		return NAN
	var setting_scale: float = (
		float(floori(float(settings) / float(params.fumble_setting_divisor)))
		if settings <= params.fumble_setting_high_start
		else (
			params.fumble_scale_high_start
			+ (
				(params.fumble_scale_high_end - params.fumble_scale_high_start)
				* float(settings - int(params.fumble_setting_high_start))
				/ (params.fumble_setting_high_end - params.fumble_setting_high_start)
			)
		)
	)
	var surface_scale: float = (
		params.fumble_slippery_multiplier if slippery else params.fumble_dry_multiplier
	)
	return (
		params.fumble_table[quality][handling_column]
		* surface_scale
		* params.fumble_base_multiplier
		* setting_scale
	)
