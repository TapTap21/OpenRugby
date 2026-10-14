class_name MatchCompositionBuilder
extends RefCounted
## Canonical composition path shared by live runs and replay.


## Builds one ordered match composition and returns every missing capability.
static func build(request: MatchCompositionRequest) -> MatchBuildResult:
	var result: MatchBuildResult = MatchBuildResult.new()
	var report: MatchReadinessReport = result.readiness
	if request == null or request.config == null:
		report.add_blocker(
			MatchReadinessReport.Capability.MATCH_CONFIG, "match configuration is missing"
		)
		return result
	var port: S2RuntimePort = request.s2 if request.s2 != null else S2RuntimePort.new()
	result.s2 = port
	var extensions: ExtensionPoints = _extension_points(request.extension_points)
	var match_hooks_safe: bool = extensions.match_hooks_are_stateless()
	if not match_hooks_safe:
		report.add_blocker(
			MatchReadinessReport.Capability.REPLAY_SAFE_HOOKS,
			"match/physics hooks need stateless_for_match=true and a stable setup_fingerprint"
		)
	var effective_config: MatchConfig = request.config.duplicate(true) as MatchConfig
	if match_hooks_safe and extensions.is_declared(BaseExtensionPoints.MATCH_FLOW_CONFIG):
		var filtered_flow: Variant = extensions.filter(
			BaseExtensionPoints.MATCH_FLOW_CONFIG, effective_config.flow, [effective_config]
		)
		if not filtered_flow is MatchFlowConfig:
			report.add_blocker(
				MatchReadinessReport.Capability.MATCH_CONFIG,
				"match.flow_config returned an invalid flow configuration"
			)
		else:
			@warning_ignore("unsafe_cast")
			effective_config.flow = filtered_flow
	var config_errors: PackedStringArray = effective_config.validate()
	for error_message: String in config_errors:
		report.add_blocker(MatchReadinessReport.Capability.MATCH_CONFIG, error_message)
	if not config_errors.is_empty():
		result.error = ERR_INVALID_PARAMETER
	if Engine.physics_ticks_per_second != MatchSim.TICKS_PER_SECOND:
		report.add_blocker(
			MatchReadinessReport.Capability.MATCH_CONFIG, "engine physics tick rate must be 60 Hz"
		)
	if effective_config.s2_physics != null:
		if effective_config.s2_physics.pitch_condition < 0:
			if port.pitch_condition >= 0:
				effective_config.s2_physics.pitch_condition = port.pitch_condition
			else:
				report.add_blocker(
					MatchReadinessReport.Capability.MATCH_CONFIG,
					"pitch condition must be supplied by match setup"
				)
		if effective_config.s2_physics.stadium_id < 0:
			report.add_blocker(
				MatchReadinessReport.Capability.MATCH_CONFIG,
				"stadium id must be supplied for pitch-surface selection"
			)
	if port.pitch_condition < 0 and effective_config.s2_physics != null:
		port.pitch_condition = effective_config.s2_physics.pitch_condition
	if port.fatigue_option < 0:
		report.add_blocker(
			MatchReadinessReport.Capability.PLAYER_FATIGUE_INPUTS,
			"fatigue option must be injected by the player/match owner"
		)
	if port.player_initializations.is_empty():
		report.add_blocker(
			MatchReadinessReport.Capability.PLAYER_FATIGUE_INPUTS,
			"at least one player with initial motion and fatigue inputs is required"
		)
	for initialization: S2PlayerInitialization in port.player_initializations:
		if initialization == null:
			report.add_blocker(
				MatchReadinessReport.Capability.PLAYER_FATIGUE_INPUTS,
				"player initialization entry is missing"
			)
			continue
		var player_label: String = (
			String(initialization.player.player_id)
			if initialization.player != null
			else "unknown player"
		)
		for error_message: String in initialization.validate():
			report.add_blocker(
				MatchReadinessReport.Capability.PLAYER_FATIGUE_INPUTS,
				"%s: %s" % [player_label, error_message]
			)
	var ball_setup: S2BallInitialization = port.ball_initialization
	if ball_setup == null:
		report.add_blocker(
			MatchReadinessReport.Capability.BALL_INITIALIZATION,
			"owner must initialize ball mode and goal-kick state before start"
		)
	else:
		for error_message: String in ball_setup.validate():
			report.add_blocker(MatchReadinessReport.Capability.BALL_INITIALIZATION, error_message)
	if port.contact_source == null or not port.contact_source.is_available():
		report.add_blocker(
			MatchReadinessReport.Capability.STADIUM_GEOMETRY,
			"deterministic stadium contact geometry provider is unavailable"
		)
	if port.contact_solver == null or not port.contact_solver.is_available():
		report.add_blocker(
			MatchReadinessReport.Capability.CONTACT_SOLVER,
			"contract-complete normal/friction/rolling LCP solver is unavailable"
		)
	if port.contact_source != null and port.contact_solver != null:
		if not _validate_provider_checkpoint(port.contact_source):
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_DEPENDENCIES,
				"contact source must be stateless or implement checkpoint and restore"
			)
		if not _validate_solver_checkpoint(port.contact_solver):
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_DEPENDENCIES,
				"contact solver must be stateless or implement checkpoint and restore"
			)
	var wind_policy: S2WindPolicy = _resolve_wind_policy(
		ball_setup, port, extensions, effective_config, report
	)
	if (
		ball_setup != null
		and ball_setup.goal_kick_state == BallState.GoalKickState.ACTIVE
		and (wind_policy == null or not wind_policy.is_valid())
	):
		report.add_blocker(
			MatchReadinessReport.Capability.WIND_POLICY,
			"active goal kick requires an explicit wind policy or deterministic provider"
		)
	if not report.is_ready():
		return result
	var provided_systems: Array[SimSystem] = []
	if extensions.is_declared(BaseExtensionPoints.MATCH_SIM_SYSTEMS):
		for provided: Variant in extensions.collect(
			BaseExtensionPoints.MATCH_SIM_SYSTEMS, [effective_config]
		):
			if not provided is SimSystem:
				report.add_blocker(
					MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
					"match.sim_systems returned a value that is not a SimSystem"
				)
				return result
			@warning_ignore("unsafe_cast")
			provided_systems.append(provided)
	var systems: Array[SimSystem] = []
	systems.append_array(request.systems)
	systems.append_array(provided_systems)
	var ids: Dictionary[StringName, bool] = {}
	for system: SimSystem in systems:
		if system == null or ids.has(system.system_id()):
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
				"caller and extension systems must be non-null with unique stable ids"
			)
			return result
		ids[system.system_id()] = true
		var checkpoint: SimDependencyCheckpoint = system.transaction_checkpoint()
		if checkpoint == null or not checkpoint.complete or not system.snapshot_is_complete():
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
				"%s needs complete snapshots and transaction restore" % system.system_id()
			)
		elif not system.restore_transaction_checkpoint(checkpoint):
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
				"%s rejected its own transaction checkpoint" % system.system_id()
			)
	if not report.is_ready():
		return result
	var sim: MatchSim = MatchSim.new(effective_config)
	var locomotion: LocomotionSystem = LocomotionSystem.new(effective_config.s2_physics.locomotion)
	locomotion.pitch_condition = port.pitch_condition
	locomotion.fatigue_option = port.fatigue_option
	for initialization: S2PlayerInitialization in port.player_initializations:
		locomotion.players.append(initialization.copy_player())
	var ball: BallPhysicsSystem = BallPhysicsSystem.new(
		effective_config.s2_physics.ball,
		effective_config.s2_physics.surfaces,
		port.contact_source,
		port.contact_solver
	)
	ball.kick_params = effective_config.s2_physics.kicks
	ball.pass_params = effective_config.s2_physics.passes
	ball.pitch_condition = effective_config.s2_physics.pitch_condition
	ball.stadium_id = effective_config.s2_physics.stadium_id
	ball.configure_extensions(extensions, effective_config)
	if wind_policy != null:
		ball.wind_policy_from_extensions = wind_policy
	var interactions: S2InteractionSystem = S2InteractionSystem.new(
		effective_config.s2_physics.tackle, effective_config.s2_physics.catches
	)
	interactions.configure_extensions(extensions)
	port.bind(ball, locomotion, interactions)
	ball.runtime_port = port
	locomotion.runtime_port = port
	interactions.runtime_port = port
	var composed_ids: Dictionary[StringName, bool] = {}
	for system: SimSystem in systems + [locomotion, ball, interactions]:
		if system == null or composed_ids.has(system.system_id()):
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
				"composed systems must have unique stable ids"
			)
			return result
		composed_ids[system.system_id()] = true
	for s2_system: SimSystem in [locomotion, ball, interactions]:
		var system_checkpoint: SimDependencyCheckpoint = s2_system.transaction_checkpoint()
		if (
			system_checkpoint == null
			or not system_checkpoint.complete
			or not s2_system.snapshot_is_complete()
			or not s2_system.restore_transaction_checkpoint(system_checkpoint)
		):
			report.add_blocker(
				MatchReadinessReport.Capability.RESTORABLE_SYSTEMS,
				"%s could not round-trip a transaction checkpoint" % s2_system.system_id()
			)
	if not report.is_ready():
		return result
	if not ball.initialize_from(ball_setup):
		report.add_blocker(
			MatchReadinessReport.Capability.BALL_INITIALIZATION,
			"explicit initial ball state failed validation"
		)
		return result
	for system: SimSystem in systems:
		sim.add_system(system)
	sim.add_system(locomotion)
	sim.add_system(ball)
	sim.add_system(interactions)
	if not sim.is_valid():
		report.add_blocker(
			MatchReadinessReport.Capability.MATCH_CONFIG,
			"MatchSim rejected the effective configuration"
		)
		return result
	var ordered: Array[SimSystem] = []
	ordered.append_array(systems)
	ordered.append(locomotion)
	ordered.append(ball)
	ordered.append(interactions)
	var system_data: Array[Dictionary] = []
	for system: SimSystem in ordered:
		result.system_ids.append(system.system_id())
		system_data.append({"id": system.system_id(), "state": system.snapshot()})
	result.setup_fingerprint = (
		ReplayFingerprint
		. hash(
			{
				"config": effective_config,
				"mod_set_hash": request.mod_set_hash,
				"action_layout_hash": request.action_layout_hash,
				"tick_rate": MatchSim.TICKS_PER_SECOND,
				"composition_version": 1,
				"extension_points": extensions.configuration_snapshot(),
				"runtime_setup": port.setup_snapshot(),
				"resolved_wind": wind_policy.snapshot() if wind_policy != null else {},
				"systems": system_data,
			}
		)
	)
	sim.s2_runtime_port = port
	result.sim = sim
	result.error = OK
	return result


