class_name TackleResolver
extends RefCounted
## Pure physical contest formulas. Legality and infringement classification belong to S3.


## Carrier strength category bonus from the observed ability and stat bands.
static func strength_bonus(
	strength: int, has_strength_category_ability: bool, params: TackleParams
) -> int:
	if strength >= params.carrier_strength_top_category_min and has_strength_category_ability:
		return params.carrier_strength_bonuses[0]
	if strength >= params.carrier_strength_second_category_min:
		return params.carrier_strength_bonuses[1]
	if strength >= params.carrier_strength_third_category_min:
		return params.carrier_strength_bonuses[2]
	return params.carrier_strength_bonuses[3]


## Returns null when the unresolved carrier modifier has not been injected.
static func break_probability(
	defender_tackling: int,
	defender_has_tackle_ability: bool,
	carrier_strength: int,
	carrier_has_strength_category_ability: bool,
	relative_angle_degrees: float,
	carrier_break_modifier: float,
	params: TackleParams,
	out_of_position_fullback: bool = false
) -> float:
	if not is_finite(carrier_break_modifier) or params == null:
		return NAN
	var effective_tackling: int = (
		maxi(defender_tackling, params.tackle_ability_floor)
		if defender_has_tackle_ability
		else defender_tackling
	)
	var bonus: int = strength_bonus(carrier_strength, carrier_has_strength_category_ability, params)
	if relative_angle_degrees > params.head_on_threshold_degrees:
		bonus += params.head_on_bonus
	if out_of_position_fullback:
		return params.out_of_position_break_chance
	return clampf(
		(
			1.0
			- clampf(float(effective_tackling + bonus) / 100.0, 0.0, 1.0)
			+ float(carrier_break_modifier)
		),
		0.0,
		1.0
	)


## Standard tackle challenge; the unresolved carrier modifier must be explicitly supplied.
static func resolve_standard(
	defender_tackling: int,
	defender_has_tackle_ability: bool,
	carrier_strength: int,
	carrier_has_strength_category_ability: bool,
	relative_angle_degrees: float,
	carrier_break_modifier: float,
	rng: SimRng,
	params: TackleParams,
	out_of_position_fullback: bool = false,
	extensions: ExtensionPoints = null
) -> TackleResult:
	var result: TackleResult = TackleResult.new()
	var probability: float = break_probability(
		defender_tackling,
		defender_has_tackle_ability,
		carrier_strength,
		carrier_has_strength_category_ability,
		relative_angle_degrees,
		carrier_break_modifier,
		params,
		out_of_position_fullback
	)
	if not is_finite(probability) or rng == null:
		result.unresolved = true
		return result
	result.break_probability = probability
	if extensions != null:
		var filter_value: TackleResult = TackleResult.new()
		filter_value.break_probability = probability
		var filtered: Variant = extensions.filter(
			BaseExtensionPoints.PHYSICS_TACKLE_RESOLVE, filter_value
		)
		if not filtered is TackleResult:
			result.unresolved = true
			return result
		@warning_ignore("unsafe_cast")
		var filtered_result: TackleResult = filtered
		if (
			not is_finite(filtered_result.break_probability)
			or filtered_result.break_probability < 0.0
			or filtered_result.break_probability > 1.0
		):
			result.unresolved = true
			return result
		result.break_probability = filtered_result.break_probability
	result.broke_tackle = rng.next_float() < result.break_probability
	result.outcome = (
		TackleResult.Outcome.BROKEN_TACKLE if result.broke_tackle else TackleResult.Outcome.TACKLE
	)
	return result


## Power terms used by observed special-contact ratio; caller supplies resolved stats.
static func contest_power(
	tackling: float,
	weight_kg: float,
	speed_m_s: float,
	strength: float,
	aggression: float,
	has_tackle_ability: bool,
	has_tackle_breaker: bool,
	has_crash_ball: bool,
	carrier: bool,
	params: TackleParams
) -> float:
	if params == null:
		return NAN
	var value: float = (
		tackling + params.weight_power_scale * (weight_kg - params.reference_weight_kg)
	)
	value += speed_m_s + strength + params.aggression_power_scale * aggression
	value += params.tackle_ability_power if has_tackle_ability else 0.0
	if carrier:
		value += params.tackle_breaker_power if has_tackle_breaker else 0.0
		value += params.crash_ball_power if has_crash_ball else 0.0
	return value


## Applies an injected contact base chance and observed carrier/defender power ratio.
static func contact_probability(base: float, carrier_power: float, defender_power: float) -> float:
	if defender_power <= 0.0 or not is_finite(carrier_power) or not is_finite(defender_power):
		return NAN
	return clampf(base * carrier_power / defender_power, 0.0, 1.0)


## Observed big-hit eligibility gates; caller supplies resolved state gate and energy percentage.
static func big_hit_eligible(
	energy_percent: float,
	tackling: int,
	strength: int,
	aggression: int,
	has_tackle_ability: bool,
	carrier_strength: int,
	state_gate: int,
	params: TackleParams
) -> bool:
	if (
		params == null
		or state_gate != 1
		or carrier_strength >= params.big_hit_carrier_strength_ceiling
	):
		return false
	var primary: bool = (
		energy_percent >= 50.0
		and (
			(
				tackling >= params.big_hit_primary_stat_min
				and strength >= params.big_hit_primary_stat_min
				and aggression >= params.big_hit_primary_stat_min
			)
			or has_tackle_ability
		)
	)
	var alternate: bool = (
		energy_percent >= params.big_hit_energy_alternate_percent
		and aggression >= 70
		and tackling >= 70
	)
	return primary or alternate


## Rolls a supplied spill probability and the observed uniform velocity scale.
static func resolve_spill(
	probability: float, rng: SimRng, params: TackleParams, result: TackleResult
) -> void:
	if rng == null or params == null or probability < 0.0 or probability > 1.0:
		result.unresolved = true
		return
	result.spill_probability = probability
	if not is_finite(result.spill_velocity_min) or not is_finite(result.spill_velocity_max):
		result.spill_velocity_min = params.spill_velocity_min
		result.spill_velocity_max = params.spill_velocity_max
	if (
		result.spill_velocity_min < 0.0
		or result.spill_velocity_max > 2.0
		or result.spill_velocity_min > result.spill_velocity_max
	):
		result.unresolved = true
		return
	result.spilled_ball = rng.next_float() < probability
	if result.spilled_ball:
		result.ball_velocity_scale = rng.range_float(
			result.spill_velocity_min, result.spill_velocity_max
		)
		result.outcome = TackleResult.Outcome.SPILL
