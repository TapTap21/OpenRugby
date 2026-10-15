# gdlint: disable=max-public-methods,max-returns
class_name MatchSim
extends RefCounted
## Deterministic fixed-step match simulation with checked, abortable ticks.

signal state_changed(from_state: StringName, to_state: StringName)
signal period_started(period: int)
signal period_ended(period: int)
signal finished

const TICKS_PER_SECOND: int = 60
const FATAL_ROLLBACK_REASON: StringName = &"rollback_failed"

var config: MatchConfig
var rng: SimRng
var clock: MatchClock
var flow: MatchStateMachine
var tick_count: int = 0

var _valid: bool = false
var _finished: bool = false
var _stopped: bool = false
var _stop_reason: StringName = &""
var _runner_owned: bool = false
var _systems: Array[SimSystem] = []
var _setup_results: Array[SetupResult] = []
var _participant_ids: Array[String] = []
var _provider_refs: Array[RefCounted] = []
var _pending_triggers: Array[StringName] = []
var _current: InputFrame
var _previous: InputFrame
var _active_prepared_tick: PreparedTick
var _publishable_signal_batch: SignalBatch
var _live_append_token: PreparedAppendToken
var _append_registration: Dictionary = {}
var _candidate_attempt_id: int = 0


func _init(p_config: MatchConfig) -> void:
	config = p_config
	if p_config == null:
		push_error("MatchSim: config is null")
		_current = InputFrame.new(1, 2)
		_previous = InputFrame.new(1, 2)
		return
	var errors: PackedStringArray = p_config.validate()
	if not errors.is_empty():
		push_error("MatchSim: invalid config: " + "; ".join(errors))
		_current = InputFrame.new(1, 2)
		_previous = InputFrame.new(1, 2)
		return
	rng = SimRng.new(p_config.seed)
	clock = MatchClock.new(
		p_config.rules.period_count,
		p_config.period_real_seconds * TICKS_PER_SECOND,
		p_config.rules.period_game_seconds
	)
	flow = MatchStateMachine.new(p_config.flow)
	_current = InputFrame.new(p_config.slot_count, p_config.axes_per_slot)
	_previous = InputFrame.new(p_config.slot_count, p_config.axes_per_slot)
	_valid = true


## True when the config validated and the sim can run.
func is_valid() -> bool:
	return _valid


## Registers and sets up a participant before tick one.
func add_system(system: SimSystem) -> Error:
	if not _valid or system == null or tick_count > 0 or _active_prepared_tick != null:
		return ERR_INVALID_PARAMETER
	if _systems.has(system):
		return ERR_ALREADY_EXISTS
	var participant_hint: String = system.participant_id_hint()
	if not participant_hint.is_empty() and _participant_ids.has(participant_hint):
		return ERR_ALREADY_EXISTS
	var result: SetupResult = system.setup(self)
	if result == null or not result.is_well_formed():
		return ERR_INVALID_DATA
	if not result.ok:
		return result.error
	var claim: ParticipantClaim = result.participant_claim
	if _participant_ids.has(claim.stable_participant_id):
		return ERR_ALREADY_EXISTS
	var new_providers: Array[RefCounted] = []
	for provider_claim: ProviderClaim in result.owned_provider_claims:
		if (
			_provider_refs.has(provider_claim.provider)
			or new_providers.has(provider_claim.provider)
		):
			return ERR_ALREADY_EXISTS
		if (
			provider_claim.transaction_capability == TransactionCapability.COMPLETE_TRANSACTIONAL
			and result.capability != TransactionCapability.COMPLETE_TRANSACTIONAL
		):
			return ERR_INVALID_DATA
		new_providers.append(provider_claim.provider)
	if result.capability == TransactionCapability.COMPLETE_TRANSACTIONAL:
		if not _has_usable_restore(system):
			return ERR_UNCONFIGURED
		var checkpoint_result: CheckpointResult = system.checkpoint()
		if not _valid_checkpoint_result(checkpoint_result, result.capability):
			return _checkpoint_error(checkpoint_result)
	elif result.capability != TransactionCapability.EXPLICITLY_STATELESS:
		return ERR_UNCONFIGURED
	else:
		var stateless_checkpoint: CheckpointResult = system.checkpoint()
		if not _valid_checkpoint_result(stateless_checkpoint, result.capability):
			return _checkpoint_error(stateless_checkpoint)
		if not OwnerCapture._is_empty_checkpoint_value(stateless_checkpoint.value):
			return ERR_INVALID_DATA
	_systems.append(system)
	_setup_results.append(result)
	_participant_ids.append(claim.stable_participant_id)
	_provider_refs.append_array(new_providers)
	return OK


