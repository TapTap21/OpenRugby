class_name RulesConfig
extends Resource
## Law parameters. S3 extends it.

## TBC-RE.
@export var period_count: int = 2
## Displayed length of one period in game seconds (40 minutes).
@export var period_game_seconds: int = 2400
@export var players_per_side: int = 15
## PROVISIONAL.
@export var replacements_allowed: int = 7
## TBC-RE.
@export var points_try: int = 5
## TBC-RE.
@export var points_conversion: int = 2
## TBC-RE.
@export var points_penalty_goal: int = 3
## TBC-RE.
@export var points_drop_goal: int = 3
## 2007 law: try plus conversion attempt; TBC-RE.
@export var points_penalty_try: int = 5
## 2007 law; the modern law is false; TBC-RE.
@export var penalty_try_awards_conversion: bool = true
## TBC-RE.
@export var sin_bin_game_seconds: int = 600
## PROVISIONAL bag for RE law parameters until promoted to fields.
@export var extra: Dictionary[StringName, float] = {}


## Returns one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if period_count < 1:
		errors += PackedStringArray(["period_count must be at least 1"])
	if period_game_seconds < 1:
		errors += PackedStringArray(["period_game_seconds must be at least 1"])
	if players_per_side < 1:
		errors += PackedStringArray(["players_per_side must be at least 1"])
	var points: Dictionary[String, int] = {
		"points_try": points_try,
		"points_conversion": points_conversion,
		"points_penalty_goal": points_penalty_goal,
		"points_drop_goal": points_drop_goal,
		"points_penalty_try": points_penalty_try,
	}
	for key: String in points:
		if points[key] < 0:
			errors += PackedStringArray(["%s must not be negative" % key])
	return errors
