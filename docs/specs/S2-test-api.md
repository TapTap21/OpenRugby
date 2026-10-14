# S2 public test API

Status: normative test-facing integration contract for [S2-physics](S2-physics.md) and the
[S1 public test API](S1-test-api.md).
This document defines the S2 adapter and replay seams needed by S1 lifecycle/replay tests. It
does not change physics behavior, numeric values, S1 tick order, or transaction boundaries. The
test inventory remains the acceptance source for C-45–C-77. Current declarations are listed as
such; a declared method is not evidence that it satisfies this target contract.

## 1. Names and authority

All paths are repository-root relative. Public records below are `class_name` GDScript types.
Unless a result explicitly contains a mutable object reference, records are immutable snapshots:
constructor arrays and nested containers are deep-copied, and container getters return detached
copies. Exact provider references are retained only where identity is part of the contract.

The S2 integration owns these new required public types and methods. Generic lifecycle, replay,
codec-result, encoded-bundle, readback, append-token, and replay-validation records are S1-owned;
this document uses their canonical S1 names and signatures and does not define replacements.

| Type | Required path | Status at `c4b5adb` |
|---|---|---|
| `S2RuntimePortOwner` | `game/match/s2_runtime_port_owner.gd` | Missing; required adapter implementing the S1 owner seam |
| `S2ProviderBindings` | `game/match/s2_provider_bindings.gd` | Missing; required typed factory input |
| `S2ReplayInstanceResult` | `game/match/s2_replay_instance_result.gd` | Missing; required typed factory result |
| `S2ReplayCodec` | `game/match/s2_replay_codec.gd` | Missing; required typed codec |

Already declared in this worktree are `S2RuntimePort` at `game/match/s2_runtime_port.gd`,
`S2RuntimeCommand` at `game/match/s2_runtime_command.gd`, `S2RuntimeResult` at
`game/match/s2_runtime_result.gd`, `S2PlayerTickInput`, `PlayerFatigueSnapshot`,
`S2BallInitialization`, `S2PlayerInitialization`, and `S2WindPolicy` under
`game/physics/state/`, plus `MatchBuildResult` and `MatchReadinessReport`. Section 8 names the
concrete declared payload fields. Their present signatures do not supply the missing adapter,
codec, prepared append, or replay receipt guarantees. `ReplayRowBeginResult`,
`ReplayValidationResult`, `CanonicalPortReadbackResult`, `CodecResult`, `EncodedCommandBundle`,
`PreparedOutputBundle`, `AppendPrepareResult`, and the opaque `PreparedAppendToken` and
`ReplayValidationToken` are S1-owned types specified by S1-core and the S1 public test API.

## 2. `S2RuntimePort` test seam

Path/class: `game/match/s2_runtime_port.gd`, `class_name S2RuntimePort extends RefCounted`.
The declared public calls used by this contract are:

```gdscript
func enqueue(command: S2RuntimeCommand) -> int
func queued_command_snapshots() -> Array[Dictionary]
func results() -> Array[S2RuntimeResult]
func results_since(first_index: int) -> Array[Dictionary]
func enqueue_replay_commands(values: Array[Dictionary]) -> bool
func setup_snapshot() -> Dictionary
func snapshot() -> Dictionary
func begin_tick() -> void
func tick_succeeded() -> bool
func commit_tick() -> void
func rollback_tick() -> void
func reset_runtime() -> bool
```

### Queue and result rules

`enqueue` accepts one valid command whose `sequence == -1`, assigns the current non-negative
`next_sequence`, increments `next_sequence` once, and returns the assigned sequence. It returns
`-1` for a null/invalid command, an explicitly assigned sequence, or a command rejected by
validation; rejection leaves the complete runtime snapshot unchanged. The accepted command is
detached from the caller and appended to the pending queue. A test fake follows these same rules.

`queued_command_snapshots()` returns a detached ordered copy of the full pending command queue.
Each dictionary is exactly `S2RuntimeCommand.snapshot()` for that command; it is not a second
command schema. `results()` returns detached typed copies of all results retained by the port.
`results_since(first_index)` returns detached serialized snapshots from result index
`first_index` through the current end; valid indices are `0..results().size()`, inclusive at the
end. An out-of-range index returns an empty array and does not mutate state. Results are retained
in completion order until `reset_runtime()`.

The command queue has a single monotonically assigned sequence space for the lifetime of a
runtime instance. On a successful tick, commands completed in that tick leave the pending queue
and get one result with the same sequence and kind; commands not consumed remain pending with
their original sequence. No sequence is renumbered or reused. A failed tick restores pending
commands, results, consumed markers, `next_sequence`, `tick_failed`, `failure_detail`, and
`failure_sequence` to the exact pre-tick values.