static func _extension_points(points: ExtensionPoints) -> ExtensionPoints:
	var resolved: ExtensionPoints = points if points != null else ExtensionPoints.new()
	BaseExtensionPoints.declare_into(resolved)
	return resolved


static func _validate_provider_checkpoint(source: BallContactSource) -> bool:
	var checkpoint: SimDependencyCheckpoint = source.transaction_checkpoint()
	return (
		checkpoint != null
		and checkpoint.complete
		and source.snapshot_is_complete()
		and source.restore_transaction_checkpoint(checkpoint)
	)


static func _validate_solver_checkpoint(solver: BallContactSolver) -> bool:
	var checkpoint: SimDependencyCheckpoint = solver.transaction_checkpoint()
	return (
		checkpoint != null
		and checkpoint.complete
		and solver.snapshot_is_complete()
		and solver.restore_transaction_checkpoint(checkpoint)
	)


static func _resolve_wind_policy(
	initialization: S2BallInitialization,
	port: S2RuntimePort,
	extensions: ExtensionPoints,
	config: MatchConfig,
	report: MatchReadinessReport
) -> S2WindPolicy:
	if initialization != null and initialization.wind_policy != null:
		if initialization.wind_policy.is_valid():
			return initialization.wind_policy
		report.add_blocker(
			MatchReadinessReport.Capability.WIND_POLICY,
			"ball initializer contains an invalid wind policy"
		)
		return null
	if extensions.is_declared(BaseExtensionPoints.PHYSICS_WIND_PROVIDER):
		if not extensions.match_hooks_are_stateless():
			return null
		for provider: Callable in extensions.hooks(BaseExtensionPoints.PHYSICS_WIND_PROVIDER):
			var provided: Variant = provider.call(config)
			if provided == null:
				continue
			if not provided is S2WindPolicy:
				report.add_blocker(
					MatchReadinessReport.Capability.WIND_POLICY,
					"physics.wind_provider must return an explicit S2WindPolicy"
				)
				return null
			@warning_ignore("unsafe_cast")
			var policy: S2WindPolicy = provided
			if not policy.is_valid():
				report.add_blocker(
					MatchReadinessReport.Capability.WIND_POLICY,
					"physics.wind_provider returned an invalid wind policy"
				)
				return null
			return policy.duplicate_policy()
	if port.wind_policy != null:
		return port.wind_policy if port.wind_policy.is_valid() else null
	return null
