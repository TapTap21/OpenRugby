class_name MatchConfig
extends Resource
## Everything needed to start a match. Teams, stadium and difficulty may be null in S1.

@export var seed: int = 0
@export var rules: RulesConfig
@export var flow: MatchFlowConfig
@export var pitch: PitchGeometry
@export var home_team: Team
@export var away_team: Team
@export var stadium: Stadium
@export var difficulty: DifficultyProfile
## Real seconds per period (PROVISIONAL, the match-length option).
@export var period_real_seconds: int = 300
@export var slot_count: int = 1
@export var axes_per_slot: int = 2


## Builds a config from the default rules, flow and pitch resources.
static func create_default() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	var rules_res: RulesConfig = load("res://game/data/defaults/default_rules.tres") as RulesConfig
	var flow_res: MatchFlowConfig = (
		load("res://game/match/flow/default_match_flow.tres") as MatchFlowConfig
	)
	var pitch_res: PitchGeometry = (
		load("res://game/match/pitch/default_pitch.tres") as PitchGeometry
	)
	config.rules = rules_res.duplicate(true) as RulesConfig
	config.flow = flow_res.duplicate(true) as MatchFlowConfig
	config.pitch = pitch_res.duplicate(true) as PitchGeometry
	return config


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if rules == null:
		errors += PackedStringArray(["rules is null"])
	else:
		errors.append_array(rules.validate())
	if flow == null:
		errors += PackedStringArray(["flow is null"])
	else:
		errors.append_array(flow.validate())
	if pitch == null:
		errors += PackedStringArray(["pitch is null"])
	else:
		errors.append_array(pitch.validate())
	if period_real_seconds < 1:
		errors += PackedStringArray(["period_real_seconds must be at least 1"])
	if slot_count < 1 or slot_count > 8:
		errors += PackedStringArray(["slot_count must be in 1..8"])
	if axes_per_slot < 0 or axes_per_slot > 16:
		errors += PackedStringArray(["axes_per_slot must be in 0..16"])
	return errors