`enqueue_replay_commands(values)` receives the full pending-queue row from the replay log, not
only its newly introduced suffix. It succeeds only if every dictionary decodes as a valid
`S2RuntimeCommand`, sequences are unique and increasing, each carried command matches the
existing pending command with that sequence byte-for-value at the typed snapshot level, and each
new suffix sequence is exactly the next expected sequence. It injects only that new suffix and
leaves carried commands in place. Validation is all-or-nothing: `false` leaves queue, results,
consumed markers, `next_sequence`, and failure fields unchanged. After injection,
`queued_command_snapshots()` must equal the full replay row exactly.

### Setup snapshot and runtime snapshot

`setup_snapshot()` is a detached dictionary containing only construction/setup identity. The
required target keys and types are `contact_source: Dictionary`, `contact_solver: Dictionary`,
`ball_initialization: Dictionary`, `wind_policy: Dictionary`, `pitch_condition: int`,
`fatigue_option: int`, and `player_initializations: Array[Dictionary]`. Player setup records are
sorted by `(team_id, shirt_number, player_id)`; the returned containers are detached. These
contents are included in the setup fingerprint through their canonical values, not object
addresses. This is the required target shape: at `c4b5adb`, the current `setup_snapshot()` uses
`players` for the player array instead of `player_initializations`, so that declaration does not
yet conform to the target key.

`snapshot()` is the complete deterministic runtime state. The required target keys are all setup
snapshot keys plus `queued_commands: Array[Dictionary]`, `results: Array[Dictionary]`,
`consumed_sequences: PackedInt32Array` in ascending order, `next_sequence: int`,
`tick_failed: bool`, `failure_detail: String`, and `failure_sequence: int`. `tick_failed` is the
serialized equivalent of the port's `_tick_failed` state and must agree with
`tick_succeeded() == not tick_failed`. Tests compare this whole value before and after rollback;
they do not inspect private members. The snapshot intentionally excludes the port's object
references to providers/systems and the transient transaction-handle implementation.
At `c4b5adb`, the current `snapshot()` emits only `commands`, `outputs`, and `next_sequence`; it
has no setup keys, `queued_commands`, `results`, `consumed_sequences`, or failure fields. The
current names and shape are implementation observations, not substitutes for the required target
keys.

### Tick transaction and reset

`begin_tick()` captures the complete `snapshot()` above before any command is consumed. It is
called exactly once before the S2 systems process that tick. `tick_succeeded()` is true only if
no S2 command/system has failed during the active tick. `commit_tick()` is called once after a
successful S2 tick and marks the port work successful, but retains the pre-tick snapshot and
rollback ability while the outer S1 prepared transaction is abortable. It must not discard rollback
state during codec validation, row preparation, or sim finalization. The retained/restored state
includes `_tick_failed` (exposed in `snapshot()` as `tick_failed`) and both failure fields. The
next `begin_tick()` may discard the previous snapshot only after the prior S1 commit boundary has
completed, then captures
the new complete snapshot. `rollback_tick()` while the outer transaction is abortable restores
every runtime snapshot field exactly and clears that transaction state. A rollback without a
retained transaction is a no-op. The outer S1 transaction owns the call order and invokes rollback
on every checked failure.

`reset_runtime()` clears pending commands, retained results, consumed sequences, failure detail,
and failure sequence; resets `next_sequence` to zero; and sets `tick_failed` to `false` (the
internal `_tick_failed` state is also reset). It does not change providers, initialized ball/player
setup, wind policy, pitch/fatigue environment, attached systems, or setup identity. It returns
`true` after reset. A fake may return `false` to represent a checked reset rejection; that is an
ordinary failure result and must leave the complete runtime snapshot, including `tick_failed`,
unchanged.

For checked failures, port fakes use the declared `-1`/`false` results and preserve state as
specified; codec and append failures use the S1 `CodecResult` and `AppendPrepareResult` shapes.
Tests do not depend on process allocation failure or a production failure switch.

## 3. Registered typed owner adapter

`S2RuntimePortOwner` at `game/match/s2_runtime_port_owner.gd` extends `SimTickOwner` and is the
single final registry entry that owns the exact port's queue, results, consumed sequences, next
sequence, and failure state. It is registered once after the composed S2 systems. Its inherited
`tick(sim)` remains a no-op. The adapter does not claim the contact source or solver as providers;
their unique generic owners retain their provider checkpoint and claim obligations.

The adapter implements the exact S1 generic owner API, plus its typed construction attachment:

```gdscript
func attach_port(port: S2RuntimePort) -> Error
func port() -> S2RuntimePort
func setup(sim: MatchSim) -> SetupResult
func capture_tick(context: SimTickContext) -> OwnerCaptureResult
func commit_tick(context: SimTickContext, capture: OwnerCapture,
        outcome: SimTickOutcome) -> OwnerCommitResult
func checkpoint() -> CheckpointResult
func restore(checkpoint: Variant) -> Error
func create_replay_instance() -> ReplayInstanceResult
```

`setup`, `capture_tick`, `commit_tick`, `checkpoint`, `restore`, and the generic replay factory
have the signatures and result shapes specified by S1-core and the S1 public test API. Setup is
the normal `setup(sim)` call exactly once after port attachment; there is no separate
`setup_result()` method. `attach_port` succeeds once before setup, returns `OK` on success, and
returns a non-OK `Error` for null, repeated, or already-owned port references. `port()` returns the
exact attached object. Before owner operations the adapter verifies its attached port is the same
exact instance wired into the composed S2 system graph; a mismatch is a checked error and cannot
write either port. S2 systems and the adapter all hold that exact port reference.

`setup(sim)` returns `SetupResult` with capability `COMPLETE_TRANSACTIONAL`, a non-null stable
`ParticipantClaim`, and an empty `owned_provider_claims` array. Contact source and solver providers
each have exactly one separate generic owner in the effective registry; that owner's claim
retains the exact provider reference and stable id/version, configuration fingerprint, and
deterministic initial-state fingerprint. No provider reference may also be claimed by this
adapter. Missing, duplicate, unsupported, or incomplete provider claims reject composition before
tick 1. Claim contents and ordering participate in the S1 setup fingerprint according to S1;
provider object addresses do not.

`capture_tick` captures the complete port runtime snapshot before S2 systems run and returns the
S1 immutable `OwnerCaptureResult`. `commit_tick(context, capture, outcome)` reports successful
S2 work only after the systems and S1 flow staging succeed. It leaves the port state restorable
through output preparation, row preparation, and sim finalization; S1 can still abort and restore
after an owner commit. `checkpoint()` and `restore(checkpoint)` implement the generic S1
participant checkpoint contract over that same complete snapshot. Failed capture/commit/
checkpoint/restore uses the exact S1 checked result/error shape. Restore failure is fatal rollback
per S1. Neither the generic capture nor checkpoint exposes the port's internal dictionary by
mutable reference.

The adapter's generic `create_replay_instance()` runs once per mutable registry entry in the S1
factory pass and returns a fresh, unbound adapter with no provider claims. The separate typed port
factory creates the fresh port; the builder attaches that exact port once before normal setup.
Provider claims remain with the unique generic participants that own each provider reference;
neither the port nor adapter repeats those claims. Stateless generic participants may self-reuse
only under the S1 cross-registry rule.

## 4. Fresh replay providers and build result

`S2ProviderBindings` at `game/match/s2_provider_bindings.gd` is the typed factory input. Its
fields, in constructor order, are:

```gdscript
contact_source: BallContactSource
contact_source_claim: ProviderClaim
contact_solver: BallContactSolver
contact_solver_claim: ProviderClaim
```

Each claim is the exact validated `ProviderClaim` from the unique generic owner of that provider;
`claim.provider` is the same object reference as the paired binding. The bindings retain these
exact fresh initial provider objects and do not clone them. A missing optional provider is allowed
only when readiness explicitly marks its capability unavailable; replay playback requires ready
contact source and solver under S2-physics §10.

The S2-only typed factory is declared on `S2RuntimePort`:

```gdscript
static func create_replay_instance(bindings: S2ProviderBindings) -> S2ReplayInstanceResult
```

`S2ReplayInstanceResult` has fields in this exact order: `ok: bool`,
`port: S2RuntimePort | null`, `error: Error`. Success is `(true, fresh_port, OK)` and failure is
`(false, null, non-OK)`. This is separate from the generic S1 `ReplayInstanceResult`; the port is
not a `SimSystem` and is never dispatched through the generic participant factory.

Replay composition follows S1-core §3.3: clone each mutable effective registry participant once
in place, validate fresh factory claims and provider-reference uniqueness, derive bindings from
those exact claims, call the typed port factory once, attach that exact fresh port to the fresh
unbound owner, construct the fresh sim/ordered registry, then call normal `setup(sim)` once and
require each setup claim to match its factory claim in count, order, object identity, stable values,
and capability. No provider is cloned twice, and the original request graph is not set up,
reset, or ticked. The port copies stable configuration and transient runtime setup; it does not
clone providers.

`MatchBuildResult` keeps the exact S1 public test API shape: `ok`, `sim`, `codec`,
`setup_fingerprint`, `readiness`, `error`. This S2 document adds no `s2`, `system_ids`, or
alternate result fields. `MatchReadinessReport` remains the shared S1 report type.