## Runs a checked tick and leaves successful state abortable until finalization.
func tick_checked(frame: InputFrame, commands: DetachedCommandBundle = null) -> TickResult:
	if not _valid:
		return _no_op(TickResult.Status.NO_OP_INVALID, ERR_INVALID_PARAMETER)
	if _stopped:
		return _no_op(TickResult.Status.NO_OP_STOPPED, OK)
	if _finished:
		return _no_op(TickResult.Status.NO_OP_FINISHED, OK)
	if _active_prepared_tick != null:
		return _failure(ERR_BUSY)
	_candidate_attempt_id += 1
	_publishable_signal_batch = null
	var candidate: InputFrame = _normalize_frame(frame)
	var command_copy: DetachedCommandBundle = (
		commands if commands != null else DetachedCommandBundleBuilder.new().seal()
	)
	if command_copy == null:
		return _failure(ERR_INVALID_DATA)
	if not command_copy.is_valid():
		return _failure(ERR_INVALID_DATA)
	var delta: Vector2i = _clock_delta()
	var context: SimTickContext = _make_context(
		candidate, command_copy, delta, _candidate_attempt_id
	)
	var checkpoint_result: Dictionary = _capture_checkpoint()
	if not checkpoint_result.ok:
		return _failure(checkpoint_result.error)
	var captures: Array[OwnerCapture] = []
	for system: SimSystem in _systems:
		if system is SimTickOwner:
			var capture_result: OwnerCaptureResult = (system as SimTickOwner).capture_tick(context)
			if not _valid_capture_result(capture_result):
				return _rollback_failure(
					checkpoint_result,
					(
						capture_result.error
						if capture_result != null and capture_result.error != OK
						else ERR_INVALID_DATA
					)
				)
			captures.append(capture_result.capture)
		else:
			captures.append(null)
	_previous.copy_from(_current)
	_current.copy_from(candidate)
	tick_count += 1
	var outputs: Array[RefCounted] = []
	for system: SimSystem in _systems:
		var tick_result: SystemTickResult = system.tick_checked(self, context)
		if not _valid_tick_result(tick_result):
			return _rollback_failure(
				checkpoint_result, tick_result.error if tick_result != null else ERR_INVALID_DATA
			)
		outputs.append_array(tick_result.outputs)
	var pre_clock_period: int = context.pre_clock_period
	var pre_clock_elapsed: int = context.pre_clock_elapsed_ticks
	var pre_flow_state: StringName = context.pre_flow_state
	var pre_flow_ticks: int = context.pre_flow_ticks_in_state
	var prior_state: MatchStateDef = flow.current_def()
	if prior_state == null:
		return _rollback_failure(checkpoint_result, ERR_INVALID_DATA)
	if prior_state.clock_runs:
		clock.advance()
	flow.ticks_in_state += 1
	var transition_result: TransitionEvaluationResult = flow.evaluate_transition_checked(
		self, _pending_triggers
	)
	if not transition_result.ok:
		return _rollback_failure(checkpoint_result, transition_result.error)
	var staged: Array[StagedSignal] = []
	if transition_result.transition != null:
		_stage_transition(transition_result.transition, staged)
	_pending_triggers.clear()
	var transition: MatchTransitionDef = transition_result.transition
	var outcome: SimTickOutcome = SimTickOutcome.new(
		tick_count,
		pre_clock_period,
		pre_clock_elapsed,
		clock.period,
		clock.elapsed_ticks,
		pre_flow_state,
		pre_flow_ticks,
		flow.current,
		flow.ticks_in_state,
		transition.to if transition != null else &"",
		transition.trigger if transition != null else &"",
		transition.period_effect if transition != null else MatchTransitionDef.PeriodEffect.NONE,
		delta.x,
		delta.y
	)
	for index: int in range(_systems.size()):
		if not _systems[index] is SimTickOwner:
			continue
		var owner: SimTickOwner = _systems[index] as SimTickOwner
		var commit_result: OwnerCommitResult = owner.commit_tick(context, captures[index], outcome)
		if not _valid_commit_result(commit_result):
			return _rollback_failure(
				checkpoint_result,
				commit_result.error if commit_result != null else ERR_INVALID_DATA
			)
	var batch: SignalBatch = SignalBatch.new(staged)
	var prepared: PreparedTick = PreparedTick.new(
		self,
		checkpoint_result,
		captures,
		candidate,
		command_copy,
		outcome,
		outputs,
		batch,
		_candidate_attempt_id
	)
	_active_prepared_tick = prepared
	return TickResult.new(TickResult.Status.PREPARED, OK, outcome, outputs, batch, prepared)


