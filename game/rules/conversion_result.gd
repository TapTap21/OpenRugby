class_name ConversionResult
extends RefCounted
## Completed conversion outcome delivered by the S4 place-kick owner.

enum Outcome { SUCCESS, MISS }

var team_id: StringName = &""
var scorer_id: StringName = &""
var outcome: Outcome = Outcome.MISS
var attempt_id: int = -1
var game_time_seconds: float = 0.0


## Validates identity, outcome and stable attempt sequencing data.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if team_id == &"":
		errors += PackedStringArray(["team_id is required"])
	if scorer_id == &"":
		errors += PackedStringArray(["scorer_id is required"])
	if outcome != Outcome.SUCCESS and outcome != Outcome.MISS:
		errors += PackedStringArray(["unknown conversion outcome"])
	if attempt_id < 0:
		errors += PackedStringArray(["attempt_id must be non-negative"])
	if not is_finite(game_time_seconds) or game_time_seconds < 0.0:
		errors += PackedStringArray(["game_time_seconds must be finite and non-negative"])
	return errors