The current action-layout identity is `request.action_layout_hash`, supplied explicitly in the
same `MatchCompositionRequest` used by live composition. Direct replay has the exact S1 entry
point:

```gdscript
static func run(request: MatchCompositionRequest, log: InputLog) -> MatchReplayResult
```

`MatchReplay.run` compares the v3 header against `request.mod_set_hash`, the explicit current
`request.action_layout_hash`, the fresh setup fingerprint, and tick rate. It does not use
`InputSource.layout_hash()` or the stored header value as the current identity. A mismatch or
missing current identity returns before row capture, tick, append, or publication. After successful
compatibility only, fresh replay calls `reset_runtime()` exactly once; failure returns the S1
`PORT_RESET_FAILED` replay result before the first row. The full `MatchReplayResult` shape and
compatibility errors are S1-owned as specified in S1-core.

## 5. S2 replay codec on the S1 value API

Path/class: `game/match/s2_replay_codec.gd`, `class_name S2ReplayCodec extends RefCounted`. The
codec converts the existing typed `DetachedCommandBundle`, `S2RuntimeCommand`, and
`S2RuntimeResult` values to and from the existing v3 row dictionaries. It does not define
`S2CodecResult`, separate encoded/decoded command or output records, or parallel wire fields.
The S1 result/bundle types below retain their exact canonical signatures and ownership rules.

Required S1 codec methods implemented by the S2 codec are:

```gdscript
func prepare_commands(command_bundle: DetachedCommandBundle) -> CodecResult
func decode_commands(records) -> CodecResult
func decode_outputs(records) -> CodecResult
func prepare_outputs(prepared_tick) -> CodecResult
func encode_outputs(prepared_output_bundle) -> Array[Dictionary]
func capture_canonical_port_readback(port: S2RuntimePort) -> CanonicalPortReadbackResult
func validate_replay_row(prepared_tick: PreparedTick, source_row: ReplaySourceRow,
        canonical_port_readback: CanonicalPortReadback) -> ReplayValidationResult
```

`prepare_commands` returns a `CodecResult` containing the opaque `EncodedCommandBundle` bound to
the exact source `DetachedCommandBundle` and detached v3 records. Decode calls return the
appropriate existing concrete S2 typed values in `CodecResult`; malformed records produce a
non-OK result and no partial bundle. `prepare_outputs` obtains outputs only from the exact
`PreparedTick`'s validated detached `TickResult.outputs` and returns the opaque
`PreparedOutputBundle` paired with that tick. No method accepts a caller-supplied output array to
mint a prepared bundle. `encode_outputs` consumes only that bundle.

`capture_canonical_port_readback(port)` reads the full pending queue exactly once, validates and
decodes those canonical records, and returns the S1 `CanonicalPortReadbackResult` with fields
`ok: bool`, `readback: CanonicalPortReadback | null`,
`command_bundle: DetachedCommandBundle | null`, and `error: Error`. Failure returns no readback
or bundle. The opaque readback identity is paired with those exact decoded commands; copying an
array or reading the port again cannot create an equivalent authority.

`validate_replay_row` validates the exact `ReplaySourceRow`, carried/new sequence rules, canonical
readback, command/output linkage, and expected outputs against the generated outputs on the
`PreparedTick`. It returns the S1 `ReplayValidationResult` `{ok, token, error}`. The codec's
receipt mint operation is private to this validation path and the build-owned authority; there is
no public `mint_replay_receipt`, arbitrary output-array input, or caller-supplied success boolean.
Only a successfully validated exact row can produce the opaque registered
`ReplayValidationToken` consumed by `MatchSim.finalize_replay_tick`.

V3 commands and outputs retain the existing snapshot field names, kinds, order, and meanings. A
row is valid only when each output refers to exactly one command with the same sequence and kind,
and generated output records equal the recorded expected records. Tests use the S1 `CodecResult`,
`CanonicalPortReadbackResult`, and `ReplayValidationResult` contracts; they must not invent
parallel result shapes or inspect private authority state.

## 6. Prepared append and capability pairing

`InputLog` uses the S1-owned prepared append API:

```gdscript
func prepare_append(prepared_tick: PreparedTick, command_bundle: EncodedCommandBundle,
        output_bundle: PreparedOutputBundle) -> AppendPrepareResult
func commit_append(token: PreparedAppendToken) -> void
func cancel_append(token: PreparedAppendToken) -> Error
```

