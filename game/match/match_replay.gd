class_name MatchReplay
extends RefCounted
## Static helpers that re-run a recorded match.


## Re-runs [param log] against [param config]; null when the mod set or shape differs.
static func run(
	_config: MatchConfig, _log: InputLog, _mod_set_hash: String, _systems: Array[SimSystem] = []
) -> MatchSim:
	# Replay stays disabled until the reviewed S2 codec and one-shot receipt are available.
	return null
