class_name TestS3ScoreRefereeBridge
extends GdUnitTestSuite
## Acceptance coverage for the isolated, injected S3 scoring/referee bridge.

const TEAM_A: StringName = &"team_a"
const TEAM_B: StringName = &"team_b"
const PLAYER_A: StringName = &"player_a"


func _bridge(period_index: int = 1) -> S3ScoreRefereeBridge:
	var bridge: S3ScoreRefereeBridge = S3ScoreRefereeBridge.new()
	var rules: RulesConfig = RulesConfig.new()
	var end_time: float = 2400.0 if period_index == 1 else 4800.0
	@warning_ignore("unused_variable")
	var configured: bool = bridge.setup([TEAM_A, TEAM_B], rules, period_index, end_time)
	return bridge


func _try_report(team_id: StringName = TEAM_A) -> RefereeReport:
	var report: RefereeReport = RefereeReport.new()
	report.reason = RefereeReport.StoppageReason.TRY
	report.decision = RefereeReport.Decision.CONVERSION
	report.offending_team_id = team_id
	report.player_id = PLAYER_A
	report.position = Vector3(0.0, 0.0, 50.0)
	return report


func _conversion(outcome: ConversionResult.Outcome, attempt_id: int = 1) -> ConversionResult:
	var result: ConversionResult = ConversionResult.new()
	result.team_id = TEAM_A
	result.scorer_id = PLAYER_A
	result.outcome = outcome
	result.attempt_id = attempt_id
	result.game_time_seconds = 100.0
	return result


## The score totals derive from four typed counters and stable team IDs.
func test_score_counters_use_rules_config_and_detached_snapshots() -> void:
	var score: MatchScore = MatchScore.new()
	var rules: RulesConfig = RulesConfig.new()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(score.setup([TEAM_A, TEAM_B])).is_true()
	@warning_ignore("unused_variable")
	var inc_tries: bool = score.increment(TEAM_A, ScoreCounters.Counter.TRY, 2)
	@warning_ignore("unused_variable")
	var inc_conversions: bool = score.increment(TEAM_A, ScoreCounters.Counter.CONVERSION)
	@warning_ignore("unused_variable")
	var inc_penalties: bool = score.increment(TEAM_A, ScoreCounters.Counter.PENALTY_GOAL)
	@warning_ignore("unused_variable")
	var inc_drop_goals: bool = score.increment(TEAM_A, ScoreCounters.Counter.DROP_GOAL)
	var counters: ScoreCounters = score.counters_for(TEAM_A)
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(counters.points_total(rules)).is_equal(18)
	var snapshot: Dictionary[StringName, int] = counters.snapshot()
	@warning_ignore("unused_variable")
	var r3: GdUnitBoolAssert = assert_bool(snapshot.is_read_only()).is_true()
	@warning_ignore("unused_variable")
	var r4: GdUnitBoolAssert = (
		assert_bool(score.increment(TEAM_A, ScoreCounters.Counter.TRY, 0)).is_false()
	)


## A try report awards five points and creates a conversion restart, not a kickoff.
func test_try_report_opens_pending_conversion_and_conversion_restart() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge()
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(bridge.submit_eligible_try(_try_report())).is_equal(
		S3ScoreRefereeBridge.ResultCode.APPLIED
	)
	var state: Dictionary = bridge.snapshot()
	var score: Dictionary = state["score"]
	var team_score: Dictionary = score[TEAM_A]
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(team_score[&"tries"]).is_equal(1)
	@warning_ignore("unused_variable")
	var r3: GdUnitAssert = assert_that(state["pending_conversion_team_id"]).is_equal(TEAM_A)
	var restart: Dictionary = state["restart"]
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(restart["kind"]).is_equal(
		RestartAssignment.Kind.CONVERSION
	)
	@warning_ignore("unused_variable")
	var r5: GdUnitBoolAssert = assert_bool(restart["has_position"]).is_false()