## Standalone compatibility wrapper: finalize then publish locally.
func tick(frame: InputFrame) -> TickResult:
	var result: TickResult = tick_checked(frame)
	if result.status != TickResult.Status.PREPARED:
		return result
	var finalize_error: Error = finalize_standalone_tick(result.prepared_tick)
	if finalize_error != OK:
		if _is_active_handle(result.prepared_tick):
			abort_prepared_tick(result.prepared_tick)
		return _failure(finalize_error)
	publish_staged_signals(result.signal_batch)
	return TickResult.new(
		TickResult.Status.COMMITTED, OK, result.outcome, result.outputs, result.signal_batch
	)


## Finalizes a runner-authorized prepared tick. The token is validated by the runner boundary.
func finalize_prepared_tick(
	prepared_tick: PreparedTick, append_token: PreparedAppendToken
) -> Error:
	if (
		_runner_owned
		and _is_active_handle(prepared_tick)
		and append_token != null
		and not _append_registration.is_empty()
		and _append_registration.prepared_tick == prepared_tick
		and _append_registration.token == append_token
		and _append_registration.log._finalize_registered_append(append_token, self, prepared_tick)
	):
		_live_append_token = append_token
		_append_registration.clear()
		_consume_prepared_tick(prepared_tick)
		return OK
	return ERR_INVALID_PARAMETER


## Finalizes exactly this sim's active standalone tick once.
func finalize_standalone_tick(prepared_tick: PreparedTick) -> Error:
	if _runner_owned or not _append_registration.is_empty() or not _is_active_handle(prepared_tick):
		return ERR_INVALID_PARAMETER
	_consume_prepared_tick(prepared_tick)
	return OK


## Finalizes a replay tick after its codec has validated the exact source row.
func finalize_replay_tick(
	_prepared_tick: PreparedTick, _replay_validation_token: ReplayValidationToken
) -> Error:
	# Replay receipt minting is owned by the S2 codec contract, not present in this checkout.
	return ERR_UNCONFIGURED


## Restores and consumes the exact active prepared tick.
func abort_prepared_tick(prepared_tick: PreparedTick) -> Error:
	if not _is_active_handle(prepared_tick):
		return ERR_INVALID_PARAMETER
	var checkpoint: Dictionary = prepared_tick._checkpoint
	if not _append_registration.is_empty():
		_append_registration.log._invalidate_for_tick(prepared_tick)
		_append_registration.clear()
	if _live_append_token != null:
		_live_append_token = null
	_active_prepared_tick = null
	prepared_tick._active = false
	if _restore_checkpoint(checkpoint):
		return OK
	_latch_fatal_stop()
	return ERR_FAILED


