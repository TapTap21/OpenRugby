class_name PlaceKickMeterSettings
extends Resource
## Patchable values for the human place-kick meter from RE 07 §K.2.

@export var min_acceleration_by_difficulty: PackedFloat32Array = PackedFloat32Array()
@export var max_acceleration_by_difficulty: PackedFloat32Array = PackedFloat32Array()
@export var training_speed_multiplier: float = NAN
@export var accuracy_zone_top: PackedFloat32Array = PackedFloat32Array()
@export var accuracy_zone_center: PackedFloat32Array = PackedFloat32Array()
@export var accuracy_zone_bottom: PackedFloat32Array = PackedFloat32Array()


## Returns validation errors for difficulty acceleration and kicker-class accuracy tables.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if min_acceleration_by_difficulty.size() != 3:
		errors += PackedStringArray(["min acceleration table must contain three difficulties"])
	if max_acceleration_by_difficulty.size() != 3:
		errors += PackedStringArray(["max acceleration table must contain three difficulties"])
	if (
		accuracy_zone_top.size() != 5
		or accuracy_zone_center.size() != 5
		or accuracy_zone_bottom.size() != 5
	):
		errors += PackedStringArray(["accuracy zone tables must contain five kicker classes"])
	if not is_finite(training_speed_multiplier) or training_speed_multiplier <= 0.0:
		errors += PackedStringArray(["training_speed_multiplier must be finite and positive"])
	if min_acceleration_by_difficulty.size() == 3 and max_acceleration_by_difficulty.size() == 3:
		for index: int in range(3):
			var min_acceleration: float = min_acceleration_by_difficulty[index]
			var max_acceleration: float = max_acceleration_by_difficulty[index]
			if (
				not is_finite(min_acceleration)
				or not is_finite(max_acceleration)
				or min_acceleration <= 0.0
				or max_acceleration < min_acceleration
			):
				errors += PackedStringArray(["difficulty acceleration range is invalid"])
				break
	if (
		accuracy_zone_top.size() == 5
		and accuracy_zone_center.size() == 5
		and accuracy_zone_bottom.size() == 5
	):
		for index: int in range(5):
			var top: float = accuracy_zone_top[index]
			var center: float = accuracy_zone_center[index]
			var bottom: float = accuracy_zone_bottom[index]
			if (
				not is_finite(top)
				or not is_finite(center)
				or not is_finite(bottom)
				or top > 1.0
				or top <= center
				or center <= bottom
				or bottom < 0.0
			):
				errors += PackedStringArray(
					["accuracy zone must be descending fractions in [0, 1]"]
				)
				break
	return errors
