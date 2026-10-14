class_name S2InteractionSystem
extends SimSystem
## Owns typed physical catch, fumble, tackle and spill results for downstream S3/S4.

enum CandidateState { UNRESOLVED = -1, NO_CANDIDATE = 0, SELECTED = 1 }
enum GateState { UNRESOLVED = -1, DISABLED = 0, ENABLED = 1 }

var tackle_params: TackleParams
var catch_params: CatchParams
var extension_points: ExtensionPoints
var last_catch: CatchResult = CatchResult.new()
var last_fumble: CatchResult = CatchResult.new()
var last_pickup: PickupResult = PickupResult.new()
var last_tackle: TackleResult = TackleResult.new()
var last_spill: TackleResult = TackleResult.new()
var unresolved_inputs: PackedStringArray = []


func _init(p_tackle: TackleParams = null, p_catch: CatchParams = null) -> void:
	tackle_params = p_tackle
	catch_params = p_catch


func system_id() -> StringName:
	return &"s2_interactions"


func tick(_sim: MatchSim) -> void:
	unresolved_inputs.clear()


func configure_extensions(points: ExtensionPoints) -> void:
	extension_points = points


## Catch candidate score and gate must be injected by the owning interaction caller.
func resolve_catch(
	candidate_state: CandidateState, failure_probability: float, gate_state: GateState, rng: SimRng
) -> CatchResult:
	var result: CatchResult = CatchResult.new()
	if (
		candidate_state == CandidateState.UNRESOLVED
		or gate_state == GateState.UNRESOLVED
		or rng == null
	):
		result.outcome = CatchResult.Outcome.UNRESOLVED
		unresolved_inputs += PackedStringArray(
			["catch candidate, gate, probability or RNG is unresolved"]
		)
		last_catch = result
		return result
	if candidate_state == CandidateState.NO_CANDIDATE:
		result.outcome = CatchResult.Outcome.DROPPED
		result.resolved = true
	elif gate_state == GateState.ENABLED:
		if (
			not is_finite(failure_probability)
			or failure_probability < 0.0
			or failure_probability > 1.0
		):
			result.outcome = CatchResult.Outcome.UNRESOLVED
			last_catch = result
			return result
		result.probability = failure_probability
		var filtered: Variant = _filter_probability(
			BaseExtensionPoints.PHYSICS_CATCH_RESOLVE, result
		)
		if filtered == null:
			result.outcome = CatchResult.Outcome.UNRESOLVED
		else:
			@warning_ignore("unsafe_cast")
			var filtered_catch: CatchResult = filtered
			result.probability = filtered_catch.probability
			result.outcome = (
				CatchResult.Outcome.DROPPED
				if rng.next_float() < result.probability
				else CatchResult.Outcome.CAUGHT
			)
			result.resolved = true
	else:
		result.outcome = CatchResult.Outcome.CAUGHT
		result.resolved = true
	last_catch = result
	return result


## Fumble roll with strict comparison and typed probability override hook.
func resolve_fumble(probability: float, rng: SimRng) -> CatchResult:
	var result: CatchResult = CatchResult.new()
	result.probability = probability
	if not is_finite(probability) or probability < 0.0 or probability > 1.0:
		result.outcome = CatchResult.Outcome.UNRESOLVED
		last_fumble = result
		return result
	var filtered: Variant = _filter_probability(BaseExtensionPoints.PHYSICS_FUMBLE_RESOLVE, result)
	if filtered == null or rng == null:
		unresolved_inputs += PackedStringArray(["fumble probability or RNG is unresolved"])
		last_fumble = result
		return result
	@warning_ignore("unsafe_cast")
	var filtered_fumble: CatchResult = filtered
	result.probability = filtered_fumble.probability
	result.outcome = (
		CatchResult.Outcome.FUMBLED
		if rng.next_float() < result.probability
		else CatchResult.Outcome.CAUGHT
	)
	result.resolved = true
	last_fumble = result
	return result


## Standard physical tackle; carrier modifier must be explicitly injected.
func resolve_tackle(
	defender_tackling: int,
	defender_has_tackle: bool,
	carrier_strength: int,
	carrier_strength_ability: bool,
	relative_angle_degrees: float,
	carrier_break_modifier: float,
	rng: SimRng,
	out_of_position: bool = false
) -> TackleResult:
	last_tackle = TackleResolver.resolve_standard(
		defender_tackling,
		defender_has_tackle,
		carrier_strength,
		carrier_strength_ability,
		relative_angle_degrees,
		carrier_break_modifier,
		rng,
		tackle_params,
		out_of_position,
		extension_points
	)
	return last_tackle


