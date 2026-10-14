class_name PassParams
extends Resource
## Patchable pass-flight and forward-assist values from RE 06 §2.7.

@export var normal_time_s: float = 0.5
@export var lead_time_s: float = 0.9
@export var passing_time_low_s: float = 1.5
@export var passing_time_span_s: float = 0.95
@export var passing_stat_max: float = 100.0
@export var fixed_time_050_s: float = 0.5
@export var fixed_time_070_s: float = 0.7
@export var passing_multiplier_non_natural_nine: float = 1.33
@export var non_natural_nine_types: PackedInt32Array = PackedInt32Array([1, 2, 3, 4, 9])
@export var fixed_time_050_types: PackedInt32Array = PackedInt32Array([3, 6, 12])
@export var fixed_time_070_types: PackedInt32Array = PackedInt32Array([7, 8, 11])
@export var forward_assist_min_speed_m_s: float = 8.0
@export
var forward_assist_probabilities: PackedFloat32Array = PackedFloat32Array([0.5, 0.6, 0.7, 0.8, 0.9])
@export var forward_flatten_speed_m_s: float = 0.01
@export var no_receiver_speed_cap_m_s: float = 20.0
@export var lead_forward_offset_m: float = 3.0
@export var normal_forward_offset_m: float = 2.0
@export var lead_receiver_x_scale: float = 0.8
## PROVISIONAL: pass target height and unresolved type-to-user-input mapping are supplied by caller.
@export var target_height_injection_required: bool = true


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if normal_time_s <= 0.0 or lead_time_s <= 0.0 or passing_stat_max <= 0.0:
		errors += PackedStringArray(["pass timing parameters must be positive"])
	if forward_assist_probabilities.size() != 5:
		errors += PackedStringArray(["forward assist requires five probability entries"])
	for probability: float in forward_assist_probabilities:
		if probability < 0.0 or probability > 1.0:
			errors += PackedStringArray(["forward assist probabilities must be bounded"])
	return errors