## Success applies once, clears pending state and assigns the opponent kickoff.
func test_conversion_success_is_idempotent_and_assigns_conceding_team_kickoff() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge()
	@warning_ignore("unused_variable")
	var try_result: S3ScoreRefereeBridge.ResultCode = bridge.submit_eligible_try(_try_report())
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = (
		assert_int(bridge.resolve_conversion(_conversion(ConversionResult.Outcome.SUCCESS)))
		. is_equal(S3ScoreRefereeBridge.ResultCode.APPLIED)
	)
	var state: Dictionary = bridge.snapshot()
	var team_score: Dictionary = state["score"][TEAM_A]
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(team_score[&"conversions"]).is_equal(1)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(state["last_conversion_attempt_id"]).is_equal(1)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = (
		assert_int(bridge.resolve_conversion(_conversion(ConversionResult.Outcome.SUCCESS)))
		. is_equal(S3ScoreRefereeBridge.ResultCode.REJECTED)
	)
	var restart: Dictionary = bridge.snapshot()["restart"]
	@warning_ignore("unused_variable")
	var r5: GdUnitAssert = assert_that(restart["team_id"]).is_equal(TEAM_B)
	@warning_ignore("unused_variable")
	var r6: GdUnitIntAssert = assert_int(team_score[&"conversions"]).is_equal(1)


## A wrong team's result cannot consume the pending conversion or mutate score.
func test_wrong_team_conversion_result_is_rejected_without_state_change() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge()
	@warning_ignore("unused_variable")
	var try_result: S3ScoreRefereeBridge.ResultCode = bridge.submit_eligible_try(_try_report())
	var wrong_team: ConversionResult = _conversion(ConversionResult.Outcome.SUCCESS)
	wrong_team.team_id = TEAM_B
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = assert_int(bridge.resolve_conversion(wrong_team)).is_equal(
		S3ScoreRefereeBridge.ResultCode.REJECTED
	)
	var state: Dictionary = bridge.snapshot()
	var counters: Dictionary = state["score"][TEAM_A]
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(counters[&"conversions"]).is_equal(0)
	@warning_ignore("unused_variable")
	var r3: GdUnitAssert = assert_that(state["pending_conversion_team_id"]).is_equal(TEAM_A)


## An unresolved second-half transition preserves score without guessing the match result.
func test_second_half_conversion_scores_but_transition_stays_unresolved() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge(2)
	@warning_ignore("unused_variable")
	var clock_observed: bool = bridge.observe_clock(5000.0)
	@warning_ignore("unused_variable")
	var try_result: S3ScoreRefereeBridge.ResultCode = bridge.submit_eligible_try(_try_report())
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = (
		assert_int(bridge.resolve_conversion(_conversion(ConversionResult.Outcome.SUCCESS)))
		. is_equal(S3ScoreRefereeBridge.ResultCode.UNRESOLVED)
	)
	var state: Dictionary = bridge.snapshot()
	var counters: Dictionary = state["score"][TEAM_A]
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(counters[&"conversions"]).is_equal(1)
	@warning_ignore("unused_variable")
	var r3: GdUnitDictionaryAssert = assert_dict(state["restart"]).is_empty()
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = assert_int(state["period_state"]).is_equal(
		PeriodEndPolicy.PeriodState.TIME_UP
	)


## Missed conversion kickoff is an explicit inferred policy and can be disabled.
func test_conversion_miss_policy_gate_preserves_pending_attempt_when_disabled() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge()
	@warning_ignore("unused_variable")
	var try_result: S3ScoreRefereeBridge.ResultCode = bridge.submit_eligible_try(_try_report())
	bridge.missed_conversion_kickoff_policy_enabled = false
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = (
		assert_int(bridge.resolve_conversion(_conversion(ConversionResult.Outcome.MISS)))
		. is_equal(S3ScoreRefereeBridge.ResultCode.REJECTED)
	)
	@warning_ignore("unused_variable")
	var r2: GdUnitAssert = assert_that(bridge.pending_conversion_team_id).is_equal(TEAM_A)
	bridge.missed_conversion_kickoff_policy_enabled = true
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = (
		assert_int(bridge.resolve_conversion(_conversion(ConversionResult.Outcome.MISS)))
		. is_equal(S3ScoreRefereeBridge.ResultCode.APPLIED)
	)
	var restart: Dictionary = bridge.snapshot()["restart"]
	@warning_ignore("unused_variable")
	var r4: GdUnitAssert = assert_that(restart["team_id"]).is_equal(TEAM_B)


