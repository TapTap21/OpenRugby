class_name MatchClock
extends RefCounted
## Integer-tick match clock with a derived display time.

var period: int = 1
var period_count: int = 2
var period_ticks: int = 1
var elapsed_ticks: int = 0
var game_seconds_per_period: int = 2400


func _init(p_period_count: int, p_period_ticks: int, p_game_seconds_per_period: int) -> void:
	period_count = p_period_count
	period_ticks = p_period_ticks
	game_seconds_per_period = p_game_seconds_per_period


## Advances the current period by one tick. There is no cap: rugby plays past time.
func advance() -> void:
	elapsed_ticks += 1


## True once the current period has reached its nominal length.
func is_period_expired() -> bool:
	return elapsed_ticks >= period_ticks


## True when the current period is the last one.
func is_last_period() -> bool:
	return period >= period_count


## Moves to the next period and resets the elapsed ticks.
func start_next_period() -> void:
	period += 1
	elapsed_ticks = 0


## Returns the displayed match time in whole seconds (integer maths only).
@warning_ignore("integer_division")
func game_time_seconds() -> int:
	return (
		(period - 1) * game_seconds_per_period
		+ (elapsed_ticks * game_seconds_per_period) / period_ticks
	)