## Publishes a finalized batch through the existing local MatchSim signals.
func publish_staged_signals(batch: SignalBatch) -> void:
	if batch == null or batch != _publishable_signal_batch:
		return
	_publishable_signal_batch = null
	for staged_signal: StagedSignal in batch.signals:
		match staged_signal.kind:
			StagedSignal.Kind.STATE_CHANGED:
				state_changed.emit(staged_signal.from_state, staged_signal.to_state)
			StagedSignal.Kind.PERIOD_STARTED:
				period_started.emit(staged_signal.period)
			StagedSignal.Kind.PERIOD_ENDED:
				period_ended.emit(staged_signal.period)
			StagedSignal.Kind.FINISHED:
				finished.emit()


## Queues a trigger for evaluation on the current candidate tick.
func raise_trigger(trigger: StringName) -> void:
	_pending_triggers.append(trigger)


## Claims this sim for coordinated runner finalization.
func claim_runner_ownership() -> Error:
	if _runner_owned or tick_count > 0 or _active_prepared_tick != null:
		return ERR_ALREADY_IN_USE
	_runner_owned = true
	return OK


func _register_append_registration(
	log: InputLog, token: PreparedAppendToken, prepared_tick: PreparedTick
) -> bool:
	if (
		log == null
		or token == null
		or not _is_active_handle(prepared_tick)
		or not _append_registration.is_empty()
		or not log._seal_registered_append(token)
	):
		return false
	_append_registration["log"] = log
	_append_registration["token"] = token
	_append_registration["prepared_tick"] = prepared_tick
	return true


func _consume_append_registration(log: InputLog, token: PreparedAppendToken) -> void:
	if (
		not _append_registration.is_empty()
		and _append_registration.log == log
		and _append_registration.token == token
	):
		_append_registration.clear()


func current_state() -> StringName:
	return flow.current if flow != null else &""


func is_finished() -> bool:
	return _finished


func is_stopped() -> bool:
	return _stopped


func stop_reason() -> StringName:
	return _stop_reason


func is_held(slot: int, bit: int) -> bool:
	return _current.is_held(slot, bit)


func just_pressed(slot: int, bit: int) -> bool:
	return _current.is_held(slot, bit) and not _previous.is_held(slot, bit)


func just_released(slot: int, bit: int) -> bool:
	return _previous.is_held(slot, bit) and not _current.is_held(slot, bit)


func get_axis(slot: int, axis: int) -> int:
	return _current.get_axis(slot, axis)


## Returns the deterministic public simulation state in stable key order.
func snapshot() -> Dictionary:
	if not _valid:
		return {"tick": tick_count, "valid": false}
	var systems_data: Array = []
	for index: int in range(_systems.size()):
		var claim: ParticipantClaim = _setup_results[index].participant_claim
		var detached_snapshot: Variant = OwnerCapture._copy_contract_value(
			_systems[index].snapshot()
		)
		if typeof(detached_snapshot) != TYPE_DICTIONARY:
			detached_snapshot = {}
		systems_data.append(
			{
				"id": _systems[index].system_id(),
				"participant_id": claim.stable_participant_id,
				"participant_version": claim.participant_version,
				"configuration_fingerprint": claim.configuration_fingerprint,
				"initial_state_fingerprint": claim.deterministic_initial_state_fingerprint,
				"data": detached_snapshot
			}
		)
	return {
		"tick": tick_count,
		"rng_seed": rng.seed,
		"rng_state": rng.get_state(),
		"state": flow.current,
		"ticks_in_state": flow.ticks_in_state,
		"period": clock.period,
		"elapsed_ticks": clock.elapsed_ticks,
		"finished": _finished,
		"pending_triggers": _pending_triggers.duplicate(),
		"input_buttons": _current.buttons.duplicate(),
		"input_axes": _current.axes.duplicate(),
		"previous_input_buttons": _previous.buttons.duplicate(),
		"previous_input_axes": _previous.axes.duplicate(),
		"systems": systems_data
	}


