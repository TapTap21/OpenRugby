class_name TestTeamMatchdayRoster
extends GdUnitTestSuite
## Tests match-specific starting XV resolution.


func _profile(player_id: StringName) -> PlayerProfile:
	var profile: PlayerProfile = PlayerProfile.new()
	profile.id = player_id
	return profile


func _team(lineup_size: int = 15) -> Team:
	var team: Team = Team.new()
	team.id = &"team_a"
	for index: int in range(1, 16):
		var player_id: StringName = StringName("p%d" % index)
		team.squad.append(_profile(player_id))
	if lineup_size > 0:
		for index: int in range(1, lineup_size + 1):
			team.default_lineup.append(StringName("p%d" % index))
	return team


## A valid XV resolves to the same profiles in the order declared by the team.
func test_resolves_fifteen_profiles_in_declared_order() -> void:
	var team: Team = _team()
	team.default_lineup.reverse()
	var roster: TeamMatchdayRoster = TeamMatchdayRoster.resolve(team)
	@warning_ignore("unused_variable")
	var valid_assert: GdUnitBoolAssert = assert_bool(roster.is_valid()).is_true()
	@warning_ignore("unused_variable")
	var count_assert: GdUnitIntAssert = assert_int(roster.starters.size()).is_equal(15)
	@warning_ignore("unused_variable")
	var first_assert: GdUnitStringAssert = assert_str(String(roster.starters[0].id)).is_equal("p15")
	@warning_ignore("unused_variable")
	var last_assert: GdUnitStringAssert = assert_str(String(roster.starters[14].id)).is_equal("p1")


## A lineup with fewer or more than fifteen members cannot resolve as a match XV.
func test_rejects_lineup_sizes_other_than_fifteen() -> void:
	var short_roster: TeamMatchdayRoster = TeamMatchdayRoster.resolve(_team(14))
	var long_roster: TeamMatchdayRoster = TeamMatchdayRoster.resolve(_team(16))
	@warning_ignore("unused_variable")
	var short_assert: GdUnitBoolAssert = assert_bool(short_roster.is_valid()).is_false()
	@warning_ignore("unused_variable")
	var long_assert: GdUnitBoolAssert = assert_bool(long_roster.is_valid()).is_false()
	@warning_ignore("unused_variable")
	var short_count_assert: GdUnitIntAssert = assert_int(short_roster.starters.size()).is_equal(0)
	@warning_ignore("unused_variable")
	var long_count_assert: GdUnitIntAssert = assert_int(long_roster.starters.size()).is_equal(0)


## Every starter must resolve to a profile in the team's squad.
func test_rejects_lineup_player_missing_from_squad() -> void:
	var team: Team = _team()
	team.default_lineup[7] = &"missing"
	var roster: TeamMatchdayRoster = TeamMatchdayRoster.resolve(team)
	@warning_ignore("unused_variable")
	var valid_assert: GdUnitBoolAssert = assert_bool(roster.is_valid()).is_false()
	@warning_ignore("unused_variable")
	var empty_assert: GdUnitIntAssert = assert_int(roster.starters.size()).is_equal(0)
	@warning_ignore("unused_variable")
	var error_assert: GdUnitBoolAssert = (
		assert_bool(roster.errors[0].contains("not in the squad")).is_true()
	)


## A player cannot occupy two starting slots.
func test_rejects_duplicate_lineup_player() -> void:
	var team: Team = _team()
	team.default_lineup[7] = team.default_lineup[6]
	var roster: TeamMatchdayRoster = TeamMatchdayRoster.resolve(team)
	@warning_ignore("unused_variable")
	var valid_assert: GdUnitBoolAssert = assert_bool(roster.is_valid()).is_false()
	@warning_ignore("unused_variable")
	var empty_assert: GdUnitIntAssert = assert_int(roster.starters.size()).is_equal(0)
	@warning_ignore("unused_variable")
	var error_assert: GdUnitBoolAssert = (
		assert_bool(roster.errors[0].contains("duplicate")).is_true()
	)


## A missing team and an empty lineup id are rejected explicitly.
func test_rejects_missing_team_and_empty_player_id() -> void:
	var missing_team: TeamMatchdayRoster = TeamMatchdayRoster.resolve(null)
	var team: Team = _team()
	team.default_lineup[0] = &""
	var empty_id: TeamMatchdayRoster = TeamMatchdayRoster.resolve(team)
	@warning_ignore("unused_variable")
	var missing_assert: GdUnitBoolAssert = assert_bool(missing_team.is_valid()).is_false()
	@warning_ignore("unused_variable")
	var empty_assert: GdUnitBoolAssert = assert_bool(empty_id.is_valid()).is_false()
