class_name Team
extends Resource
## A team: squad, kits, stadium and default lineup.

@export var id: StringName
@export var name: String
## Three-letter short name.
@export var short_name: String
@export var nation: StringName
@export var home_kit: Kit
@export var away_kit: Kit
@export var home_stadium: Stadium
@export var squad: Array[PlayerProfile] = []
## Player ids, starters first.
@export var default_lineup: Array[StringName] = []
@export var captain_id: StringName
@export var goal_kicker_id: StringName
## PROVISIONAL team ratings.
@export var ratings: Dictionary[StringName, int] = {}


## Returns the squad member with [param player_id], or null.
func find_player(player_id: StringName) -> PlayerProfile:
	for player: PlayerProfile in squad:
		if player != null and player.id == player_id:
			return player
	return null


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"":
		errors += PackedStringArray(["team id is empty"])
	var seen: Dictionary[StringName, bool] = {}
	for player: PlayerProfile in squad:
		if player == null:
			errors += PackedStringArray(["team '%s' has a null squad entry" % id])
			continue
		if seen.has(player.id):
			errors += PackedStringArray(
				["team '%s' has duplicate player id '%s'" % [id, player.id]]
			)
		seen[player.id] = true
	var seen_lineup: Dictionary[StringName, bool] = {}
	for player_id: StringName in default_lineup:
		if find_player(player_id) == null:
			errors += PackedStringArray(
				["team '%s' lineup id '%s' is not in the squad" % [id, player_id]]
			)
		if seen_lineup.has(player_id):
			errors += PackedStringArray(
				["team '%s' has duplicate lineup id '%s'" % [id, player_id]]
			)
		seen_lineup[player_id] = true
	if captain_id != &"" and find_player(captain_id) == null:
		errors += PackedStringArray(
			["team '%s' captain '%s' is not in the squad" % [id, captain_id]]
		)
	if goal_kicker_id != &"" and find_player(goal_kicker_id) == null:
		errors += PackedStringArray(
			["team '%s' goal kicker '%s' is not in the squad" % [id, goal_kicker_id]]
		)
	if home_kit == null:
		errors += PackedStringArray(["team '%s' home kit is null" % id])
	return errors