## Stores the observed physical pickup gates; ball pickup fumble band remains caller-injected.
func resolve_pickup(
	ball_held: bool, vertical_separation_m: float, hand_capsule_intersects: bool
) -> PickupResult:
	last_pickup = CatchPickup.pickup(
		ball_held, vertical_separation_m, hand_capsule_intersects, catch_params
	)
	return last_pickup


## Spill filter may adjust only probability; velocity range remains parameter-owned.
func resolve_spill(probability: float, rng: SimRng) -> TackleResult:
	var result: TackleResult = TackleResult.new()
	result.spill_probability = probability
	if tackle_params != null:
		result.spill_velocity_min = tackle_params.spill_velocity_min
		result.spill_velocity_max = tackle_params.spill_velocity_max
	if not is_finite(probability) or probability < 0.0 or probability > 1.0:
		result.unresolved = true
		last_spill = result
		return result
	var filtered: Variant = _filter_probability(BaseExtensionPoints.PHYSICS_BALL_SPILL, result)
	if filtered == null:
		result.unresolved = true
	else:
		@warning_ignore("unsafe_cast")
		var filtered_spill: TackleResult = filtered
		result.spill_probability = filtered_spill.spill_probability
		result.spill_velocity_min = filtered_spill.spill_velocity_min
		result.spill_velocity_max = filtered_spill.spill_velocity_max
		TackleResolver.resolve_spill(result.spill_probability, rng, tackle_params, result)
	last_spill = result
	return result


func snapshot() -> Dictionary:
	return {
		"tackle_params": _resource_snapshot(tackle_params),
		"catch_params": _resource_snapshot(catch_params),
		"last_catch": last_catch.snapshot(),
		"last_fumble": last_fumble.snapshot(),
		"last_pickup": last_pickup.snapshot(),
		"last_tackle": last_tackle.snapshot(),
		"last_spill": last_spill.snapshot(),
		"unresolved_inputs": Array(unresolved_inputs),
	}


func _filter_probability(point: StringName, result: RefCounted) -> Variant:
	if extension_points == null:
		return result
	var filtered: Variant = extension_points.filter(point, _copy_result(result))
	var probability: float
	if filtered is CatchResult:
		@warning_ignore("unsafe_cast")
		var catch_result: CatchResult = filtered
		probability = catch_result.probability
	elif filtered is TackleResult:
		@warning_ignore("unsafe_cast")
		var tackle_result: TackleResult = filtered
		if point == BaseExtensionPoints.PHYSICS_TACKLE_RESOLVE:
			probability = tackle_result.break_probability
		else:
			probability = tackle_result.spill_probability
			if (
				not is_finite(tackle_result.spill_velocity_min)
				or not is_finite(tackle_result.spill_velocity_max)
				or tackle_result.spill_velocity_min < 0.0
				or tackle_result.spill_velocity_max > 2.0
				or tackle_result.spill_velocity_min > tackle_result.spill_velocity_max
			):
				unresolved_inputs += PackedStringArray(
					["physics.ball_spill returned an invalid velocity scale range"]
				)
				return null
	else:
		unresolved_inputs += PackedStringArray(["%s returned a result of the wrong type" % point])
		return null
	if not is_finite(probability) or probability < 0.0 or probability > 1.0:
		unresolved_inputs += PackedStringArray(["%s returned a probability outside [0,1]" % point])
		return null
	return filtered


func _copy_result(source: RefCounted) -> RefCounted:
	if source is CatchResult:
		@warning_ignore("unsafe_cast")
		var source_catch: CatchResult = source
		var catch_copy: CatchResult = CatchResult.new()
		catch_copy.outcome = source_catch.outcome
		catch_copy.probability = source_catch.probability
		catch_copy.resolved = source_catch.resolved
		return catch_copy
	@warning_ignore("unsafe_cast")
	var source_tackle: TackleResult = source
	var tackle_copy: TackleResult = TackleResult.new()
	tackle_copy.outcome = source_tackle.outcome
	tackle_copy.break_probability = source_tackle.break_probability
	tackle_copy.spill_probability = source_tackle.spill_probability
	tackle_copy.broke_tackle = source_tackle.broke_tackle
	tackle_copy.spilled_ball = source_tackle.spilled_ball
	tackle_copy.ball_velocity_scale = source_tackle.ball_velocity_scale
	tackle_copy.spill_velocity_min = source_tackle.spill_velocity_min
	tackle_copy.spill_velocity_max = source_tackle.spill_velocity_max
	tackle_copy.unresolved = source_tackle.unresolved
	return tackle_copy


func _property_name(property: Dictionary) -> String:
	@warning_ignore("unsafe_cast")
	var name_value: StringName = property["name"]
	return String(name_value)


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
