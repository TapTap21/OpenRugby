# S1 public test API

Status: normative clarification to [S1-core](S1-core.md) for test authors. This defines the
public generic S1 seam; it does not change tick order, simulation behavior, or transaction
boundaries. `docs/specs/S2-*` must declare the typed port and codec seam before tests construct or
inspect those S2 types.

## Public type locations

The following `class_name` scripts are public test API. Paths are relative to the repository root.
Each record's positional `_init` parameter order is the field order below unless an entry states a
different constructor. Tests may construct records with `.new(...)` or inspect the named read-only
properties; they must not infer a different constructor from implementation code.

| Type | Script path | Public fields, in constructor order |
|---|---|---|
| `TransactionCapability` | `game/match/transaction_capability.gd` | enum `COMPLETE_TRANSACTIONAL`, `EXPLICITLY_STATELESS`, `UNSUPPORTED` |
| `SetupResult` | `game/match/setup_result.gd` | `ok: bool`, `error: Error`, `capability: TransactionCapability`, `participant_claim: ParticipantClaim | null`, `owned_provider_claims: Array[ProviderClaim]` |
| `ParticipantClaim` | `game/match/participant_claim.gd` | `stable_participant_id: String`, `participant_version: String`, `configuration_fingerprint: String`, `deterministic_initial_state_fingerprint: String` |
| `ProviderClaim` | `game/match/provider_claim.gd` | `provider: RefCounted`, `stable_provider_id: String`, `provider_version: String`, `transaction_capability: TransactionCapability`, `configuration_fingerprint: String`, `deterministic_initial_state_fingerprint: String` |
| `ReplayInstanceResult` | `game/match/replay_instance_result.gd` | `ok: bool`, `instance: SimSystem | null`, `error: Error`, `owned_provider_claims: Array[ProviderClaim]` |
| `SystemTickResult` | `game/match/system_tick_result.gd` | `ok: bool`, `error: Error`, `outputs: Array[RefCounted]` |
| `OwnerCapture` | `game/match/owner_capture.gd` | `payload: Variant` |
| `OwnerCaptureResult` | `game/match/owner_capture_result.gd` | `ok: bool`, `capture: OwnerCapture | null`, `error: Error` |
| `OwnerCommitResult` | `game/match/owner_commit_result.gd` | `ok: bool`, `error: Error` |
| `CheckpointResult` | `game/match/checkpoint_result.gd` | `ok: bool`, `value: Variant | null`, `error: Error` |
| `SimDependencyCheckpoint` | `game/match/sim_dependency_checkpoint.gd` | `stable_provider_id: String`, `provider_version: String`, `state: Variant | null` |
| `ReplaySourceRow` | `game/match/replay_source_row.gd` | `frame: InputFrame | null`, `command_records: Array[Dictionary]`, `output_records: Array[Dictionary]`; public `_init()` is no-argument and creates an inert, unregistered row |
| `SimTickContext` | `game/match/sim_tick_context.gd` | See context accessors below; constructed by the sim for an owner callback, not directly by callers. |
| `SimTickOutcome` | `game/match/sim_tick_outcome.gd` | See outcome accessors below; constructed by the sim after successful staging, not directly by callers. |
| `TickResult` | `game/match/tick_result.gd` | `status: TickResult.Status`, `error: Error`, `outcome: SimTickOutcome | null`, `outputs: Array[RefCounted]`, `signal_batch: SignalBatch`, `prepared_tick: PreparedTick | null` |
| `MatchReadinessBlocker` | `game/match/match_readiness_blocker.gd` | `code: MatchReadinessBlocker.Code`, `subject: StringName`, `message: String` |
| `MatchReadinessReport` | `game/match/match_readiness_report.gd` | `blockers: Array[MatchReadinessBlocker]`; also `is_ready() -> bool` |
| `MatchBuildResult` | `game/match/match_build_result.gd` | `ok: bool`, `sim: MatchSim | null`, `codec: S2ReplayCodec | null`, `setup_fingerprint: String`, `readiness: MatchReadinessReport`, `error: Error` |
| `MatchReplayResult` | `game/match/match_replay_result.gd` | `sim: MatchSim | null`, `error: Error`, `replay_failure: MatchReplayResult.ReplayFailure`, `fatal_reason: StringName`, `readiness_evaluation: MatchReplayResult.ReadinessEvaluation`, `readiness: MatchReadinessReport` |
| `PreparedAppendToken` | `game/match/prepared_append_token.gd` | Opaque token; public no-argument constructor, no inspectable fields |
| `ReplayValidationToken` | `game/match/replay_validation_token.gd` | Opaque token; public no-argument constructor, no inspectable fields |

