class_name TeamMatchdayRoster
extends RefCounted
## Resolves a team's declared starting XV without assigning match simulation state.

const STARTER_COUNT: int = 15

var team_id: StringName
var starters: Array[PlayerProfile] = []
var errors: PackedStringArray = []


## Resolves exactly fifteen unique lineup ids to profiles in their declared order.
static func resolve(team: Team) -> TeamMatchdayRoster:
	var roster: TeamMatchdayRoster = TeamMatchdayRoster.new()
	if team == null:
		roster.errors += PackedStringArray(["team is missing"])
		return roster
	roster.team_id = team.id
	if team.default_lineup.size() != STARTER_COUNT:
		roster.errors += PackedStringArray(
			["team '%s' starting lineup must contain exactly %d players" % [team.id, STARTER_COUNT]]
		)
		return roster
	var seen: Dictionary[StringName, bool] = {}
	var resolved: Array[PlayerProfile] = []
	for player_id: StringName in team.default_lineup:
		if player_id == &"":
			roster.errors += PackedStringArray(
				["team '%s' starting lineup contains an empty player id" % team.id]
			)
			continue
		if seen.has(player_id):
			roster.errors += PackedStringArray(
				[
					(
						"team '%s' starting lineup contains duplicate player id '%s'"
						% [team.id, player_id]
					)
				]
			)
			continue
		seen[player_id] = true
		var player: PlayerProfile = team.find_player(player_id)
		if player == null:
			roster.errors += PackedStringArray(
				["team '%s' starting lineup player '%s' is not in the squad" % [team.id, player_id]]
			)
			continue
		resolved.append(player)
	if roster.errors.is_empty() and resolved.size() == STARTER_COUNT:
		roster.starters = resolved
	return roster


## Returns whether the declared starting XV resolved without errors.
func is_valid() -> bool:
	return errors.is_empty() and starters.size() == STARTER_COUNT
