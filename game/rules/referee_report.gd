class_name RefereeReport
extends RefCounted
## Rebuild-owned referee report values used by the narrow scoring/time-up bridge.

enum StoppageReason {
	KICK_AT_GOAL_IN = 1,
	KICK_AT_GOAL_OUT = 2,
	DROP_GOAL_SCORED = 3,
	TRY = 4,
	BALL_DEAD = 0x11,
	BALL_IN_TOUCH = 0x12,
	DEFENSIVE_GROUNDING_IN_GOAL = 0x2D,
}

enum Decision {
	SCRUM = 3,
	END_OF_PERIOD = 5,
	DROP_OUT_22 = 6,
	LINEOUT = 8,
	KICK_OFF = 9,
	CONVERSION = 16,
}

var reason: StoppageReason = StoppageReason.TRY
var decision: Decision = Decision.CONVERSION
var offending_team_id: StringName = &""
var player_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var has_report_time: bool = false
var report_time_game_seconds: float = 0.0
var from_advantage: bool = false


## Validates the subset of report identities handled by this bridge.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if not _known_reason(reason):
		errors += PackedStringArray(["unknown stoppage reason"])
	if not _known_decision(decision):
		errors += PackedStringArray(["unknown referee decision"])
	if offending_team_id == &"":
		errors += PackedStringArray(["offending_team_id is required"])
	if not position.is_finite():
		errors += PackedStringArray(["position must be finite"])
	if (
		has_report_time
		and (not is_finite(report_time_game_seconds) or report_time_game_seconds < 0.0)
	):
		errors += PackedStringArray(["report time must be finite and non-negative"])
	return errors


## Returns a detached report with a stamped time when absent.
func stamped(game_time_seconds: float) -> RefereeReport:
	var result: RefereeReport = RefereeReport.new()
	result.reason = reason
	result.decision = decision
	result.offending_team_id = offending_team_id
	result.player_id = player_id
	result.position = position
	result.has_report_time = true
	result.report_time_game_seconds = (
		report_time_game_seconds if has_report_time else game_time_seconds
	)
	result.from_advantage = from_advantage
	return result


func _known_reason(value: int) -> bool:
	return value in [1, 2, 3, 4, 0x11, 0x12, 0x2D]


func _known_decision(value: int) -> bool:
	return value in [3, 5, 6, 8, 9, 16]
