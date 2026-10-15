class_name TestPlaceKickMeter
extends GdUnitTestSuite
## Human place-kick meter state machine checks from RE 07 §K.2.

const SETTINGS: PlaceKickMeterSettings = preload(
	"res://game/setpiece/kick/default_place_kick_meter_settings.tres"
)

var _completed_results: Array[PlaceKickMeterResult] = []


func _meter(
	kicker_stat: float = 40.0,
	difficulty_index: int = 1,
	kicker_class_index: int = 0,
	training_mode: bool = false
) -> PlaceKickMeter:
	var result: PlaceKickMeter = PlaceKickMeter.new()
	var configured: bool = result.configure(
		SETTINGS, kicker_stat, difficulty_index, kicker_class_index, training_mode
	)
	@warning_ignore("unused_variable")
	var configured_assertion: GdUnitBoolAssert = assert_bool(configured).is_true()
	return result


func _on_meter_completed(result: PlaceKickMeterResult) -> void:
	_completed_results.append(result)


## RE 07 K.2 maps stat below 40 to max acceleration and stat 100 to min acceleration.
func test_stat_and_difficulty_select_observed_acceleration() -> void:
	var low_stat: PlaceKickMeter = _meter(39.0, 1)
	var high_stat: PlaceKickMeter = _meter(100.0, 1)
	var hard_difficulty: PlaceKickMeter = _meter(40.0, 2)
	@warning_ignore("unused_variable")
	var r1: GdUnitFloatAssert = assert_float(low_stat.gauge_acceleration_per_s2).is_equal(2.0)
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(high_stat.gauge_acceleration_per_s2).is_equal_approx(
		0.8, 0.000001
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = (
		assert_float(hard_difficulty.gauge_acceleration_per_s2).is_equal_approx(2.4, 0.000001)
	)


## Rising and returning use semi-implicit acceleration with caller-supplied seconds.
func test_manual_power_and_accuracy_inputs_emit_one_raw_result() -> void:
	_completed_results.clear()
	var meter: PlaceKickMeter = _meter()
	var connect_error: Error = meter.meter_completed.connect(_on_meter_completed)
	@warning_ignore("unused_variable")
	var connected_assertion: GdUnitBoolAssert = assert_bool(connect_error == OK).is_true()
	@warning_ignore("unused_variable")
	var r1: GdUnitAssert = assert_that(meter.advance(0.25, true)).is_null()
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(meter.power).is_equal_approx(0.125, 0.000001)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(meter.needle).is_equal_approx(0.125, 0.000001)
	@warning_ignore("unused_variable")
	var r4: GdUnitAssert = assert_that(meter.advance(0.25, false)).is_null()
	@warning_ignore("unused_variable")
	var r5: GdUnitFloatAssert = assert_float(meter.power).is_equal_approx(0.375, 0.000001)
	@warning_ignore("unused_variable")
	var r6: GdUnitAssert = assert_that(meter.advance(0.0, true)).is_null()
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(meter.phase).is_equal(PlaceKickMeter.Phase.RETURNING)
	@warning_ignore("unused_variable")
	var r8: GdUnitFloatAssert = assert_float(meter.power).is_equal_approx(0.375, 0.000001)
	var result: PlaceKickMeterResult = meter.advance(0.0, true)
	@warning_ignore("unused_variable")
	var r9: GdUnitBoolAssert = assert_bool(result.is_valid()).is_true()
	@warning_ignore("unused_variable")
	var r10: GdUnitFloatAssert = assert_float(result.raw_gauge).is_equal_approx(0.375, 0.000001)
	@warning_ignore("unused_variable")
	var r11: GdUnitFloatAssert = assert_float(result.needle_error).is_equal_approx(
		(0.375 - 0.230) / (0.343 - 0.230), 0.000001
	)
	@warning_ignore("unused_variable")
	var r12: GdUnitIntAssert = assert_int(_completed_results.size()).is_equal(1)
	@warning_ignore("unused_variable")
	var r13: GdUnitAssert = assert_that(meter.advance(0.1, true)).is_null()
	@warning_ignore("unused_variable")
	var r14: GdUnitIntAssert = assert_int(_completed_results.size()).is_equal(1)


## Full power auto-sets after the rise; the next press advances to return, not accuracy-set.
func test_full_power_uses_extra_set_press_and_can_finish_at_top() -> void:
	var meter: PlaceKickMeter = _meter(0.0)
	@warning_ignore("unused_variable")
	var r1: GdUnitAssert = assert_that(meter.advance(2.0, true)).is_null()
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(meter.power).is_equal(1.0)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(meter.phase).is_equal(PlaceKickMeter.Phase.AUTO_POWER_WAIT)
	@warning_ignore("unused_variable")
	var r4: GdUnitAssert = assert_that(meter.advance(0.0, true)).is_null()
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(meter.phase).is_equal(PlaceKickMeter.Phase.RETURNING)
	var result: PlaceKickMeterResult = meter.advance(0.0, true)
	@warning_ignore("unused_variable")
	var r6: GdUnitFloatAssert = assert_float(result.raw_gauge).is_equal(1.0)
	@warning_ignore("unused_variable")
	var r7: GdUnitFloatAssert = assert_float(result.needle_error).is_equal_approx(
		(1.0 - 0.230) / (0.343 - 0.230), 0.000001
	)


## Releasing at the return floor auto-completes with a negative below-centre error.
func test_return_floor_auto_completes_and_records_signed_error() -> void:
	var meter: PlaceKickMeter = _meter(0.0)
	@warning_ignore("unused_variable")
	var rising: GdUnitAssert = assert_that(meter.advance(0.5, true)).is_null()
	@warning_ignore("unused_variable")
	var set_power: GdUnitAssert = assert_that(meter.advance(0.0, true)).is_null()
	var result: PlaceKickMeterResult = meter.advance(1.0, false)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(result.is_valid()).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(result.raw_gauge).is_equal_approx(0.5, 0.000001)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(result.needle_error).is_equal_approx(
		-(0.0 - 0.230) / (0.125 - 0.230), 0.000001
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(meter.phase).is_equal(PlaceKickMeter.Phase.COMPLETE)


## Training scales gauge travel by the observed 0.75 factor without changing acceleration.
func test_training_mode_scales_meter_travel_only() -> void:
	var regular: PlaceKickMeter = _meter(40.0, 1, 0, false)
	var training: PlaceKickMeter = _meter(40.0, 1, 0, true)
	@warning_ignore("unused_variable")
	var r1: GdUnitAssert = assert_that(regular.advance(0.5, true)).is_null()
	@warning_ignore("unused_variable")
	var r2: GdUnitAssert = assert_that(training.advance(0.5, true)).is_null()
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(training.gauge_acceleration_per_s2).is_equal(
		regular.gauge_acceleration_per_s2
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitFloatAssert = assert_float(training.power).is_equal_approx(
		regular.power * 0.75, 0.000001
	)


## Invalid setup and elapsed time are rejected without advancing future-affecting state.
func test_invalid_inputs_do_not_mutate_the_meter() -> void:
	var meter: PlaceKickMeter = PlaceKickMeter.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(meter.configure(SETTINGS, 101.0, 1, 0)).is_false()
	@warning_ignore("unused_variable")
	var r2: GdUnitAssert = assert_that(meter.advance(0.1, true)).is_null()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(meter.configure(SETTINGS, 50.0, 3, 0)).is_false()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(meter.configure(SETTINGS, 50.0, 1, 5)).is_false()
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(meter.configure(SETTINGS, 50.0, 1, 0)).is_true()
	var before: Dictionary = meter.snapshot()
	@warning_ignore("unused_variable")
	var r6: GdUnitAssert = assert_that(meter.advance(-0.1, true)).is_null()
	@warning_ignore("unused_variable")
	var r7: GdUnitDictionaryAssert = assert_dict(meter.snapshot()).is_equal(before)
