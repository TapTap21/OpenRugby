class_name CameraPreset
extends Resource
## A camera preset. All numeric fields are PROVISIONAL.

@export var id: StringName
@export var display_name_key: String
@export var fov_degrees: float = 50.0
@export var distance: float = 25.0
@export var height: float = 12.0
@export var pitch_degrees: float = -25.0
@export var follow_smoothing: float = 0.15
@export var look_ahead: float = 3.0


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors += PackedStringArray(["camera preset id is empty"])
	if fov_degrees <= 1.0 or fov_degrees >= 179.0:
		errors += PackedStringArray(["fov_degrees must be between 1 and 179 (exclusive)"])
	if distance < 0.0:
		errors += PackedStringArray(["distance must not be negative"])
	return errors