## Lowercase hex SHA-256 of the serialised snapshot.
func state_hash() -> String:
	var ctx: HashingContext = HashingContext.new()
	var err: Error = ctx.start(HashingContext.HASH_SHA256)
	assert(err == OK)
	err = ctx.update(var_to_bytes(snapshot()))
	assert(err == OK)
	return ctx.finish().hex_encode()


func _normalize_frame(frame: InputFrame) -> InputFrame:
	var candidate: InputFrame = InputFrame.new(config.slot_count, config.axes_per_slot)
	if frame == null:
		return candidate
	if frame.slot_count == candidate.slot_count and frame.axes_per_slot == candidate.axes_per_slot:
		candidate.copy_from(frame)
	else:
		candidate.tick = frame.tick
	return candidate


func _make_context(
	frame: InputFrame, commands: DetachedCommandBundle, delta: Vector2i, attempt_id: int
) -> SimTickContext:
	var pressed: PackedInt64Array = PackedInt64Array()
	var released: PackedInt64Array = PackedInt64Array()
	pressed.resize(config.slot_count)
	released.resize(config.slot_count)
	for slot: int in range(config.slot_count):
		var prior: int = _previous.buttons[slot] if tick_count > 0 else 0
		pressed[slot] = frame.buttons[slot] & ~prior
		released[slot] = prior & ~frame.buttons[slot]
	return SimTickContext.new(
		tick_count + 1,
		frame,
		_previous if tick_count > 0 else null,
		pressed,
		released,
		commands,
		clock.period,
		clock.elapsed_ticks,
		clock.period_count,
		clock.period_ticks,
		clock.game_seconds_per_period,
		flow.current,
		flow.ticks_in_state,
		_pending_triggers,
		delta.x,
		delta.y,
		attempt_id
	)


func _clock_delta() -> Vector2i:
	if not flow.current_def().clock_runs:
		return Vector2i(0, 1)
	var numerator: int = clock.game_seconds_per_period
	var denominator: int = clock.period_ticks
	var divisor: int = _gcd(numerator, denominator)
	return Vector2i(numerator / divisor, denominator / divisor)


func _gcd(left: int, right: int) -> int:
	var a: int = abs(left)
	var b: int = abs(right)
	while b != 0:
		var remainder: int = a % b
		a = b
		b = remainder
	return maxi(a, 1)


func _capture_checkpoint() -> Dictionary:
	var system_checkpoints: Array = []
	for index: int in range(_systems.size()):
		var capability: int = _setup_results[index].capability
		if capability == TransactionCapability.EXPLICITLY_STATELESS:
			system_checkpoints.append(null)
			continue
		var result: CheckpointResult = _systems[index].checkpoint()
		if not _valid_checkpoint_result(result, capability):
			return {"ok": false, "error": _checkpoint_error(result)}
		system_checkpoints.append(result.value)
	return {
		"ok": true,
		"tick": tick_count,
		"rng_state": rng.get_state(),
		"period": clock.period,
		"elapsed_ticks": clock.elapsed_ticks,
		"flow_state": flow.current,
		"flow_ticks": flow.ticks_in_state,
		"finished": _finished,
		"pending_triggers": _pending_triggers.duplicate(),
		"current": SimTickContext._copy_frame(_current),
		"previous": SimTickContext._copy_frame(_previous),
		"systems": system_checkpoints
	}


func _restore_checkpoint(checkpoint: Dictionary) -> bool:
	var restored: bool = true
	var values: Array = checkpoint.systems
	for index: int in range(_systems.size() - 1, -1, -1):
		if _setup_results[index].capability == TransactionCapability.EXPLICITLY_STATELESS:
			continue
		if _systems[index].restore(values[index]) != OK:
			restored = false
	tick_count = checkpoint.tick
	rng.set_state(checkpoint.rng_state)
	clock.period = checkpoint.period
	clock.elapsed_ticks = checkpoint.elapsed_ticks
	flow.current = checkpoint.flow_state
	flow.ticks_in_state = checkpoint.flow_ticks
	_finished = checkpoint.finished
	_pending_triggers = checkpoint.pending_triggers.duplicate()
	_current.copy_from(checkpoint.current)
	_previous.copy_from(checkpoint.previous)
	return restored