The return type is the S1 `AppendPrepareResult`: `PREPARED(token)` or `FAILED(error)`. The
opaque `PreparedAppendToken` is minted only by the exact log's private path. Preparation obtains
the frame and command candidate from the exact `PreparedTick`, verifies the encoded command source
identity and matching prepared-output identity, builds/copies the full row, and reserves its
index without changing visible rows or `frame_count`. There is no caller-supplied frame or raw
command/output array in this API. The token is bound to the exact log, row generation/index,
`PreparedTick`, command identity, output identity, and row, as specified by S1-core. An inert
caller-created token and stale, foreign, mismatched, cancelled, or consumed tokens are rejected
without publication. Finalization/commit/cancel behavior is the S1 contract; no S2 replacement
append token or result type exists.

For replay, `InputLog.read_replay_row(index)` supplies one detached `ReplaySourceRow` and its
log-issued identity. The codec validates that source row; replay never appends to the source log.
The private replay receipt is minted only by `S2ReplayCodec.validate_replay_row` after complete
validation and is consumed once by the matching `MatchSim.finalize_replay_tick`.

A deterministic checked preparation failure is an ordinary non-OK S1 `CodecResult` or
`AppendPrepareResult` before finalization; allocation failure and production failure toggles are
not test inputs. The public result contract is fixed here, but injection of a fake codec/log into
`MatchRunner` is not defined by S1 or this S2 API. Therefore the injected-failure/retry portions
of C-48 and C-67 remain deferred until an independently reviewed test-only composition seam is
specified. C-69's typed-factory spy/failure branches and C-70's fake reset-rejection/order branch
also remain deferred: the current static typed factory has no public fake-factory injection point.
The real successful factory/reset behavior and ordinary invalid-input validation remain
specifiable and testable without such an injector.

## 7. S1 transaction order retained

Live S2 order follows S1-core: poll/fill once and seal the detached typed submission bundle;
enqueue each submitted command once; read the canonical full pending queue exactly once through
`capture_canonical_port_readback`; use its paired detached command bundle as the tick candidate;
call `prepare_commands(candidate_bundle)`; then call `MatchSim.tick_checked(frame,
command_bundle)`. A command encoding/validation failure occurs before tick execution. The prepared
tick's own immutable `TickResult.outputs` are the sole source for
`prepare_outputs(prepared_tick)`, followed by `encode_outputs(prepared_output_bundle)` and
`InputLog.prepare_append(prepared_tick, encoded_command_bundle, prepared_output_bundle)` while the
tick remains abortable. The owner and port retain their pre-tick rollback state through all of this
work and through sim finalization.

If any checked phase or fallible preparation fails before finalization, abort the prepared tick,
cancel any prepared append token, and restore the sim, generic owners/providers, and complete S2
port snapshot, including `_tick_failed` and its observable `tick_failed` snapshot value. Keep the
exact sampled frame, typed candidate, and already assigned port sequences for explicit retry; do
not poll, enqueue, or assign replacement sequences again. On success,
`MatchSim.finalize_prepared_tick(prepared_tick, append_token)` and
`InputLog.commit_append(append_token)` are infallible, allocation-free, and callback-free, with no
callback between them. The complete row is visible before staged MatchSim signals, EventBus relay,
and `ticked` last. A retryable failure publishes no row, output, or signal; a restore failure is
fatal under S1.

Replay first builds and validates fresh participants/providers/port, checks the v3 header against
current request identity, and resets the fresh port exactly once after compatibility. For every
row, read exactly one `ReplaySourceRow`, then call
`MatchSim.begin_replay_row(source_row) -> ReplayRowBeginResult` before sequence validation or
command injection. This captures the complete sim and owner checkpoint, including the S2 port
snapshot, before any replay queue mutation. Decode the row using the S1 `CodecResult`; compare the
full carried queue with the prior committed survivors by sequence, canonical payload, and order;
reject missing, changed, duplicated, or reordered survivors; inject only the next contiguous new
suffix; and capture canonical readback exactly once. Require readback to equal the full row and
pass its paired command bundle to `tick_replay_row(prepared_tick, frame, command_bundle)` using
the already-open checkpoint. Do not begin a second transaction or take a second checkpoint.

The codec derives generated outputs from the exact returned `PreparedTick`, decodes the expected
row outputs, and calls `validate_replay_row(prepared_tick, source_row, canonical_port_readback)`.
Only its successful S1 `ReplayValidationResult` can carry the private-minted receipt. Finalize
with `MatchSim.finalize_replay_tick(prepared_tick, token)` and publish only after success; replay
never appends to its source log. Any pre-finalization failure aborts the prepared tick and restores
the exact pre-row sim/owner/port state, including `_tick_failed` and its snapshot value. Fatal
restore failure is distinct from retryable tick failure and latches the sim stopped. Tick and codec outputs come from `PreparedTick` and the
S1 result records; no caller-supplied output arrays or parallel S2 result schema are permitted.

