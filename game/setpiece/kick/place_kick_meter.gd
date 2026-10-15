class_name PlaceKickMeter
extends RefCounted
## Deterministic human place-kick gauge; returns raw power and signed needle error only.

signal meter_completed(result: PlaceKickMeterResult)

enum Phase { UNCONFIGURED, IDLE, RISING, AUTO_POWER_WAIT, RETURNING, COMPLETE }

const MIN_KICKER_STAT: float = 0.0
const MAX_KICKER_STAT: float = 100.0
const LOW_STAT_ACCELERATION_LIMIT: float = 40.0
const HIGH_STAT_ACCELERATION_LIMIT: float = 100.0

var phase: Phase = Phase.UNCONFIGURED
var power: float = 0.0
var needle: float = 0.0
var gauge_acceleration_per_s2: float = NAN
var settings: PlaceKickMeterSettings
var kicker_stat: float = NAN
var difficulty_index: int = -1
var kicker_class_index: int = -1
var training_mode: bool = false

var _power_speed: float = 0.0
var _needle_speed: float = 0.0


## Configures the meter from owner-provided difficulty, kicker-class, and match-mode inputs.
func configure(
	p_settings: PlaceKickMeterSettings,
	p_kicker_stat: float,
	p_difficulty_index: int,
	p_kicker_class_index: int,
	p_training_mode: bool = false
) -> bool:
	if (
		p_settings == null
		or not p_settings.validate().is_empty()
		or not is_finite(p_kicker_stat)
		or p_kicker_stat < MIN_KICKER_STAT
		or p_kicker_stat > MAX_KICKER_STAT
		or p_difficulty_index < 0
		or p_difficulty_index >= p_settings.min_acceleration_by_difficulty.size()
		or p_kicker_class_index < 0
		or p_kicker_class_index >= p_settings.accuracy_zone_top.size()
	):
		return false
	settings = p_settings.duplicate(true) as PlaceKickMeterSettings
	kicker_stat = p_kicker_stat
	difficulty_index = p_difficulty_index
	kicker_class_index = p_kicker_class_index
	training_mode = p_training_mode
	gauge_acceleration_per_s2 = _acceleration_for_stat(
		p_kicker_stat,
		settings.min_acceleration_by_difficulty[p_difficulty_index],
		settings.max_acceleration_by_difficulty[p_difficulty_index]
	)
	phase = Phase.IDLE
	power = 0.0
	needle = 0.0
	_power_speed = 0.0
	_needle_speed = 0.0
	return true


## Advances by owner-supplied elapsed seconds and returns a completed raw meter result once.
func advance(delta_seconds: float, kick_just_pressed: bool) -> PlaceKickMeterResult:
	if (
		phase == Phase.UNCONFIGURED
		or phase == Phase.COMPLETE
		or not is_finite(delta_seconds)
		or delta_seconds < 0.0
	):
		return null
	if phase == Phase.IDLE:
		if kick_just_pressed:
			phase = Phase.RISING
		else:
			return null
	elif phase == Phase.RISING and kick_just_pressed:
		phase = Phase.RETURNING
		_reset_speeds()
	elif phase == Phase.AUTO_POWER_WAIT and kick_just_pressed:
		phase = Phase.RETURNING
		_reset_speeds()
	elif phase == Phase.RETURNING and kick_just_pressed:
		return _complete()

	var speed_scale: float = settings.training_speed_multiplier if training_mode else 1.0
	if phase == Phase.RISING:
		_power_speed += gauge_acceleration_per_s2 * delta_seconds
		_needle_speed += gauge_acceleration_per_s2 * delta_seconds
		power = minf(power + _power_speed * delta_seconds * speed_scale, 1.0)
		needle = minf(needle + _needle_speed * delta_seconds * speed_scale, 1.0)
		if power >= 1.0:
			power = 1.0
			needle = 1.0
			phase = Phase.AUTO_POWER_WAIT
			_reset_speeds()
	elif phase == Phase.RETURNING:
		_needle_speed += gauge_acceleration_per_s2 * delta_seconds
		needle = maxf(needle - _needle_speed * delta_seconds * speed_scale, 0.0)
		if needle <= 0.0:
			return _complete()
	return null


## Returns future-affecting meter values for deterministic owner snapshots and replay hashing.
func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"power": power,
		"needle": needle,
		"gauge_acceleration_per_s2": gauge_acceleration_per_s2,
		"kicker_stat": kicker_stat,
		"difficulty_index": difficulty_index,
		"kicker_class_index": kicker_class_index,
		"training_mode": training_mode,
		"training_speed_multiplier": settings.training_speed_multiplier,
		"accuracy_zone_top": settings.accuracy_zone_top[kicker_class_index],
		"accuracy_zone_center": settings.accuracy_zone_center[kicker_class_index],
		"accuracy_zone_bottom": settings.accuracy_zone_bottom[kicker_class_index],
		"power_speed": _power_speed,
		"needle_speed": _needle_speed,
	}


func _complete() -> PlaceKickMeterResult:
	var top: float = settings.accuracy_zone_top[kicker_class_index]
	var center: float = settings.accuracy_zone_center[kicker_class_index]
	var bottom: float = settings.accuracy_zone_bottom[kicker_class_index]
	var error: float = 0.0
	if needle > center:
		error = (needle - center) / (top - center)
	elif needle < center:
		error = -(needle - center) / (bottom - center)
	var result: PlaceKickMeterResult = PlaceKickMeterResult.new()
	result.raw_gauge = power
	result.needle_error = error
	phase = Phase.COMPLETE
	meter_completed.emit(result)
	return result


func _reset_speeds() -> void:
	_power_speed = 0.0
	_needle_speed = 0.0


func _acceleration_for_stat(stat: float, minimum: float, maximum: float) -> float:
	if stat < LOW_STAT_ACCELERATION_LIMIT:
		return maximum
	var stat_fraction: float = (
		(stat - LOW_STAT_ACCELERATION_LIMIT)
		/ (HIGH_STAT_ACCELERATION_LIMIT - LOW_STAT_ACCELERATION_LIMIT)
	)
	return maximum - stat_fraction * (maximum - minimum)