## Time-up freezes at the end; a try still allows conversion, whose result ends period one.
func test_time_up_try_and_conversion_finish_first_period_without_kickoff() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(bridge.observe_clock(2500.0)).is_true()
	@warning_ignore("unused_variable")
	var r2: GdUnitFloatAssert = assert_float(bridge.snapshot()["game_time_seconds"]).is_equal(
		2400.0
	)
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = assert_int(bridge.submit_eligible_try(_try_report())).is_equal(
		S3ScoreRefereeBridge.ResultCode.APPLIED
	)
	@warning_ignore("unused_variable")
	var r4: GdUnitIntAssert = (
		assert_int(bridge.resolve_conversion(_conversion(ConversionResult.Outcome.MISS)))
		. is_equal(S3ScoreRefereeBridge.ResultCode.PERIOD_END_REQUESTED)
	)
	var state: Dictionary = bridge.snapshot()
	@warning_ignore("unused_variable")
	var r5: GdUnitIntAssert = assert_int(state["period_state"]).is_equal(
		PeriodEndPolicy.PeriodState.PERIOD_ENDED
	)
	@warning_ignore("unused_variable")
	var r6: GdUnitDictionaryAssert = assert_dict(state["restart"]).is_empty()


## The time-up whitelist qualifies only observed report types and respects report time.
func test_time_up_report_whitelist_and_second_half_unknown_gate() -> void:
	var policy: PeriodEndPolicy = PeriodEndPolicy.new()
	var lineout: RefereeReport = RefereeReport.new()
	lineout.reason = RefereeReport.StoppageReason.BALL_IN_TOUCH
	lineout.decision = RefereeReport.Decision.LINEOUT
	lineout.offending_team_id = TEAM_A
	lineout.has_report_time = true
	lineout.report_time_game_seconds = 2400.0
	@warning_ignore("unused_variable")
	var r1: GdUnitIntAssert = (
		assert_int(policy.evaluate(lineout, PeriodEndPolicy.PeriodState.TIME_UP, 1, 2400.0))
		. is_equal(PeriodEndPolicy.GateResult.END_PERIOD)
	)
	lineout.reason = RefereeReport.StoppageReason.TRY
	lineout.decision = RefereeReport.Decision.CONVERSION
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = (
		assert_int(policy.evaluate(lineout, PeriodEndPolicy.PeriodState.TIME_UP, 1, 2400.0))
		. is_equal(PeriodEndPolicy.GateResult.NO_END)
	)
	lineout.reason = RefereeReport.StoppageReason.BALL_IN_TOUCH
	lineout.decision = RefereeReport.Decision.LINEOUT
	lineout.report_time_game_seconds = 4800.0
	@warning_ignore("unused_variable")
	var r3: GdUnitIntAssert = (
		assert_int(policy.evaluate(lineout, PeriodEndPolicy.PeriodState.TIME_UP, 2, 4800.0))
		. is_equal(PeriodEndPolicy.GateResult.SECOND_HALF_UNRESOLVED)
	)


## Production remains unavailable while the match, physical-event and place-kick owners are absent.
func test_live_match_integration_lists_missing_provider_contracts() -> void:
	var bridge: S3ScoreRefereeBridge = _bridge()
	@warning_ignore("unused_variable")
	var r1: GdUnitBoolAssert = assert_bool(bridge.is_production_available()).is_false()
	@warning_ignore("unused_variable")
	var r2: GdUnitIntAssert = assert_int(bridge.production_blockers().size()).is_equal(3)
