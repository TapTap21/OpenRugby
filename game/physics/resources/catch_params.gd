class_name CatchParams
extends Resource
## Patchable observed catch, pickup and fumble values from RE 06 §2.7.

@export var hand_segment_reach_m: PackedFloat32Array = PackedFloat32Array([1.0, 2.0])
@export var pickup_vertical_limit_m: float = 1.0
@export var pickup_capsule_radius_m: float = 0.1
@export var fumble_table: Array[PackedFloat32Array] = [
	PackedFloat32Array([0.0, 0.01, 0.02, 0.05]),
	PackedFloat32Array([0.01, 0.03, 0.05, 0.1]),
	PackedFloat32Array([0.05, 0.1, 0.15, 0.25]),
	PackedFloat32Array([0.1, 0.15, 0.25, 0.5]),
]
@export var slippery_pitch_conditions: PackedInt32Array = PackedInt32Array([3, 4, 5])
@export var fumble_dry_multiplier: float = 0.5
@export var fumble_slippery_multiplier: float = 1.0
@export var fumble_base_multiplier: float = 0.5
@export var fumble_setting_divisor: int = 60
@export var fumble_setting_high_start: float = 60.0
@export var fumble_setting_high_end: float = 100.0
@export var fumble_scale_high_start: float = 1.0
@export var fumble_scale_high_end: float = 10.0
@export var handling_stat_max: float = 100.0
@export var handling_failure_floor: float = 0.25
@export var handling_failure_handling_scale: float = 0.5
@export var separate_mode_failure_probability: float = 0.25
@export var handling_bucket_thresholds: PackedInt32Array = PackedInt32Array([85, 65, 40])
@export var catch_set_play_drop_distance_m: float = 2.5
## PROVISIONAL: setting byte and catch candidate score/gate remain unresolved and must be injected.
@export var catch_gate_id: int = -1
@export var candidate_score_policy_id: int = -1


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if (
		hand_segment_reach_m.size() != 2
		or fumble_table.size() != 4
		or handling_bucket_thresholds.size() != 3
	):
		errors += PackedStringArray(["catch parameter table dimensions are invalid"])
	for row: PackedFloat32Array in fumble_table:
		if row.size() != 4:
			errors += PackedStringArray(["fumble table rows require four entries"])
		for probability: float in row:
			if probability < 0.0 or probability > 1.0:
				errors += PackedStringArray(["fumble probabilities must be bounded"])
	return errors


func validate_classic_catch_policy() -> PackedStringArray:
	var errors: PackedStringArray = []
	if catch_gate_id < 0:
		errors += PackedStringArray(["catch condition gate is unresolved"])
	if candidate_score_policy_id < 0:
		errors += PackedStringArray(["catch candidate score policy is unresolved"])
	return errors