The paths for `TransactionCapability`, result/claim/checkpoint records, readiness/build records,
opaque token types and `TickResult` are added here to make the already named public concepts
locatable. `PreparedTick`, `SignalBatch`, `InputFrame`,
`DetachedCommandBundle`, `MatchClock`, and match-flow definitions retain the APIs in S1-core.

## Construction and value semantics

Fake participants construct the listed result/claim/capture/checkpoint records. `TickResult` is
constructed by `MatchSim` and is inspected by tests; tests do not fabricate one. MatchSim stores
its detached output array, and the returned `TickResult.outputs` getter is detached. `SimTickContext`
and `SimTickOutcome` are constructed by the sim and are not directly caller-constructible.
For `Array[ProviderClaim]`, the constructor takes a typed array in the stated position and stores a
detached array copy. `SetupResult` success is `(true, OK, declared capability, non-null valid
ParticipantClaim, claims)`; failure is `(false, non-OK, UNSUPPORTED, null, [])`. `ReplayInstanceResult`
success is `(true, fresh instance, OK, claims)` and failure is `(false, null, non-OK, [])`.
`SystemTickResult` success/failure is `(true, OK, outputs)` / `(false, non-OK, [])`; success may
carry an empty or non-empty `Array[RefCounted]` of existing feature-owned typed records. S1 does
not define a universal output record schema. Its constructor and returned `outputs` getter detach
the array. `TickResult.outputs` is also `Array[RefCounted]`; MatchSim stores a detached array and
the returned getter is detached. Published output records and nested mutable payloads are detached and sealed, so
these arrays may share immutable record references. Successful systems' outputs concatenate in
registration order, preserving producer-local order; failures, aborts, failed ticks, and no-op
results expose empty outputs. `OwnerCaptureResult` is
`(true, non-null capture, OK)` / `(false, null, non-OK)`. `OwnerCommitResult` is `(true, OK)` /
`(false, non-OK)`. `CheckpointResult` is `(true, non-empty immutable value, OK)` for a transactional
participant and `(false, null, non-OK)` for failure; only an explicitly stateless participant may
return the immutable empty value on success. `SimDependencyCheckpoint` has no failure shape;
provider checkpoint failure is the containing participant's `CheckpointResult` failure. `Error`
values mean Godot's global `Error` enum, with exactly `OK` for success and any non-`OK` value for
failure; where S1 names a specific error, that named value is required.

Every record is an immutable value snapshot after construction. Reads of arrays, packed arrays,
dictionaries, and nested mutable containers return detached deep copies; mutation of a returned
container or a constructor argument cannot change the record. `Variant` payloads/checkpoint values
must be immutable value data (scalars, strings, immutable records, or recursively copied
containers). Opaque checkpoint contents are only round-tripped to `restore`; tests assert success,
failure and restoration behavior through observable state and do not inspect private checkpoint
payload shape. `ProviderClaim.provider` is the one intentional reference exception: it retains the
exact `RefCounted` object for setup ownership and identity comparisons, but it is not serialized,
copied, hashed as an address, or exposed through another mutable record field.

## Generic tick context and outcome

`SimTickContext` exposes these read-only properties, with the existing named types:

| Property | Type and meaning |
|---|---|
| `candidate_tick` | `int`, 1-based tick being evaluated |
| `candidate_frame` | detached `InputFrame` copy |
| `previous_frame` | detached previous `InputFrame` copy; null before the first frame |
| `pressed_buttons` | detached `PackedInt64Array`, per slot bitmask of newly held bits relative to `previous_frame` |
| `released_buttons` | detached `PackedInt64Array`, per slot bitmask of newly released bits relative to `previous_frame` |
| `commands` | detached immutable `DetachedCommandBundle` of existing typed records, empty when commandless |
| `pre_clock_period` | `int` |
| `pre_clock_elapsed_ticks` | `int` |
| `pre_clock_period_count` | `int` |
| `pre_clock_period_ticks` | `int` |
| `pre_clock_game_seconds_per_period` | `int` |
| `pre_flow_state` | `StringName` |
| `pre_flow_ticks_in_state` | `int` |
| `pre_pending_triggers` | detached `Array[StringName]` captured before transition evaluation |
| `clock_delta_numerator` | `int`, non-negative numerator of actual game-clock seconds advanced this tick |
| `clock_delta_denominator` | `int`, positive denominator |

