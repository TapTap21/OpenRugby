class_name MatchScore
extends RefCounted
## Owns score counters keyed by stable team identity.

var _teams: Dictionary[StringName, ScoreCounters] = {}


## Creates a zeroed score for each distinct, non-empty team ID.
func setup(team_ids: Array[StringName]) -> bool:
	if team_ids.size() < 2:
		return false
	var replacement: Dictionary[StringName, ScoreCounters] = {}
	for team_id: StringName in team_ids:
		if team_id == &"" or replacement.has(team_id):
			return false
		replacement[team_id] = ScoreCounters.new()
	_teams = replacement
	return true


## Atomically increments one known team's counter by a positive amount.
func increment(team_id: StringName, counter: ScoreCounters.Counter, amount: int = 1) -> bool:
	if amount <= 0 or not _teams.has(team_id) or not _is_counter(counter):
		return false
	var current: ScoreCounters = _teams[team_id]
	match counter:
		ScoreCounters.Counter.TRY:
			current.tries += amount
		ScoreCounters.Counter.CONVERSION:
			current.conversions += amount
		ScoreCounters.Counter.PENALTY_GOAL:
			current.penalty_goals += amount
		ScoreCounters.Counter.DROP_GOAL:
			current.drop_goals += amount
	return true


## Returns a copied score value, or null for an unknown team.
func counters_for(team_id: StringName) -> ScoreCounters:
	if not _teams.has(team_id):
		return null
	return _teams[team_id].duplicate_counters()


## Returns a detached, read-only snapshot for every team.
func snapshot() -> Dictionary[StringName, Dictionary]:
	var result: Dictionary[StringName, Dictionary] = {}
	for team_id: StringName in _teams:
		result[team_id] = _teams[team_id].snapshot()
	result.make_read_only()
	return result


func _is_counter(counter: int) -> bool:
	return counter >= ScoreCounters.Counter.TRY and counter <= ScoreCounters.Counter.DROP_GOAL