func _rollback_failure(checkpoint: Dictionary, phase_error: Error) -> TickResult:
	if _restore_checkpoint(checkpoint):
		return _failure(phase_error if phase_error != OK else ERR_FAILED)
	_latch_fatal_stop()
	return _failure(phase_error if phase_error != OK else ERR_FAILED, true)


func _stage_transition(transition: MatchTransitionDef, staged: Array[StagedSignal]) -> void:
	var from_state: StringName = flow.current
	flow.current = transition.to
	flow.ticks_in_state = 0
	staged.append(StagedSignal.new(StagedSignal.Kind.STATE_CHANGED, from_state, transition.to))
	if transition.period_effect == MatchTransitionDef.PeriodEffect.START:
		staged.append(StagedSignal.new(StagedSignal.Kind.PERIOD_STARTED, &"", &"", clock.period))
	elif transition.period_effect == MatchTransitionDef.PeriodEffect.ADVANCE:
		clock.start_next_period()
		staged.append(StagedSignal.new(StagedSignal.Kind.PERIOD_STARTED, &"", &"", clock.period))
	var state_def: MatchStateDef = flow.current_def()
	if state_def.ends_period:
		staged.append(StagedSignal.new(StagedSignal.Kind.PERIOD_ENDED, &"", &"", clock.period))
	if state_def.terminal:
		_finished = true
		staged.append(StagedSignal.new(StagedSignal.Kind.FINISHED))


func _consume_prepared_tick(prepared_tick: PreparedTick) -> void:
	_publishable_signal_batch = prepared_tick.signal_batch
	prepared_tick._active = false
	_active_prepared_tick = null


func _is_active_handle(prepared_tick: PreparedTick) -> bool:
	return (
		prepared_tick != null
		and prepared_tick == _active_prepared_tick
		and prepared_tick._active
		and prepared_tick._sim == self
	)


func _latch_fatal_stop() -> void:
	_stopped = true
	if _stop_reason == &"":
		_stop_reason = FATAL_ROLLBACK_REASON


func _no_op(status: TickResult.Status, error: Error) -> TickResult:
	return TickResult.new(status, error)


func _failure(error: Error, fatal: bool = false) -> TickResult:
	return TickResult.new(
		TickResult.Status.FATAL_ROLLBACK if fatal else TickResult.Status.FAILED_RETRYABLE,
		error if error != OK else ERR_FAILED
	)


func _valid_tick_result(result: SystemTickResult) -> bool:
	return (
		result != null
		and ((result.ok and result.error == OK) or (not result.ok and result.error != OK))
		and result.ok
	)


func _valid_capture_result(result: OwnerCaptureResult) -> bool:
	return (
		result != null
		and result.ok
		and result.error == OK
		and result.capture != null
		and result.capture._has_detached_payload
	)


func _valid_commit_result(result: OwnerCommitResult) -> bool:
	return result != null and result.ok and result.error == OK


func _valid_checkpoint_result(result: CheckpointResult, capability: int) -> bool:
	if result == null or not result.ok or result.error != OK:
		return false
	if capability == TransactionCapability.EXPLICITLY_STATELESS:
		return result._has_detached_value
	return result._has_detached_value and not OwnerCapture._is_empty_checkpoint_value(result.value)


func _checkpoint_error(result: CheckpointResult) -> Error:
	return result.error if result != null and result.error != OK else ERR_INVALID_DATA


func _has_usable_restore(system: SimSystem) -> bool:
	var script: Script = system.get_script()
	var base_script: Script = SimSystem.new().get_script()
	while script != null and script != base_script:
		for method: Dictionary in script.get_script_method_list():
			if method.get("name", "") == "restore":
				return true
		script = script.get_base_script()
	return false
