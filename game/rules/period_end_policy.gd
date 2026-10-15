class_name PeriodEndPolicy
extends RefCounted
## Evidence-bounded time-up report whitelist with an unavailable second-half gate.

# gdlint: disable=max-returns
# The whitelist is intentionally explicit so each non-qualifying condition is easy to audit.

enum PeriodState { RUNNING, TIME_UP, PERIOD_ENDED }
enum GateResult { NO_END, END_PERIOD, SECOND_HALF_UNRESOLVED }


## Evaluates a stamped report after advantage and quick-option precedence.
func evaluate(
	report: RefereeReport,
	period_state: PeriodState,
	period_index: int,
	period_end_game_seconds: float,
	second_half_transition_resolved: bool = false
) -> GateResult:
	if report == null or not report.validate().is_empty():
		return GateResult.NO_END
	if period_state != PeriodState.TIME_UP:
		return GateResult.NO_END
	if not is_finite(period_end_game_seconds) or period_end_game_seconds < 0.0:
		return GateResult.NO_END
	if not _qualifies(report, period_end_game_seconds):
		return GateResult.NO_END
	if period_index == 2 and not second_half_transition_resolved:
		return GateResult.SECOND_HALF_UNRESOLVED
	return GateResult.END_PERIOD


func _qualifies(report: RefereeReport, period_end: float) -> bool:
	match report.reason:
		RefereeReport.StoppageReason.KICK_AT_GOAL_IN:
			return true
		RefereeReport.StoppageReason.KICK_AT_GOAL_OUT:
			return true
		RefereeReport.StoppageReason.DROP_GOAL_SCORED:
			return true
		RefereeReport.StoppageReason.BALL_DEAD:
			return (
				(
					report.decision
					in [RefereeReport.Decision.SCRUM, RefereeReport.Decision.DROP_OUT_22]
				)
				and report.report_time_game_seconds >= period_end
			)
		RefereeReport.StoppageReason.BALL_IN_TOUCH:
			return (
				report.decision == RefereeReport.Decision.LINEOUT
				and report.report_time_game_seconds >= period_end
			)
		RefereeReport.StoppageReason.DEFENSIVE_GROUNDING_IN_GOAL:
			return (
				report.decision == RefereeReport.Decision.DROP_OUT_22
				and report.report_time_game_seconds >= period_end
			)
	return false
