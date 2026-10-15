class_name S3ScoreRefereeBridge
extends RefCounted
## Injected scoring/referee bridge. It does not synthesize missing S2/S4 facts.

# gdlint: disable=max-returns
# Each boundary validation rejects before mutating score, pending attempt, or restart state.

enum ResultCode { APPLIED, REJECTED, UNAVAILABLE, PERIOD_END_REQUESTED, UNRESOLVED }

const MISSING_PROVIDERS: PackedStringArray = [
	"S1 committed staged-event and period-transition owner",
	"S2 typed grounding and completed goal-kick facts",
	"S4 typed completed conversion result provider",
]

var rules: RulesConfig
var score: MatchScore = MatchScore.new()
var period_policy: PeriodEndPolicy = PeriodEndPolicy.new()
var period_state: PeriodEndPolicy.PeriodState = PeriodEndPolicy.PeriodState.RUNNING
var pending_conversion_team_id: StringName = &""
var pending_conversion_player_id: StringName = &""
var last_conversion_attempt_id: int = -1
var last_restart: RestartAssignment
var last_report: RefereeReport
var missed_conversion_kickoff_policy_enabled: bool = true
var second_half_transition_resolved: bool = false

var _team_ids: Array[StringName] = []
var _game_time_seconds: float = 0.0
var _period_end_game_seconds: float = 2400.0
var _period_index: int = 1


## Configures the injected test/owner boundary for two stable teams.
func setup(
	team_ids: Array[StringName],
	p_rules: RulesConfig,
	period_index: int,
	period_end_game_seconds: float
) -> bool:
	if (
		p_rules == null
		or not p_rules.validate().is_empty()
		or period_index < 1
		or not is_finite(period_end_game_seconds)
		or period_end_game_seconds <= 0.0
	):
		return false
	var detached_ids: Array[StringName] = team_ids.duplicate()
	if not score.setup(detached_ids):
		return false
	_team_ids = detached_ids
	rules = p_rules.duplicate(true) as RulesConfig
	_period_end_game_seconds = period_end_game_seconds
	_period_index = period_index
	period_state = PeriodEndPolicy.PeriodState.RUNNING
	pending_conversion_team_id = &""
	pending_conversion_player_id = &""
	last_conversion_attempt_id = -1
	last_restart = null
	last_report = null
	_game_time_seconds = 0.0
	return true


## Returns production readiness blockers; no current S1/S2/S4 provider is fabricated.
func production_blockers() -> PackedStringArray:
	return MISSING_PROVIDERS.duplicate()


## This isolated bridge remains unavailable to the live match until providers are wired.
func is_production_available() -> bool:
	return false


## Advances only its injected clock view and enters TIME_UP when it reaches the end.
func observe_clock(game_time_seconds: float) -> bool:
	if (
		not is_finite(game_time_seconds)
		or game_time_seconds < _game_time_seconds
		or period_state != PeriodEndPolicy.PeriodState.RUNNING
	):
		return false
	_game_time_seconds = minf(game_time_seconds, _period_end_game_seconds)
	if _game_time_seconds >= _period_end_game_seconds:
		period_state = PeriodEndPolicy.PeriodState.TIME_UP
	return true


## Accepts an already-eligible try report supplied by an upstream fact owner.
func submit_eligible_try(report: RefereeReport) -> ResultCode:
	if not _configured() or report == null or not report.validate().is_empty():
		return _reject()
	if (
		report.reason != RefereeReport.StoppageReason.TRY
		or report.decision != RefereeReport.Decision.CONVERSION
		or not _team_ids.has(report.offending_team_id)
		or report.player_id == &""
		or period_state == PeriodEndPolicy.PeriodState.PERIOD_ENDED
		or pending_conversion_team_id != &""
	):
		return _reject()
	var stamped: RefereeReport = report.stamped(_game_time_seconds)
	var conversion_restart: RestartAssignment = RestartAssignment.new()
	conversion_restart.kind = RestartAssignment.Kind.CONVERSION
	conversion_restart.team_id = report.offending_team_id
	conversion_restart.cause = RefereeReport.Decision.CONVERSION
	if not conversion_restart.validate().is_empty():
		return _reject()
	if not score.increment(report.offending_team_id, ScoreCounters.Counter.TRY):
		return _reject()
	pending_conversion_team_id = report.offending_team_id
	pending_conversion_player_id = report.player_id
	last_report = stamped
	last_restart = conversion_restart
	return ResultCode.APPLIED