## 8. Existing command and result payloads

These are the declared typed payloads at `c4b5adb`, summarized from `S2-physics` §10 and the
S2 declarations. Constructor helpers are available on `S2RuntimeCommand`; tests should use those
helpers for valid records and mutate fields only for invalid-input cases.

`S2RuntimeCommand` enums are `Kind {PLAYER_TICK_INPUT=0, BALL_STATE=1, KICK=2, PASS=3, CATCH=4,
FUMBLE=5, PICKUP=6, TACKLE=7, SPILL=8}`, `Phase {LOCOMOTION=0, BALL=1, INTERACTION=2}`,
`CandidateState {UNRESOLVED=0, NO_CANDIDATE=1, SELECTED=2}`, and
`GateState {UNRESOLVED=0, DISABLED=1, ENABLED=2}`. Its fields and exact types are:

| Field | Type |
|---|---|
| `kind`, `catch_candidate`, `catch_gate` | `Kind`, `CandidateState`, `GateState` respectively |
| `sequence`, `kick_type`, `difficulty`, `forward_assist_setting`, `defender_tackling`, `carrier_strength` | `int` |
| `actor_id` | `StringName` |
| `tackling_fatigue_snapshot` | `PlayerFatigueSnapshot` |
| `player_input` | `S2PlayerTickInput` |
| `ball_mode` | `BallState.Mode` |
| `goal_kick_state` | `BallState.GoalKickState` |
| `wind_policy` | `S2WindPolicy` |
| `gauge`, `kicking_power`, `kick_accuracy`, `heading_radians`, `place_meter_gauge`, `place_meter_error`, `attack_direction`, `catch_probability`, `probability`, `pickup_vertical_separation_m`, `relative_angle_degrees`, `carrier_break_modifier` | `float` |
| `ai_place`, `has_place_meter`, `ball_held`, `hand_capsule_intersects`, `defender_has_tackle`, `carrier_strength_ability`, `out_of_position` | `bool` |
| `pass_launch` | `PassLaunch` |

`sequence` begins at
`-1` before port acceptance; `actor_id` identifies the action owner where the command is
player-owned. `phase()`, `validate()`, `snapshot()`, and `static from_snapshot(Dictionary)` are
declared. The existing factory signatures are:

```gdscript
static func player_tick_input(value: S2PlayerTickInput) -> S2RuntimeCommand
static func ball_state(mode: BallState.Mode, goal_kick_state: BallState.GoalKickState,
        wind: S2WindPolicy = null) -> S2RuntimeCommand
static func kick(kick_type: int, gauge: float, kicking_power: float, kick_accuracy: float,
        heading_radians: float, difficulty: int, ai_place: bool = false,
        place_meter: PlaceKickMeterResult = null) -> S2RuntimeCommand
static func pass(launch: PassLaunch, assist_setting: int, direction: float) -> S2RuntimeCommand
static func catch(actor: StringName, candidate: CandidateState, failure_probability: float,
        gate: GateState) -> S2RuntimeCommand
static func fumble(actor: StringName, probability: float) -> S2RuntimeCommand
static func pickup(actor: StringName, ball_held: bool, vertical_separation_m: float,
        capsule_intersects: bool) -> S2RuntimeCommand
static func tackle(actor_id: StringName, fatigue: PlayerFatigueSnapshot,
        defender_has_tackle: bool, carrier_strength: int, carrier_strength_ability: bool,
        relative_angle_degrees: float, carrier_break_modifier: float,
        out_of_position: bool = false) -> S2RuntimeCommand
static func spill(actor: StringName, probability: float) -> S2RuntimeCommand
static func tackle_from_fatigue(actor_id: StringName, fatigue: PlayerFatigueSnapshot,
        defender_has_tackle: bool, carrier_strength: int, carrier_strength_ability: bool,
        relative_angle_degrees: float, carrier_break_modifier: float,
        out_of_position: bool = false) -> S2RuntimeCommand
```

Nested concrete fields:

- `S2PlayerTickInput`: `player_id: StringName`, `sprint_request: int`, `urgency: float`,
  `fatigue_snapshot: PlayerFatigueSnapshot`.
- `PlayerFatigueSnapshot`: `team_id`, `player_id`, `shirt_number`, `fatigue_time_s`,
  `energy_cap`, `energy_percent`, `effective_passing`, `effective_tackling`,
  `initial_sprint_energy`. It is owner-supplied; S2 does not own/advance fatigue time.
