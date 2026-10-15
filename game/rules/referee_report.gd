class_name RefereeReport
extends RefCounted
## Rebuild-owned referee report values used by the narrow scoring/time-up bridge.

enum StoppageReason {
	FORWARD_PASS = 0x16,
	KNOCK_ON = 0x31,
	OFFSIDE = 0x2C,
	RUCK_HANDLING = 0x21,
	RUCK_UNPLAYABLE = 0x0F,
	RUCK_IN_GOAL = 0x2B,
	RUCK_TIME_WASTING = 0x1E,
	MAUL_COLLAPSE = 0x14,
	DANGEROUS_TACKLE = 0x36,
	DELAY_OF_GAME = 0x32,
	SLOW_LINEOUT = 0x33,
	LINEOUT_OFFENCE = 0x1F,
	SCRUM_COLLAPSE = 0x13,
	SCRUM_FEED_OFFENCE_A = 0x1C,
	SCRUM_FEED_OFFENCE_B = 0x1D,
	SCRUM_HALF_OFFENCE = 0x20,
	SCRUM_WHEEL_A = 0x0D,
	SCRUM_WHEEL_B = 0x0E,
	SCRUM_DECISION_A = 0x1A,
	SCRUM_DECISION_B = 0x1B,
	MARK = 0x30,
	KICK_AT_GOAL_IN = 1,
	KICK_AT_GOAL_OUT = 2,
	DROP_GOAL_SCORED = 3,
	TRY = 4,
	BALL_DEAD_IN_GOAL = 0x34,
	BALL_DEAD = 0x11,
	BALL_IN_TOUCH = 0x12,
	KICK_OFF_NOT_TEN = 0x2F,
	DEFENSIVE_GROUNDING_IN_GOAL = 0x2D,
	GENERAL_PENALTY = 0x35,
}

enum Decision {
	PENALTY = 1,
	SCRUM_RETRY = 2,
	SCRUM = 3,
	FREE_KICK = 4,
	END_OF_PERIOD = 5,
	DROP_OUT_22 = 6,
	OTHER_7 = 7,
	LINEOUT = 8,
	KICK_OFF = 9,
	KICK_AT_GOAL_RESULT = 10,
	OTHER_11 = 11,
	OTHER_12 = 12,
	OTHER_13 = 13,
	OTHER_14 = 14,
	PENALTY_TRY = 15,
	CONVERSION = 16,
	DROP_GOAL_RESTART = 17,
}

var reason: StoppageReason = StoppageReason.TRY
var decision: Decision = Decision.CONVERSION
var offending_team_id: StringName = &""
var player_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var has_report_time: bool = false
var report_time_game_seconds: float = 0.0
var from_advantage: bool = false


## Validates the observed report identities represented by this rebuild type.
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
	return (
		value
		in [
			1,
			2,
			3,
			4,
			0x0D,
			0x0E,
			0x0F,
			0x11,
			0x12,
			0x13,
			0x14,
			0x16,
			0x1A,
			0x1B,
			0x1C,
			0x1D,
			0x1E,
			0x1F,
			0x20,
			0x21,
			0x2B,
			0x2C,
			0x2D,
			0x2F,
			0x30,
			0x31,
			0x32,
			0x33,
			0x34,
			0x35,
			0x36,
		]
	)


func _known_decision(value: int) -> bool:
	return value in range(1, 18)
