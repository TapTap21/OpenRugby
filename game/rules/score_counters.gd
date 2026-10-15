class_name ScoreCounters
extends RefCounted
## Typed Rugby score counters; the displayed total is derived from [RulesConfig].

enum Counter { TRY, CONVERSION, PENALTY_GOAL, DROP_GOAL }

var tries: int = 0
var conversions: int = 0
var penalty_goals: int = 0
var drop_goals: int = 0


## Returns a non-negative score using the active law parameters.
func points_total(config: RulesConfig) -> int:
	if config == null:
		return 0
	return (
		tries * config.points_try
		+ conversions * config.points_conversion
		+ penalty_goals * config.points_penalty_goal
		+ drop_goals * config.points_drop_goal
	)


## Returns a detached snapshot of the four authoritative counters.
func snapshot() -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {
		&"tries": tries,
		&"conversions": conversions,
		&"penalty_goals": penalty_goals,
		&"drop_goals": drop_goals,
	}
	result.make_read_only()
	return result


## Returns a detached copy of this value.
func duplicate_counters() -> ScoreCounters:
	var result: ScoreCounters = ScoreCounters.new()
	result.tries = tries
	result.conversions = conversions
	result.penalty_goals = penalty_goals
	result.drop_goals = drop_goals
	return result
