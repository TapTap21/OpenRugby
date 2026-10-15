class_name PlayerFatigueParams
extends Resource
## Observed parameters for the RE 09 fatigue and energy calculations.

@export var stamina_floor: float = 40.0
@export var stamina_ceiling: float = 100.0
@export var energy_floor_at_low_stamina: float = 40.0
@export var energy_floor_at_high_stamina: float = 90.0
@export var energy_ceiling: float = 100.0
@export var full_fatigue_time_s: float = 4800.0
@export var fatigue_exponent: float = 2.0
@export var energy_percent_floor: float = 9.0
@export var halftime_recovery_s: float = 300.0


## Returns one message per invalid parameter; empty means this resource is usable.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if (
		not is_finite(stamina_floor)
		or not is_finite(stamina_ceiling)
		or stamina_floor < 0.0
		or stamina_ceiling <= stamina_floor
	):
		errors += PackedStringArray(["stamina bounds are invalid"])
	if (
		not is_finite(energy_floor_at_low_stamina)
		or not is_finite(energy_floor_at_high_stamina)
		or energy_floor_at_low_stamina < 0.0
		or energy_floor_at_high_stamina < energy_floor_at_low_stamina
	):
		errors += PackedStringArray(["energy stamina floors are invalid"])
	if not is_finite(energy_ceiling) or energy_ceiling < energy_floor_at_high_stamina:
		errors += PackedStringArray(["energy ceiling is below the high-stamina floor"])
	if (
		not is_finite(full_fatigue_time_s)
		or not is_finite(fatigue_exponent)
		or full_fatigue_time_s <= 0.0
		or fatigue_exponent <= 0.0
	):
		errors += PackedStringArray(["fatigue curve time and exponent must be positive"])
	if (
		not is_finite(energy_percent_floor)
		or energy_percent_floor < 0.0
		or energy_percent_floor >= 100.0
	):
		errors += PackedStringArray(["energy percent floor must be in [0, 100)"])
	if not is_finite(halftime_recovery_s) or halftime_recovery_s < 0.0:
		errors += PackedStringArray(["halftime recovery cannot be negative"])
	return errors