The clock delta is reduced to lowest terms. For an advancing clock it is
`game_seconds_per_period / period_ticks` reduced to lowest terms, using the pre-tick clock values.
This is the exact rational simulated game-time increment for the single elapsed tick; it is neither
wall time nor the integer-rounded display delta. S1 has no public pause API, so C-51 asserts the
advancing delta only; world-pause behavior and a paused-clock case remain unresolved. For each slot `s`,
`pressed_buttons[s] = candidate_frame.buttons[s] & ~previous_frame.buttons[s]` and
`released_buttons[s] = previous_frame.buttons[s] & ~candidate_frame.buttons[s]`; before the first
frame the previous mask is zero.
`previous_frame`, edge arrays and commands are detached; there is no mutable sim/config/system/
provider reference.

`SimTickOutcome` exposes read-only properties `candidate_tick: int`, `pre_clock_period: int`,
`pre_clock_elapsed_ticks: int`, `post_clock_period: int`, `post_clock_elapsed_ticks: int`,
`pre_flow_state: StringName`, `pre_flow_ticks_in_state: int`, `post_flow_state: StringName`,
`post_flow_ticks_in_state: int`, `selected_transition_to: StringName` (empty when none),
`selected_transition_trigger: StringName` (empty when none),
`period_effect: MatchTransitionDef.PeriodEffect` (`NONE` when no transition),
`clock_delta_numerator: int`, and `clock_delta_denominator: int`. Delta uses the same reduced
non-negative rational convention as the context. The transition's condition resource is not
exposed. No mutable config or sim reference is exposed.

## Tick result shape

`TickResult.Status` is the public enum with exactly `PREPARED`, `COMMITTED`, `NO_OP_INVALID`,
`NO_OP_FINISHED`, `NO_OP_STOPPED`, `FAILED_RETRYABLE`, and `FATAL_ROLLBACK`. The properties are
read-only. For `PREPARED` and `COMMITTED`, `error == OK`, `outcome` is non-null, and `outputs` and
`signal_batch` are detached ordered snapshots (possibly empty). Only `PREPARED` carries the exact
opaque active-tick handle in `prepared_tick`; `COMMITTED` carries the same outcome/output/batch
values and has `prepared_tick == null` because finalization consumed the handle. `NO_OP_INVALID` has
`ERR_INVALID_PARAMETER`; `NO_OP_FINISHED` and `NO_OP_STOPPED` have `OK`, and all no-op shapes have
`outcome == null`, `prepared_tick == null`, and empty outputs/batch. `FAILED_RETRYABLE` has a
non-OK phase error, `outcome == null`, `prepared_tick == null`, and empty outputs/batch. `FATAL_ROLLBACK` has a non-OK error, `outcome == null`, `prepared_tick == null`, and empty
outputs/batch; its stable non-empty fatal reason is read from
`MatchSim.stop_reason()`, as specified by S1-core. Runner terminal statuses and replay result
shapes remain those separately specified in S1-core.

## Deterministic checked-failure injection

Ordinary checked failures are tested with caller-owned fakes, not a production failure switch.
`SimSystem.tick_checked`, `SimTickOwner.capture_tick`, `SimTickOwner.commit_tick`,
`SimSystem.checkpoint`, and `SimSystem.restore` already return explicit checked results/errors;
test fakes may return the failure shape on a selected call and successful shapes otherwise. Flow
failure uses a test-owned fixture at
`tests/unit/match/fixtures/injectable_failure_condition.gd`, extending `MatchCondition`. It has an
explicit no-argument `_init()`, a test-controlled `fail_enabled: bool` defaulting to `false`, and
`evaluate_checked(sim: MatchSim) -> ConditionEvaluationResult`. When enabled it returns
`(false, false, ERR_FAILED)`; when disabled it returns `(true, true, OK)`. Evaluation never mutates
the flag. Enable it before the candidate tick and disable it before an explicit retry. This is a
test fixture contract, not a production class or production switch.

For fallible preparation after a successful tick, use an ordinary rejected codec/row preparation
result (for example, a fake codec rejects a malformed typed record, or a row preparer returns its
specified non-OK validation error). This path occurs before finalization and must take the specified
abort/rollback route. It is not an allocation-failure simulator and does not require a public
production failure toggle. No acceptance claim promises deterministic process-memory allocation
failure. The precise typed fake codec, row preparation result and error enum are S2-owned and must
be frozen in an independently reviewed S2 fake contract before those S2-dependent assertions are
authored.

## Composition ownership boundary

S1 owns the public request record shape:

`MatchCompositionRequest(config: MatchConfig, systems: Array[SimSystem], mod_set_hash: String,
action_layout_hash: String, extension_points: ExtensionPoints, s2: S2RuntimePort)`.

