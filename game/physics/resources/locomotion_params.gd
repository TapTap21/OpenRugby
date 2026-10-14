class_name LocomotionParams
extends Resource
## Mod-patchable locomotion values from RE 06 §2.9; energy cap comes from RE 09's owner.

@export var attribute_min: float = 0.0
@export var attribute_max: float = 100.0
@export var run_speed_min_m_s: float = 4.5
@export var run_speed_span_m_s: float = 3.5
@export var sprint_stat_breakpoints: PackedFloat32Array = PackedFloat32Array(
	[0.0, 55.0, 65.0, 75.0, 85.0, 95.0, 100.0]
)
@export
var sprint_speed_m_s: PackedFloat32Array = PackedFloat32Array([7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 9.5])
@export var accel_stat_breakpoints: PackedFloat32Array = PackedFloat32Array(
	[0.0, 40.0, 65.0, 75.0, 90.0, 100.0]
)
@export var accel_time_s: PackedFloat32Array = PackedFloat32Array([5.0, 4.0, 3.0, 2.0, 1.0, 0.0])
@export var run_accel_time_s: float = 1.0
@export var instant_acceleration_time_threshold_s: float = 0.01
@export var energy_minimum: float = -1.0
@export var drain_threshold_run_multiplier: float = 1.05
@export var regen_fast_threshold_run_multiplier: float = 0.8
@export var regen_fast_per_s: float = 10.0
@export var regen_slow_per_s: float = 5.0
@export var heavy_pitch_condition: int = 4
@export var heavy_pitch_drain_multiplier: float = 2.0
@export var fatigue_option_min_multiplier: float = 0.75
@export var fatigue_option_max_multiplier: float = 1.5
@export var sprint_start_energy_strict: float = 8.0
@export var sprint_continue_energy_strict: float = 0.0


## Checks all table dimensions and ordered ranges.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if (
		sprint_stat_breakpoints.size() != sprint_speed_m_s.size()
		or sprint_stat_breakpoints.size() < 2
	):
		errors += PackedStringArray(["sprint speed table dimensions do not match"])
	if accel_stat_breakpoints.size() != accel_time_s.size() or accel_stat_breakpoints.size() < 2:
		errors += PackedStringArray(["acceleration table dimensions do not match"])
	if run_accel_time_s <= 0.0:
		errors += PackedStringArray(["run_accel_time_s must be positive"])
	return errors


## RE interpolation for run speed.
func run_speed(stat: float) -> float:
	return (
		run_speed_min_m_s + run_speed_span_m_s * clampf(stat, attribute_min, attribute_max) / 100.0
	)


## RE piecewise-linear sprint-speed table.
func sprint_speed(stat: float) -> float:
	return _interpolate(stat, sprint_stat_breakpoints, sprint_speed_m_s)


## RE acceleration duration by acceleration stat.
func acceleration_time(stat: float) -> float:
	return _interpolate(stat, accel_stat_breakpoints, accel_time_s)


## Maps the injected menu option to the observed multiplier, with option zero disabling drain.
func fatigue_multiplier(option: int) -> float:
	if option == 0:
		return 0.0
	return lerpf(
		fatigue_option_min_multiplier, fatigue_option_max_multiplier, float(option) / 100.0
	)


## Energy rate from speed, run speed, pitch condition and injected fatigue option multiplier.
func energy_rate(
	speed: float, run_speed_value: float, condition: int, fatigue_multiplier: float
) -> float:
	var rate: float = (
		regen_fast_per_s
		if speed <= regen_fast_threshold_run_multiplier * run_speed_value
		else regen_slow_per_s
	)
	if speed > drain_threshold_run_multiplier * run_speed_value:
		var pitch_multiplier: float = (
			heavy_pitch_drain_multiplier if condition == heavy_pitch_condition else 1.0
		)
		rate -= speed * pitch_multiplier * fatigue_multiplier
	return rate


func _ordered_table(values: PackedFloat32Array) -> bool:
	for index: int in range(values.size() - 1):
		if not is_finite(values[index]) or values[index] >= values[index + 1]:
			return false
	return true


func _interpolate(
	value: float, breakpoints: PackedFloat32Array, values: PackedFloat32Array
) -> float:
	var clamped_value: float = clampf(value, breakpoints[0], breakpoints[breakpoints.size() - 1])
	for index: int in range(breakpoints.size() - 1):
		if clamped_value <= breakpoints[index + 1]:
			var span: float = breakpoints[index + 1] - breakpoints[index]
			if span <= 0.0:
				return values[index]
			var weight: float = (clamped_value - breakpoints[index]) / span
			return lerpf(values[index], values[index + 1], weight)
	return values[values.size() - 1]