## Consumes one completed S4 result exactly once for the matching pending try.
func resolve_conversion(result: ConversionResult) -> ResultCode:
	if not _configured() or result == null or not result.validate().is_empty():
		return _reject()
	if (
		pending_conversion_team_id == &""
		or result.team_id != pending_conversion_team_id
		or not _team_ids.has(result.team_id)
		or result.attempt_id <= last_conversion_attempt_id
	):
		return _reject()
	var ends_period: bool = period_state == PeriodEndPolicy.PeriodState.TIME_UP
	var transition_unresolved: bool = (
		ends_period and _period_index == 2 and not second_half_transition_resolved
	)
	var scoring_team: StringName = pending_conversion_team_id
	var conceding_team: StringName = _opponent_of(scoring_team)
	if (
		result.outcome == ConversionResult.Outcome.MISS
		and not missed_conversion_kickoff_policy_enabled
	):
		return _reject()
	if (
		result.outcome == ConversionResult.Outcome.SUCCESS
		and not score.increment(scoring_team, ScoreCounters.Counter.CONVERSION)
	):
		return _reject()
	last_conversion_attempt_id = result.attempt_id
	pending_conversion_team_id = &""
	pending_conversion_player_id = &""
	last_restart = null
	if transition_unresolved:
		return ResultCode.UNRESOLVED
	if ends_period:
		period_state = PeriodEndPolicy.PeriodState.PERIOD_ENDED
		return ResultCode.PERIOD_END_REQUESTED
	var assignment: RestartAssignment = RestartAssignment.new()
	assignment.team_id = conceding_team
	assignment.cause = RefereeReport.Decision.KICK_OFF
	if not assignment.validate().is_empty():
		return _reject()
	last_restart = assignment
	return ResultCode.APPLIED


## Stamps and evaluates an injected report after upstream precedence checks.
func process_report(report: RefereeReport) -> ResultCode:
	if not _configured() or report == null or not report.validate().is_empty():
		return _reject()
	if not _team_ids.has(report.offending_team_id):
		return _reject()
	var stamped: RefereeReport = report.stamped(_game_time_seconds)
	var gate: PeriodEndPolicy.GateResult = period_policy.evaluate(
		stamped,
		period_state,
		_period_index,
		_period_end_game_seconds,
		second_half_transition_resolved
	)
	last_report = stamped
	if gate == PeriodEndPolicy.GateResult.SECOND_HALF_UNRESOLVED:
		return ResultCode.UNRESOLVED
	if gate == PeriodEndPolicy.GateResult.END_PERIOD:
		period_state = PeriodEndPolicy.PeriodState.PERIOD_ENDED
		last_restart = null
		return ResultCode.PERIOD_END_REQUESTED
	return ResultCode.APPLIED


## Returns a stable state snapshot; restart and score are detached values.
func snapshot() -> Dictionary:
	var restart_snapshot: Dictionary = {}
	if last_restart != null:
		restart_snapshot = {
			"kind": last_restart.kind,
			"team_id": last_restart.team_id,
			"position": last_restart.position if last_restart.has_position else null,
			"has_position": last_restart.has_position,
			"cause": last_restart.cause,
		}
	return {
		"period_state": period_state,
		"game_time_seconds": _game_time_seconds,
		"score": score.snapshot(),
		"pending_conversion_team_id": pending_conversion_team_id,
		"pending_conversion_player_id": pending_conversion_player_id,
		"last_conversion_attempt_id": last_conversion_attempt_id,
		"restart": restart_snapshot,
	}


func _configured() -> bool:
	return rules != null and _team_ids.size() == 2


func _reject() -> ResultCode:
	return ResultCode.REJECTED


func _opponent_of(team_id: StringName) -> StringName:
	for current: StringName in _team_ids:
		if current != team_id:
			return current
	return &""