- `S2BallInitialization`: `position_m`, `orientation`, `linear_velocity_m_s`,
  `angular_velocity_rad_s`, `mode`, `goal_kick_state`, `wind_policy`.
- `S2PlayerInitialization`: `player: PlayerMotionState`; `validate()`, `copy_player()`,
  `snapshot()`.
- `S2WindPolicy`: `resolved`, `enabled`, `vector_km_h`.
- `PassLaunch`: `velocity_m_s`, `flight_time_s`, `target_m`, `unresolved`.

`S2RuntimeResult` fields and types are `command_sequence: int`, `command_kind:
S2RuntimeCommand.Kind`, `status: Status`, `kick_launch: KickLaunch`, `pass_launch: PassLaunch`,
`catch_result: CatchResult`, `pickup_result: PickupResult`, `tackle_result: TackleResult`, and
`detail: String`; `Status` is `{SUCCEEDED=0, REJECTED=1, UNRESOLVED=2}`. `is_success()`, `snapshot()`, and
`static from_snapshot(Dictionary)` are declared. Successful results carry only the payload owned
by their command kind; `command_sequence` and `command_kind` link them to exactly one input.
Resolved records include the existing `KickLaunch`, `PassLaunch`, `CatchResult`, `PickupResult`,
and `TackleResult` types. A successful tick consumes commands and creates linked results; pending
commands carry forward byte-for-value with their original sequence.

All command/result snapshot dictionaries are the existing wire representation. Tests must not
invent additional keys, serialize object addresses, or treat implementation-private keys as
contract. Replay v3 stores each row's ordered command and output snapshots and requires the typed
linkage above.

## 9. Criterion map

Statuses use the inventory's exact authorability labels: `Authorable now`, `Partial`, and
`Wait for S2`. They describe current scope, not evidence that a test exists or passes. Acceptance
behavior and proposed case names remain those in
`.omc/research/s1/test-inventory-fix14-2026-10-14.md`; the inventory remains provisional.

| Criterion | Status | S2 seam portion / retained inventory case |
|---|---|---|
| C-45 | Partial | `test_c45_owner_capture_and_commit_order`; generic owner order is S1, adapter checks are §3 |
| C-46 | Partial | `test_c46_each_phase_failure_restores_full_checkpoint`; S2 runtime snapshot restoration is §2–3 |
| C-47 | Wait for S2 | `test_c47_retry_reuses_sampled_candidate`; exact candidate and port queue retry |
| C-48 | Wait for S2 | `test_c48_append_prepare_failure_and_commit_order`; S1 append/token contract; injected failure branch deferred under §6 |
| C-49 | Wait for S2 | `test_c49_source_exhaustion_and_finished_stop`; typed composition path |
| C-50 | Wait for S2 | `test_c50_current_setup_identity_checked_before_tick`; S1 identity matrix plus S2 setup claims |
| C-51 | Partial | `test_c51_context_outcome_and_clock_delta` |
| C-52 | Wait for S2 | `test_c52_submission_and_port_readback_candidate`; command enqueue/readback |
| C-53 | Partial | `test_c53_capabilities_and_provider_ownership`; S1 owns provider claims, while the S2 adapter owns only port runtime state |
| C-54 | Partial | `test_c54_restore_failure_latches_fatal_stop`; S1 fatal latch plus adapter restore |
| C-55 | Wait for S2 | `test_c55_v3_fatigue_consumed_once`; v3 command/replay codec and owner-derived value once |
| C-56 | Partial | `test_c56_publication_only_after_commit`; S1 publication plus committed log row |
| C-57 | Authorable now | `test_c57_invalid_sim_checked_noop` |
| C-58 | Authorable now | `test_c58_checked_flow_failure_retry` |
| C-59 | Authorable now | `test_c59_fake_result_records_are_constructible` |
| C-60 | Wait for S2 | `test_c60_typed_submission_bundle_detaches`; declared concrete command types and empty bundle |
| C-61 | Partial | `test_c61_versioned_header_and_input_roundtrips`; S1 header rules plus S2 typed v3 rows |
| C-62 | Wait for S2 | `test_c62_runner_replay_current_identity_matrix`; explicit current layout and typed build |
| C-63 | Wait for S2 | `test_c63_runner_terminal_statuses_distinct`; composed runner/rollback path |
| C-64 | Partial | `test_c64_provider_identity_scope_and_fingerprint` |
| C-65 | Partial | `test_c65_setup_claim_validation_and_fingerprint` |
| C-66 | Wait for S2 | `test_c66_direct_replay_identity_and_result_shape`; S1 result shape plus typed fresh build |
| C-67 | Wait for S2 | `test_c67_live_v3_row_atomicity_and_replay_validation`; port/codec/log rollback; injected failure branch deferred under §6 |
| C-68 | Wait for S2 | `test_c68_retryable_and_fatal_runner_failures`; generic failure plus typed runner path |
| C-69 | Wait for S2 | `test_c69_live_replay_share_request_and_clone_graph`; generic factories plus typed port factory; typed-factory spy deferred under §6 |
| C-70 | Wait for S2 | `test_c70_replay_port_reset_after_compatibility`; fake reset rejection/order branch deferred under §6 |
| C-71 | Wait for S2 | `test_c71_live_enqueue_once_and_replay_canonical_commands` |
| C-72 | Wait for S2 | `test_c72_replay_carried_command_and_new_suffix` |
| C-73 | Wait for S2 | `test_c73_prepared_append_authorization`; prepared tick/token pairing |
| C-74 | Wait for S2 | `test_c74_retry_sequence_reset_and_fatal_terminal` |
| C-75 | Partial | `test_c75_replay_row_capability_and_validation_receipt`; rejecting a caller-created inert `ReplaySourceRow` in `MatchSim.begin_replay_row` before checkpoint/port work is S1-authorable; token and log-bound validation cases wait for S2 |
| C-76 | Wait for S2 | `test_c76_direct_replay_fatal_restore_shape`; S1 result shape plus S2 restore |
| C-77 | Partial | Subcases below retain the inventory's individual authorability statuses. |
| C-77a | Wait for S2 | `test_c77a_mutable_owner_system_clones` |
| C-77b | Wait for S2 | `test_c77b_mutable_provider_freshness_and_rollback` |
| C-77c | Partial | `test_c77c_generic_factory_call_count_and_shapes` |
| C-77d | Wait for S2 | `test_c77d_typed_port_factory_and_exact_bindings` |
| C-77e | Wait for S2 | `test_c77e_setup_after_attachment_once` |
| C-77f | Wait for S2 | `test_c77f_claim_match_pre_fingerprint` |
| C-77g | Wait for S2 | `test_c77g_live_graph_immutable` |
| C-77h | Wait for S2 | `test_c77h_independent_repeat_replay` |
| C-77i | Wait for S2 | `test_c77i_stateless_participant_self_reuse` |
| C-77j | Wait for S2 | `test_c77j_stateless_provider_attestation_and_determinism` |
| C-77k | Wait for S2 | `test_c77k_stateless_provider_readonly_consumers` |
| C-77l | Wait for S2 | `test_c77l_provider_duplicate_scope_and_empty_claims` |
| C-77m | Wait for S2 | `test_c77m_port_reset_preserves_provider` |

