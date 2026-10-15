class_name MatchReplay
extends RefCounted
## Static helpers that re-run a recorded match through the live composition builder.


## Re-runs [param log] against a fresh request and returns a typed outcome.
static func run(request: MatchCompositionRequest, log: InputLog) -> MatchReplayResult:
	var result: MatchReplayResult = MatchReplayResult.new()
	if log == null or log.header == null:
		return _fail(result, MatchReplayResult.ReplayFailure.INVALID_RECORD, ERR_INVALID_DATA)
	if log.header.format_version != ReplayHeader.CURRENT_FORMAT_VERSION:
		return _fail(
			result, MatchReplayResult.ReplayFailure.INCOMPATIBLE_HEADER, ERR_INVALID_PARAMETER
		)
	if request == null or request.config == null:
		var missing_request: MatchBuildResult = MatchCompositionBuilder.build(null)
		result.readiness = missing_request.readiness
		result.error = missing_request.error
		result.readiness_evaluation = MatchReplayResult.ReadinessEvaluation.BUILDER_COMPLETE
		return result
	if (
		log.header.slot_count != request.config.slot_count
		or log.header.axes_per_slot != request.config.axes_per_slot
	):
		return _fail(
			result, MatchReplayResult.ReplayFailure.INCOMPATIBLE_HEADER, ERR_INVALID_PARAMETER
		)
	result.readiness_evaluation = MatchReplayResult.ReadinessEvaluation.PREFLIGHT_ONLY
	if not _replay_dependencies_are_shareable(request, result):
		return result

	var replay_request: MatchCompositionRequest = MatchCompositionRequest.new()
	replay_request.config = request.config.duplicate(true) as MatchConfig
	replay_request.config.seed = log.header.seed
	replay_request.systems = request.systems.duplicate()
	replay_request.mod_set_hash = request.mod_set_hash
	replay_request.action_layout_hash = request.action_layout_hash
	replay_request.extension_points = request.extension_points
	replay_request.s2 = request.s2 if request.s2 != null else S2RuntimePort.new()
	if not replay_request.s2.reset_runtime():
		return _fail(result, MatchReplayResult.ReplayFailure.PORT_RESET_FAILED, ERR_BUSY)

	var build: MatchBuildResult = MatchCompositionBuilder.build(replay_request)
	result.readiness = build.readiness
	result.readiness_evaluation = MatchReplayResult.ReadinessEvaluation.BUILDER_COMPLETE
	if not build.is_success():
		result.error = build.error if build.error != OK else ERR_UNCONFIGURED
		return result
	if not log.header.is_compatible_with(
		replay_request.mod_set_hash, replay_request.action_layout_hash, build.setup_fingerprint
	):
		return _fail(
			result, MatchReplayResult.ReplayFailure.INCOMPATIBLE_HEADER, ERR_INVALID_PARAMETER
		)

	var frame: InputFrame = InputFrame.new(log.header.slot_count, log.header.axes_per_slot)
	var expected_sequence: int = 0
	for index: int in log.frame_count():
		if build.sim.is_finished():
			return _fail(result, MatchReplayResult.ReplayFailure.INVALID_LINKAGE, ERR_INVALID_DATA)
		var commands: Array[Dictionary] = log.frame_commands(index)
		var outputs: Array[Dictionary] = log.frame_outputs(index)
		if not _validate_frame_records(commands, outputs, expected_sequence):
			return _fail(result, MatchReplayResult.ReplayFailure.INVALID_LINKAGE, ERR_INVALID_DATA)
		expected_sequence += commands.size()
		if not log.read_frame(index, frame):
			return _fail(result, MatchReplayResult.ReplayFailure.INVALID_RECORD, ERR_INVALID_DATA)
		if not replay_request.s2.enqueue_replay_commands(commands):
			return _fail(result, MatchReplayResult.ReplayFailure.INVALID_LINKAGE, ERR_INVALID_DATA)
		build.sim.tick(frame)
		if not build.sim.last_tick_succeeded:
			if build.sim.is_stopped():
				result.fatal_reason = build.sim.stop_reason()
				return _fail(result, MatchReplayResult.ReplayFailure.FATAL_ROLLBACK, FAILED)
			return _fail(result, MatchReplayResult.ReplayFailure.TICK_FAILED, FAILED)
		if not _records_equal(replay_request.s2.results_since(0), outputs):
			return _fail(result, MatchReplayResult.ReplayFailure.OUTPUT_MISMATCH, ERR_INVALID_DATA)
	result.sim = build.sim
	result.error = OK
	result.replay_failure = MatchReplayResult.ReplayFailure.NONE
	return result


static func _fail(
	result: MatchReplayResult, failure: MatchReplayResult.ReplayFailure, error: Error
) -> MatchReplayResult:
	result.sim = null
	result.error = error if error != OK else FAILED
	result.replay_failure = failure
	return result


static func _replay_dependencies_are_shareable(
	request: MatchCompositionRequest, result: MatchReplayResult
) -> bool:
	if request.s2 != null:
		if (
			request.s2.contact_source != null
			and not request.s2.contact_source.is_transaction_stateless()
		):
			result.readiness.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_DEPENDENCIES,
				"replay requires a fresh contact-source factory for mutable providers"
			)
		if (
			request.s2.contact_solver != null
			and not request.s2.contact_solver.is_transaction_stateless()
		):
			result.readiness.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_DEPENDENCIES,
				"replay requires a fresh contact-solver factory for mutable providers"
			)
	for system: SimSystem in request.systems:
		if system != null and not system.is_transaction_stateless():
			result.readiness.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
				"replay requires a fresh participant factory for mutable systems"
			)
	if (
		request.extension_points != null
		and request.extension_points.is_declared(BaseExtensionPoints.MATCH_SIM_SYSTEMS)
		and not request.extension_points.hooks(BaseExtensionPoints.MATCH_SIM_SYSTEMS).is_empty()
	):
		result.readiness.add_blocker(
			MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
			"replay requires a fresh participant factory for extension-provided systems"
		)
	if not result.readiness.is_ready():
		result.error = ERR_UNAVAILABLE
		return false
	return true


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
	return seen_outputs.size() == commands.size()


static func _records_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is float and right is float:
		var left_float: float = left
		var right_float: float = right
		return left_float == right_float or (is_nan(left_float) and is_nan(right_float))
	if left is Array and right is Array:
		var left_array: Array = left
		var right_array: Array = right
		if left_array.size() != right_array.size():
			return false
		for index: int in left_array.size():
			if not _records_equal(left_array[index], right_array[index]):
				return false
		return true
	if left is Dictionary and right is Dictionary:
		var left_dictionary: Dictionary = left
		var right_dictionary: Dictionary = right
		if left_dictionary.size() != right_dictionary.size():
			return false
		for key: Variant in left_dictionary:
			if (
				not right_dictionary.has(key)
				or not _records_equal(left_dictionary[key], right_dictionary[key])
			):
				return false
		return true
	return left == right
