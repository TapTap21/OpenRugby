class_name TackleParams
extends Resource
## Mod-patchable physical contest values from RE 06 §2.8.

@export var carrier_strength_thresholds: PackedInt32Array = PackedInt32Array([90, 75, 60])
@export var carrier_strength_bonuses: PackedInt32Array = PackedInt32Array([0, 15, 10, 20])
@export var head_on_threshold_degrees: float = 135.0
@export var head_on_bonus: int = 10
@export var tackle_ability_floor: int = 90
@export var out_of_position_break_chance: float = 0.75
@export var standard_break_chance_modifiers: PackedFloat32Array = PackedFloat32Array(
	[0.0, 0.10, 0.15, 0.20, 0.25, 0.30]
)
@export var charge_base: float = 0.4
@export var handoff_base: float = 0.5
@export var sidestep_base: float = 0.2
@export var spill_head_on_dive: float = 0.25
@export var spill_big_hit: float = 0.05
@export var spill_ordinary: float = 0.02
@export var spill_velocity_min: float = 0.75
@export var spill_velocity_max: float = 1.25
@export var carrier_strength_top_category_min: int = 90
@export var carrier_strength_second_category_min: int = 75
@export var carrier_strength_third_category_min: int = 60
@export var big_hit_carrier_strength_ceiling: int = 90
@export var big_hit_primary_stat_min: int = 80
@export var big_hit_alternate_stat_min: int = 70
@export var big_hit_energy_primary_percent: float = 50.0
@export var big_hit_energy_alternate_percent: float = 35.0
@export var weight_power_scale: float = 0.1
@export var reference_weight_kg: float = 100.0
@export var aggression_power_scale: float = 0.1
@export var tackle_ability_power: float = 40.0
@export var tackle_breaker_power: float = 30.0
@export var crash_ball_power: float = 20.0


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if carrier_strength_thresholds.size() != 3 or carrier_strength_bonuses.size() != 4:
		errors += PackedStringArray(["carrier strength table dimensions invalid"])
	if spill_velocity_min < 0.0 or spill_velocity_max < spill_velocity_min:
		errors += PackedStringArray(["spill velocity range invalid"])
	return errors
