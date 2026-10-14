class_name PlaceKickMeterResult
extends RefCounted
## S4-owned raw goal-kick meter result; S2 applies the needle penalty once.

var raw_gauge: float = NAN
var needle_error: float = NAN


func is_valid() -> bool:
	return (
		is_finite(raw_gauge) and raw_gauge >= 0.0 and raw_gauge <= 1.0 and is_finite(needle_error)
	)
