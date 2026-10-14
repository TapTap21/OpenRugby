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
	var expected_sequence: int = 0
	for index: int in log.frame_count():
		if build.sim.is_finished():
			break
		var commands: Array[Dictionary] = log.frame_commands(index)
		var outputs: Array[Dictionary] = log.frame_outputs(index)
		if not _validate_frame_records(commands, outputs, expected_sequence):
			return null
		expected_sequence += commands.size()
		if not log.read_frame(index, frame):
			return null
		if not port.enqueue_replay_commands(commands):
			return null
		build.sim.tick(frame)
		if not build.sim.last_tick_succeeded:
			return null
		if not _records_equal(port.results_since(0), outputs):
			return null
	return build.sim


static func _validate_frame_records(
	command_records: Array[Dictionary], output_records: Array[Dictionary], first_sequence: int
) -> bool:
	var commands: Dictionary[int, S2RuntimeCommand] = {}
	var expected_sequence: int = first_sequence
	for record: Dictionary in command_records:
		var command: S2RuntimeCommand = S2RuntimeCommand.from_snapshot(record)
		if (
			command == null
			or not command.validate().is_empty()
			or command.sequence != expected_sequence
			or commands.has(command.sequence)
		):
			return false
		commands[command.sequence] = command
		expected_sequence += 1
	var seen_outputs: Dictionary[int, bool] = {}
	var previous_phase: int = -1
	var previous_actor: String = ""
	var previous_sequence: int = -1
	for record: Dictionary in output_records:
		var output: S2RuntimeResult = S2RuntimeResult.from_snapshot(record)
		if (
			output == null
			or seen_outputs.has(output.command_sequence)
			or not commands.has(output.command_sequence)
		):
			return false
		var command: S2RuntimeCommand = commands[output.command_sequence]
		if output.command_kind != command.kind:
			return false
		var phase: int = command.phase()
		var actor: String = (
			String(command.actor_id) if phase == S2RuntimeCommand.Phase.INTERACTION else ""
		)
		if phase < previous_phase:
			return false
		if phase == previous_phase:
			if phase == S2RuntimeCommand.Phase.INTERACTION:
				if (
					actor < previous_actor
					or (actor == previous_actor and command.sequence < previous_sequence)
				):
					return false
			elif command.sequence < previous_sequence:
				return false
		seen_outputs[output.command_sequence] = true
		previous_phase = phase
		previous_actor = actor
		previous_sequence = command.sequence
	return true


static func _records_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if typeof(left) == TYPE_FLOAT:
		return left == right or (is_nan(left) and is_nan(right))
	if typeof(left) == TYPE_ARRAY:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not _records_equal(left[index], right[index]):
				return false
		return true
	if typeof(left) == TYPE_DICTIONARY:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _records_equal(left[key], right[key]):
				return false
		return true
	return left == right
