class_name MatchReplay
extends RefCounted
## Static helpers that re-run a recorded match.


## Re-runs [param log] against [param config]; null when the mod set or shape differs.
static func run(
	config: MatchConfig, log: InputLog, mod_set_hash: String, systems: Array[SimSystem] = []
) -> MatchSim:
	var header: ReplayHeader = log.header
	if not header.is_compatible_with(mod_set_hash, header.action_layout_hash):
		return null
	if header.slot_count != config.slot_count or header.axes_per_slot != config.axes_per_slot:
		return null
	var replay_config: MatchConfig = config.duplicate() as MatchConfig
	replay_config.seed = header.seed
	var sim: MatchSim = MatchSim.new(replay_config)
	for system: SimSystem in systems:
		sim.add_system(system)
	var frame: InputFrame = InputFrame.new(header.slot_count, header.axes_per_slot)
	for i: int in log.frame_count():
		if sim.is_finished():
			break
		var ok: bool = log.read_frame(i, frame)
		assert(ok)
		sim.tick(frame)
	return sim
