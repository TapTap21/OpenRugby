class_name MatchReplay
extends RefCounted
## Static helpers that re-run a recorded match through the live composition builder.


## Re-runs [param log]; null when setup, outputs or command sequencing differ.
static func run(
	config: MatchConfig,
	log: InputLog,
	mod_set_hash: String,
	systems: Array[SimSystem] = [],
	extension_points: ExtensionPoints = null,
	s2_port: S2RuntimePort = null,
	current_action_layout_hash: String = ""
) -> MatchSim:
	if config == null or log == null or log.header == null:
		return null
	if log.header.format_version != ReplayHeader.CURRENT_FORMAT_VERSION:
		return null
	if current_action_layout_hash.is_empty():
		return null
	if (
		log.header.slot_count != config.slot_count
		or log.header.axes_per_slot != config.axes_per_slot
	):
		return null
	var port: S2RuntimePort = s2_port if s2_port != null else S2RuntimePort.new()
	if not port.reset_runtime():
		return null
	var replay_config: MatchConfig = config.duplicate(true) as MatchConfig
	replay_config.seed = log.header.seed
	var request: MatchCompositionRequest = MatchCompositionRequest.new()
	request.config = replay_config
	request.systems = systems.duplicate()
	request.mod_set_hash = mod_set_hash
	request.action_layout_hash = current_action_layout_hash
	request.extension_points = extension_points
	request.s2 = port
	var build: MatchBuildResult = MatchCompositionBuilder.build(request)
	if not build.is_success():
		return null
	if not log.header.is_compatible_with(
		mod_set_hash, request.action_layout_hash, build.setup_fingerprint
	):
		return null
	var frame: InputFrame = InputFrame.new(log.header.slot_count, log.header.axes_per_slot)
	for index: int in log.frame_count():
		if build.sim.is_finished():
			break
		if not log.read_frame(index, frame):
			return null
		if not port.enqueue_replay_commands(log.frame_commands(index)):
			return null
		build.sim.tick(frame)
		if not build.sim.last_tick_succeeded:
			return null
		if port.results_since(0) != log.frame_outputs(index):
			return null
	return build.sim
