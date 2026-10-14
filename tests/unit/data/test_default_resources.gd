class_name TestDefaultResources
extends GdUnitTestSuite
## Tests for the four default data resources and MatchConfig.create_default (S1-core section 5,
## criteria C-41 and C-42).

const DEFAULTS_DIR: String = "res://game/data/defaults/"


func _load_default(file_name: String) -> Resource:
	return ResourceLoader.load(DEFAULTS_DIR + file_name, "", ResourceLoader.CACHE_MODE_IGNORE)


## C-41: default_rules.tres loads as a RulesConfig and validates.
func test_c41_default_rules_loads_and_validates() -> void:
	var rules: RulesConfig = _load_default("default_rules.tres") as RulesConfig
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(rules != null).is_true()
	if rules == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(rules.validate().size()).is_equal(0)


## C-41: default_attribute_schema.tres loads as a PlayerAttributeSchema and validates.
func test_c41_default_attribute_schema_loads_and_validates() -> void:
	var schema: PlayerAttributeSchema = (
		_load_default("default_attribute_schema.tres") as PlayerAttributeSchema
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(schema != null).is_true()
	if schema == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(schema.validate().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(schema.has_attribute(&"scrummaging")).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = assert_bool(schema.has_attribute(&"speed")).is_true()


## C-41: default_difficulty.tres loads as a DifficultyProfile and validates.
func test_c41_default_difficulty_loads_and_validates() -> void:
	var difficulty: DifficultyProfile = (
		_load_default("default_difficulty.tres") as DifficultyProfile
	)
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(difficulty != null).is_true()
	if difficulty == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(difficulty.validate().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(String(difficulty.id)).is_equal("normal")
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(difficulty.level).is_equal(1)


## C-41: default_camera_preset.tres loads as a CameraPreset and validates.
func test_c41_default_camera_preset_loads_and_validates() -> void:
	var preset: CameraPreset = _load_default("default_camera_preset.tres") as CameraPreset
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(preset != null).is_true()
	if preset == null:
		return
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(preset.validate().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r3: GdUnitStringAssert = assert_str(String(preset.id)).is_equal("broadcast")


## C-42: MatchConfig.create_default is valid and loads rules, flow and pitch.
func test_c42_create_default_config_is_valid() -> void:
	var config: MatchConfig = MatchConfig.create_default()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(config.validate().size()).is_equal(0)
	@warning_ignore("unused_variable")
	var r2: GdUnitObjectAssert = assert_object(config.rules).is_not_null()
	@warning_ignore("unused_variable")
	var r3: GdUnitObjectAssert = assert_object(config.flow).is_not_null()
	@warning_ignore("unused_variable")
	var r4: GdUnitObjectAssert = assert_object(config.pitch).is_not_null()


## C-42: a slot count of zero is reported.
func test_c42_zero_slot_count_reported() -> void:
	var config: MatchConfig = MatchConfig.create_default()
	config.slot_count = 0
	@warning_ignore("unused_variable")
	var result: GdUnitBoolAssert = assert_bool(config.validate().size() > 0).is_true()
