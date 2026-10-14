class_name PitchSurfaceParams
extends Resource
## One observed RE 06 §2.4 row; bounce factors are 1+restitution.

@export var bounce_side_on: float = 1.5
@export var bounce_end_on: float = 1.4
@export var unused_bounce_randomness: float = 0.15
@export var friction: float = 0.7
@export var rolling_resistance: float = 0.06


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if bounce_side_on < 1.0 or bounce_side_on > 2.0 or bounce_end_on < 1.0 or bounce_end_on > 2.0:
		errors += PackedStringArray(["pitch bounce factors must be in [1,2]"])
	if friction < 0.0 or friction > 2.0 or rolling_resistance < 0.0 or rolling_resistance > 1.0:
		errors += PackedStringArray(["pitch friction or rolling resistance is outside bounds"])
	return errors


func restitution(long_axis_component: float) -> float:
	var c_squared: float = clampf(long_axis_component * long_axis_component, 0.0, 1.0)
	var bounce_factor: float = clampf(
		bounce_end_on + (1.0 - c_squared) * (bounce_side_on - bounce_end_on), 1.0, 2.0
	)
	return bounce_factor - 1.0
