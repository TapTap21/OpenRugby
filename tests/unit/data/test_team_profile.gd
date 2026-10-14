class_name TestTeamProfile
extends GdUnitTestSuite
## Tests for Team and PlayerProfile validation, lookup and display rules (S1-core section 5,
## criteria C-39 and C-40).


func _profile(player_id: StringName, known: String = "") -> PlayerProfile:
	var profile: PlayerProfile = PlayerProfile.new()
	profile.id = player_id
	profile.first_name = "Ada"
	profile.last_name = "Lovelace"
	profile.known_as = known
	return profile


## Builds a team with a home kit (so that the only possible errors are the ones under test).
func _team(squad_ids: Array, lineup_ids: Array) -> Team:
	var team: Team = Team.new()
	team.id = &"team_a"
	team.name = "Team A"
	team.short_name = "TMA"
	team.home_kit = Kit.new()
	for player_id: StringName in squad_ids:
		@warning_ignore("return_value_discarded")
		team.squad.append(_profile(player_id))
	for player_id: StringName in lineup_ids:
		@warning_ignore("return_value_discarded")
		team.default_lineup.append(player_id)
	return team


## C-39: a team with a lineup drawn from its squad validates.
func test_c39_valid_team_has_no_errors() -> void:
	var team: Team = _team([&"p1"], [&"p1"])
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(team.validate().size()).is_equal(0)


## C-39: a lineup id that is not in the squad is reported.
func test_c39_lineup_id_not_in_squad_reported() -> void:
	var team: Team = _team([&"p1"], [&"p1", &"ghost"])
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(team.validate().size() > 0).is_true()


## C-39: duplicate player ids in the squad are reported.
func test_c39_duplicate_squad_ids_reported() -> void:
	var team: Team = _team([&"p1", &"p1"], [])
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(team.validate().size() > 0).is_true()


## C-39: find_player returns the profile when present and null when absent.
func test_c39_find_player_returns_profile_or_null() -> void:
	var team: Team = _team([&"p1", &"p2"], [])
	var found: PlayerProfile = team.find_player(&"p2")
	@warning_ignore("unused_variable")
	var r1: GdUnitObjectAssert = assert_object(found).is_not_null()
	if found != null:
		@warning_ignore("unused_variable")
		var r2: GdUnitStringAssert = assert_str(String(found.id)).is_equal("p2")
	@warning_ignore("unused_variable")
	var r3: GdUnitObjectAssert = assert_object(team.find_player(&"nobody")).is_null()


## C-40: display_name uses known_as when set.
func test_c40_display_name_prefers_known_as() -> void:
	@warning_ignore("unused_variable")
	var r1: GdUnitStringAssert = assert_str(_profile(&"p1", "Lovelace").display_name()).is_equal(
		"Lovelace"
	)


## C-40: display_name falls back to first and last name when known_as is empty.
func test_c40_display_name_falls_back_to_full_name() -> void:
	@warning_ignore("unused_variable")
	var result: GdUnitStringAssert = assert_str(_profile(&"p1").display_name()).is_equal(
		"Ada Lovelace"
	)


## C-40: get_attribute returns the stored value, or the schema default when absent.
func test_c40_get_attribute_falls_back_to_schema_default() -> void:
	var schema: PlayerAttributeSchema = PlayerAttributeSchema.new()
	@warning_ignore("return_value_discarded")
	schema.attribute_ids.append(&"speed")
	@warning_ignore("return_value_discarded")
	schema.attribute_ids.append(&"tackling")
	var profile: PlayerProfile = _profile(&"p1")
	profile.attributes[&"speed"] = 80
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(profile.get_attribute(&"speed", schema)).is_equal(80)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(profile.get_attribute(&"tackling", schema)).is_equal(50)


## C-40: validate(schema) accepts a known attribute inside the range.
func test_c40_validate_accepts_known_in_range_attribute() -> void:
	var schema: PlayerAttributeSchema = PlayerAttributeSchema.new()
	@warning_ignore("return_value_discarded")
	schema.attribute_ids.append(&"speed")
	var profile: PlayerProfile = _profile(&"p1")
	profile.attributes[&"speed"] = 80
	@warning_ignore("unused_variable")
	var result: GdUnitIntAssert = assert_int(profile.validate(schema).size()).is_equal(0)


## C-40: validate(schema) reports an attribute key that is not in the schema.
func test_c40_validate_reports_unknown_attribute_key() -> void:
	var schema: PlayerAttributeSchema = PlayerAttributeSchema.new()
	@warning_ignore("return_value_discarded")
	schema.attribute_ids.append(&"speed")
	var profile: PlayerProfile = _profile(&"p1")
	profile.attributes[&"bogus"] = 10
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(profile.validate(schema).size() > 0).is_true()


## C-40: validate(schema) reports a value outside the schema range.
func test_c40_validate_reports_out_of_range_value() -> void:
	var schema: PlayerAttributeSchema = PlayerAttributeSchema.new()
	@warning_ignore("return_value_discarded")
	schema.attribute_ids.append(&"speed")
	var profile: PlayerProfile = _profile(&"p1")
	profile.attributes[&"speed"] = 150
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(profile.validate(schema).size() > 0).is_true()