`systems` is copied as an ordered array of exact participant references, preserving the caller's
order. The effective registry starts with those request systems, then the builder adds extension
and composed system entries in the declared S1-core order, and finally appends exactly one S2 owner
adapter. The request's `systems` list is not the complete effective registry. `config`,
`extension_points`, and `s2` are the exact injected typed objects; hashes are strings. S1 does not define
`ExtensionPoints` or `S2RuntimePort` internals.

`MatchReadinessBlocker` is an immutable record at
`game/match/match_readiness_blocker.gd`. Its nested `Code` enum is
`MISSING_REQUIRED_INPUT`, `INVALID_CONFIGURATION`, `INVALID_TICK_RATE`, `UNSAFE_EXTENSION`,
`PARTICIPANT_SETUP_FAILED`, or `PROVIDER_OWNERSHIP_FAILED`. Its positional constructor is
`_init(p_code: Code, p_subject: StringName, p_message: String)`. `subject` identifies the stable
input key or participant/provider identity when known (for example, `&"contact_source"` or
`&"contact_solver"`); it is empty only when no single subject applies. `message` is diagnostic
text and is not identity or fingerprint input. `MatchReadinessReport` at
`game/match/match_readiness_report.gd` has an immutable copied
`blockers: Array[MatchReadinessBlocker]`, constructed by
`_init(p_blockers: Array[MatchReadinessBlocker] = [])`, and `is_ready() -> bool`, true exactly when
the list is empty. It is the one public report type for build blockers and evaluated replay readiness.

`MatchBuildResult` at `game/match/match_build_result.gd` is a positional immutable record with
constructor `_init(p_ok: bool, p_sim: MatchSim | null, p_codec: S2ReplayCodec | null,
p_setup_fingerprint: String, p_readiness: MatchReadinessReport, p_error: Error)`. Its fields in
that order are `ok: bool`, `sim: MatchSim | null`, `codec: S2ReplayCodec | null`,
`setup_fingerprint: String`, `readiness: MatchReadinessReport`, `error: Error`. Every build
returns a non-null readiness report. Success is `(true, sim, codec, non-empty fingerprint, ready
report, OK)`; failure is `(false, null, null, empty fingerprint, report with blockers, non-OK)`.
The codec is the single composition-provided codec described by S1-core. Readiness diagnostics do
not substitute for `error`, and diagnostic message text is not fingerprinted.

`MatchReplayResult` at `game/match/match_replay_result.gd` is a positional immutable record with
constructor `_init(p_sim: MatchSim | null, p_error: Error,
p_replay_failure: MatchReplayResult.ReplayFailure, p_fatal_reason: StringName,
p_readiness_evaluation: MatchReplayResult.ReadinessEvaluation,
p_readiness: MatchReadinessReport)`. `ReplayFailure` contains `NONE`, `INVALID_RECORD`,
`INVALID_LINKAGE`, `INCOMPATIBLE_HEADER`, `PORT_RESET_FAILED`, `TICK_FAILED`, `OUTPUT_MISMATCH`,
and `FATAL_ROLLBACK`. `ReadinessEvaluation` contains `NOT_EVALUATED`, `PREFLIGHT_ONLY`, and
`BUILDER_COMPLETE`. Every result has a non-null readiness report. `NOT_EVALUATED` means null
log/header or a typed non-v3 header stopped replay before setup; its report is an empty placeholder.
`PREFLIGHT_ONLY` means null-request handling or dependency-shareability checks returned before the
full replay composition build; its report may hold known blockers but is incomplete.
`BUILDER_COMPLETE` means the full replay composition builder returned; its report is complete and
retained on later success or failure. Callers must not infer full readiness from `is_ready()` unless
the state is `BUILDER_COMPLETE`. Success is `(sim, OK, NONE, &"", BUILDER_COMPLETE, ready report)`;
a failure after composition evaluation has `sim == null`, non-OK error, the applicable failure and
reason, `BUILDER_COMPLETE`, and the evaluated builder report. A fatal rollback has
`replay_failure == FATAL_ROLLBACK` and non-empty `fatal_reason`.

`ReplayValidationToken` and `PreparedAppendToken` remain opaque single-use capabilities with no
public nonce/field access and no caller-visible mint operation. Each exposes an ordinary public
no-argument constructor. Calling it creates an inert, unregistered object with no usable authority;
replay finalization rejects a caller-created `ReplayValidationToken`. A caller-created
`PreparedAppendToken` is rejected by `MatchSim.finalize_prepared_tick`, `InputLog.commit_append`,
and `InputLog.cancel_append`; these rejections leave the active tick, log reservation, and
published rows/signals unchanged. Only the exact internally minted registered object is usable. Valid tokens remain
unforgeable through the public API. Copying or reassembling token fields is not a public test case:
the API exposes no such fields or copy constructor, so those attempts cannot be expressed without
breaking opacity. Cross-log, cross-index, cross-tick, cross-sim, stale, cancelled, consumed, aborted,
and row/readback/output-identity substitution checks remain required. `MatchCompositionRequest` above is fully specified and remains a build input record, not
a handle for tests to mutate the sim.