No case is test evidence until a separate author implements and runs it. Port/codec contracts make
the listed S2 behaviors reviewable; injected-failure branches for C-48/C-67 and fake typed-factory
branches for C-69/C-70 remain deferred under §6 until an independently reviewed test injection
seam exists. Implementation and two independent reviews remain separate gates.
## 10. Open decisions and implementation delta

No open choice in this document changes approved S2 physics behavior. The C-45–C-77 acceptance
behaviors are retained. The contract resolves the seam-level names and value rules for test
authors; it does not assert that missing code exists.

The following implementation work is required before the S2-dependent cases can run: add
`S2RuntimePortOwner`, `S2ProviderBindings`, `S2ReplayInstanceResult`, and `S2ReplayCodec`; make
port snapshots/checkpoints cover queue, results, consumed sequence set, next sequence and failure
state; implement the S1-owned prepared append and replay receipt contracts; wire
`MatchBuildResult.codec`; add the explicit current-layout identity to replay entry points; enforce
factory/setup/compatibility/reset order. Separately reviewed test-only injection seams are still
required for the deferred branches identified in §6.

Open decisions remain deferred for these issues recorded by the S2 API inventory / S1 inventory:

- The exact behavior-complete public observer for S2 post-hit classifier B-12 remains unresolved;
  do not use undocumented classifier internals as an S1 test oracle.
- The interaction ordering conflict remains open until S2-physics specifies the public
  `commands_for_phase()` order as actor/player identity then action sequence. These lifecycle
  criteria assert canonical queue order and carry-forward only; tests must not assert the disputed
  interaction execution order.
- The `physics.wind_provider` callable's exact typed signature remains undeclared; S2 bindings
  here cover the existing contact source and solver only.
- Serialized parser/framing details not fixed by the approved v1/v2/v3 specs remain outside the
  acceptance oracle. Do not expand C-61 from this seam document.

If an implementation proposal requires changing any approved physics outcome, numeric value,
system order, command payload, replay compatibility rule, or S1 transaction boundary, stop that
affected criterion as deferred and obtain an ADR/spec decision before changing this contract.
