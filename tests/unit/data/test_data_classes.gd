class_name TestDataClasses
extends GdUnitTestSuite
## Tests for the data Resource classes: section 5 defaults (C-38) and the patchability rule
## that every data field is a storage and editor exported property (C-44).


## C-38: PlayerAttributeSchema defaults.
func test_c38_player_attribute_schema_defaults() -> void:
	var schema: PlayerAttributeSchema = PlayerAttributeSchema.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(schema.min_value).is_equal(0)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(schema.max_value).is_equal(100)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(schema.default_value).is_equal(50)


## C-38: PlayerProfile defaults.
func test_c38_player_profile_defaults() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(profile.birth_year).is_equal(1980)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(profile.height_cm).is_equal(185)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(profile.weight_kg).is_equal(100)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(profile.preferred_foot).is_equal(PlayerProfile.Foot.RIGHT)
	@warning_ignore("unused_variable")
	var r5: GdUnitStringAssert = assert_str(profile.known_as).is_equal("")


## C-38: Kit defaults.
func test_c38_kit_defaults() -> void:
	var kit: Kit = Kit.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitAssert = assert_that(kit.primary_color).is_equal(Color.WHITE)
	@warning_ignore("unused_variable")
	var r2: GdUnitAssert = assert_that(kit.secondary_color).is_equal(Color.BLACK)
	@warning_ignore("unused_variable")
	var r3: GdUnitAssert = assert_that(kit.shorts_color).is_equal(Color.WHITE)
	@warning_ignore("unused_variable")
	var r4: GdUnitAssert = assert_that(kit.socks_color).is_equal(Color.WHITE)
	@warning_ignore("unused_variable")
	var r5: GdUnitAssert = assert_that(kit.number_color).is_equal(Color.BLACK)
	@warning_ignore("unused_variable")
	var r6: GdUnitStringAssert = assert_str(String(kit.pattern)).is_equal("plain")
	@warning_ignore("unused_variable")
	var r7: GdUnitStringAssert = assert_str(kit.jersey_texture_path).is_equal("")


## C-38: Stadium defaults.
func test_c38_stadium_defaults() -> void:
	var stadium: Stadium = Stadium.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(stadium.capacity).is_equal(0)
	@warning_ignore("unused_variable")
	var r2: GdUnitBoolAssert = assert_bool(stadium.has_roof).is_false()
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(stadium.scene_path).is_equal("")
	@warning_ignore("unused_variable")
	var r4: GdUnitStringAssert = assert_str(stadium.crowd_ambience_path).is_equal("")
	@warning_ignore("unused_variable")
	var r5: GdUnitObjectAssert = assert_object(stadium.pitch).is_null()


## C-38: Team defaults.
func test_c38_team_defaults() -> void:
	var team: Team = Team.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitArrayAssert = assert_array(team.squad).is_empty()
	@warning_ignore("unused_variable")
	var r2: GdUnitArrayAssert = assert_array(team.default_lineup).is_empty()
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(team.short_name).is_equal("")
	@warning_ignore("unused_variable")
	var r4: GdUnitObjectAssert = assert_object(team.home_kit).is_null()


## C-38: RulesConfig defaults.
func test_c38_rules_config_defaults() -> void:
	var rules: RulesConfig = RulesConfig.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(rules.period_count).is_equal(2)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(rules.period_game_seconds).is_equal(2400)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(rules.players_per_side).is_equal(15)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(rules.replacements_allowed).is_equal(7)
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(rules.points_try).is_equal(5)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(rules.points_conversion).is_equal(2)
	@warning_ignore("unused_variable")
	var r7: GdUnitIntAssert = assert_int(rules.points_penalty_goal).is_equal(3)
	@warning_ignore("unused_variable")
	var r8: GdUnitIntAssert = assert_int(rules.points_drop_goal).is_equal(3)
	@warning_ignore("unused_variable")
	var r9: GdUnitIntAssert = assert_int(rules.points_penalty_try).is_equal(5)
	@warning_ignore("unused_variable")
	var r10: GdUnitBoolAssert = assert_bool(rules.penalty_try_awards_conversion).is_true()
	@warning_ignore("unused_variable")
	var r11: GdUnitIntAssert = assert_int(rules.sin_bin_game_seconds).is_equal(600)
	@warning_ignore("unused_variable")
	var r12: GdUnitDictionaryAssert = assert_dict(rules.extra).is_empty()


## C-38: DifficultyProfile defaults.
func test_c38_difficulty_profile_defaults() -> void:
	var difficulty: DifficultyProfile = DifficultyProfile.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(difficulty.level).is_equal(0)
	@warning_ignore("unused_variable")
	var r2: GdUnitStringAssert = assert_str(difficulty.display_name_key).is_equal("")
	@warning_ignore("unused_variable")
	var r3: GdUnitDictionaryAssert = assert_dict(difficulty.tuning).is_empty()


