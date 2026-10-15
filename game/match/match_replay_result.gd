class_name MatchReplayResult
extends RefCounted
## Typed outcome from direct replay, including setup readiness and replay failure category.

# `NONE` means playback has not failed; setup can still be unavailable. Success requires
# `error == OK` and `sim != null`.
enum ReplayFailure {
	NONE,
	INVALID_RECORD,
	INVALID_LINKAGE,
	INCOMPATIBLE_HEADER,
	PORT_RESET_FAILED,
	TICK_FAILED,
	OUTPUT_MISMATCH,
	FATAL_ROLLBACK,
}

enum ReadinessEvaluation { NOT_EVALUATED, PREFLIGHT_ONLY, BUILDER_COMPLETE }

var sim: MatchSim
var error: Error = ERR_UNCONFIGURED
var replay_failure: ReplayFailure = ReplayFailure.NONE
var fatal_reason: StringName = &""
var readiness_evaluation: ReadinessEvaluation = ReadinessEvaluation.NOT_EVALUATED
var readiness: MatchReadinessReport = MatchReadinessReport.new()