`ReplaySourceRow.new()` is the approved way for a fake to create a caller-constructed row for the
C-75 rejection case. It creates an inert object whose `frame` accessor is null and whose command
and output accessors return empty detached arrays; it carries no log-issued identity. Tests must
not set row values, copy an identity, or mint row authority. Only
`InputLog.read_replay_row(index)` returns a populated row with usable log-bound identity. Passing
the inert row to `MatchSim.begin_replay_row` returns `(false, null, ERR_INVALID_PARAMETER)` before
checkpoint capture or port transaction, with no sim or port state change.

The S2-owned contract must separately specify concrete typed `S2RuntimePort` and
`S2RuntimePortOwner` methods/claims/checkpoint state; `S2ReplayCodec` concrete record types,
validation and fallible preparation results; `S2ProviderBindings` fields; and
`S2ReplayInstanceResult`. For the bounded output bridge, `S2RuntimePort` exposes
`take_staged_result_suffix(requested_candidate_tick: int) -> S2StagedResultSuffixResult`, called by
`S2ReplayCodec.prepare_outputs(prepared_tick)` with that exact `PreparedTick` candidate tick during
PREPARED validation. The S2-owned `S2StagedResultSuffixResult` constructor fields, in order, are
`ok: bool`, `requested_candidate_tick: int`, `staged_candidate_tick: int`,
`results: Array[S2RuntimeResult]`, and `error: Error`. Success is
`(true, requested_tick, exact_active_staged_tick, detached typed results, OK)`; an empty suffix is
a valid success. Wrong tick fails with empty results and `ERR_INVALID_PARAMETER`, reports the
active bound staged tick, and preserves availability. A repeated successful take fails with empty
results and `ERR_ALREADY_EXISTS`, retaining consumed state for that transaction. With no active
matching staged suffix, failure has empty results, non-OK `ERR_UNCONFIGURED`, and staged tick `-1`
when no active bound tick exists. All arrays are detached copies; result records and nested payloads
are sealed immutable records, and failure results never expose a partial suffix. S2 also exposes
`capture_tick(context)`, which binds the candidate tick and initializes an empty staged suffix.
`S2RuntimePort` exposes this S2-owned callable:

```gdscript
func complete_command(
		command: S2RuntimeCommand,
		result: S2RuntimeResult,
		consumer_phase: S2RuntimeCommand.Phase
) -> S2CommandCompletionResult
```

`S2CommandCompletionResult` is an S2-owned immutable result record, not a generic S1 type. Its
constructor is `_init(p_ok: bool, p_result: S2RuntimeResult | null, p_error: Error)` and its
constructor fields, in order, are `ok: bool`, `result: S2RuntimeResult | null`, and `error: Error`.
Success is `(true, canonical_result, OK)`, where the port supplies sequence and kind from its frozen
canonical command membership, not from producer fields. The canonical result and nested payloads
are detached, sealed, immutable records. Failure is `(false, null, non-OK)`: reject unknown or
changed commands, wrong phase, duplicate sequence, unsuccessful result, or malformed/uncopyable
payload. A failed call consumes no command, stores or stages no result, and advances no queue,
sequence, or result state. The producer returns failed `SystemTickResult`, causing outer S1 abort.

Record getters return detached result values; constructor inputs and any nested mutable payloads are
detached, and published nested records are sealed. Successful completion calls append the same
canonical value to the port's global results and staged suffix in deterministic call/completion
order. The completing producer appends the returned `canonical_result` to its own
`SystemTickResult.outputs` in the same order as its successful calls. It never appends the submitted
result argument or reconstructs local outputs by reading the global suffix. Systems run in registry
order, so S1's registration-order concatenation of producer-local output arrays equals the exact
global staged suffix. LocomotionSystem, BallPhysicsSystem, and S2InteractionSystem return only their
newly completed successful result records in completion order; the owner captures, checkpoints,
and restores state and returns no outputs. The S2 codec compares the registered-system aggregate to
the exact staged port suffix by detached value and order. `take_staged_result_suffix` remains solely
the codec's one-shot PREPARED validation readback API described above. S1 does not add a generic port
protocol, generic command/output schema, or public checkpoint-payload fields to make a fake
convenient.