## C-38: CameraPreset defaults.
func test_c38_camera_preset_defaults() -> void:
	var preset: CameraPreset = CameraPreset.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitFloatAssert = assert_float(preset.fov_degrees).is_equal(50.0)
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(preset.distance).is_equal(25.0)
	@warning_ignore("unused_variable")
	var r3: GdUnitFloatAssert = assert_float(preset.height).is_equal(12.0)
	@warning_ignore("unused_variable")
	var r4: GdUnitFloatAssert = assert_float(preset.pitch_degrees).is_equal(-25.0)
	@warning_ignore("unused_variable")
	var r5: GdUnitFloatAssert = assert_float(preset.follow_smoothing).is_equal(0.15)
	@warning_ignore("unused_variable")
	var r6: GdUnitFloatAssert = assert_float(preset.look_ahead).is_equal(3.0)


## C-38: MatchConfig defaults (the teams, stadium and difficulty stay null in S1).
func test_c38_match_config_defaults() -> void:
	var config: MatchConfig = MatchConfig.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(config.seed).is_equal(0)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(config.period_real_seconds).is_equal(300)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(config.slot_count).is_equal(1)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(config.axes_per_slot).is_equal(2)
	@warning_ignore("unused_variable")
	var r5: GdUnitObjectAssert = assert_object(config.home_team).is_null()


func _missing_exports(res: Resource, fields: PackedStringArray) -> PackedStringArray:
	var missing: PackedStringArray = []
	for field_name: String in fields:
		var found: bool = false
		for prop: Dictionary in res.get_property_list():
			if str(prop["name"]) == field_name:
				var usage: int = prop["usage"]
				found = (
					(usage & PROPERTY_USAGE_STORAGE) != 0 and (usage & PROPERTY_USAGE_EDITOR) != 0
				)
				break
		if not found:
			@warning_ignore("return_value_discarded")
			missing.append(field_name)
	return missing


## C-44: every data field of section 5 (and the pitch fields of section 4) is reported by
## get_property_list() with PROPERTY_USAGE_STORAGE and PROPERTY_USAGE_EDITOR.
func test_c44_data_fields_are_exported() -> void:
	var cases: Array[Array] = [
		[
			PlayerAttributeSchema.new(),
			PackedStringArray(
				["attribute_ids", "position_ids", "min_value", "max_value", "default_value"]
			),
		],
		[
			PlayerProfile.new(),
			PackedStringArray(
				[
					"id",
					"first_name",
					"last_name",
					"known_as",
					"nationality",
					"birth_year",
					"height_cm",
					"weight_kg",
					"preferred_foot",
					"primary_position",
					"secondary_positions",
					"attributes",
				]
			),
		],
		[
			Kit.new(),
			PackedStringArray(
				[
					"id",
					"primary_color",
					"secondary_color",
					"shorts_color",
					"socks_color",
					"number_color",
					"pattern",
					"jersey_texture_path",
				]
			),
		],
		[
			Stadium.new(),
			PackedStringArray(
				[
					"id",
					"name",
					"city",
					"country",
					"capacity",
					"pitch",
					"scene_path",
					"crowd_ambience_path",
					"has_roof",
				]
			),
		],
		[
			Team.new(),
			PackedStringArray(
				[
					"id",
					"name",
					"short_name",
					"nation",
					"home_kit",
					"away_kit",
					"home_stadium",
					"squad",
					"default_lineup",
					"captain_id",
					"goal_kicker_id",
					"ratings",
				]
			),
		],
		[
			RulesConfig.new(),
			PackedStringArray(
				[
					"period_count",
					"period_game_seconds",
					"players_per_side",
					"replacements_allowed",
					"points_try",
					"points_conversion",
					"points_penalty_goal",
					"points_drop_goal",
					"points_penalty_try",
					"penalty_try_awards_conversion",
					"sin_bin_game_seconds",
					"extra",
				]
			),
		],
		[
			DifficultyProfile.new(),
			PackedStringArray(["id", "display_name_key", "level", "tuning"]),
		],
		[
			CameraPreset.new(),
			PackedStringArray(
				[
					"id",
					"display_name_key",
					"fov_degrees",
					"distance",
					"height",
					"pitch_degrees",
					"follow_smoothing",
					"look_ahead",
				]
			),
		],
		[
			MatchConfig.new(),
			PackedStringArray(
				[
					"seed",
					"rules",
					"flow",
					"pitch",
					"home_team",
					"away_team",
					"stadium",
					"difficulty",
					"period_real_seconds",
					"slot_count",
					"axes_per_slot",
				]
			),
		],
		[
			PitchGeometry.new(),
			PackedStringArray(
				[
					"field_length",
					"field_width",
					"in_goal_depth",
					"line_22_from_try",
					"line_10_from_halfway",
					"line_5_from_try",
					"line_15_from_touch",
					"line_5_from_touch",
					"goal_post_gap",
					"crossbar_height",
					"goal_post_radius",
					"goal_post_bottom",
					"goal_post_top",
					"goal_pad_size",
					"goal_pad_height",
				]
			),
		],
	]
	var missing: Array[String] = []
	for entry: Array in cases:
		var res: Resource = entry[0]
		var fields: PackedStringArray = entry[1]
		for field_name: String in _missing_exports(res, fields):
			@warning_ignore("return_value_discarded")
			missing.append("%s.%s" % [res.get_class(), field_name])
	@warning_ignore("unused_variable")
	var result: GdUnitArrayAssert = assert_array(missing).is_empty()
