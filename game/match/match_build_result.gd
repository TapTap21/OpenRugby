class_name MatchBuildResult
extends RefCounted
## Typed result from the canonical live/replay composition builder.

var error: Error = ERR_UNCONFIGURED
var readiness: MatchReadinessReport = MatchReadinessReport.new()
var sim: MatchSim
var s2: S2RuntimePort
var setup_fingerprint: String = ""
var system_ids: Array[StringName] = []


## True when the builder created a runnable simulation.
func is_success() -> bool:
	return error == OK and sim != null and readiness.is_ready()
