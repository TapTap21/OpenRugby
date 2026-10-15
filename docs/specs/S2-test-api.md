# S2 public test API

Status: normative test-facing integration contract for [S2-physics](S2-physics.md) and the
[S1 public test API](S1-test-api.md).
This document defines the S2 adapter and replay seams needed by S1 lifecycle/replay tests. It
does not change physics behavior, numeric values, S1 tick order, or transaction boundaries. The
test inventory remains the acceptance source for C-45–C-77; §9 adds explicitly S2-specific
assertions where that inventory does not yet cover this bridge. Current declarations are listed
as such; a declared method is not evidence that it satisfies this target contract.

## 1. Names and authority

All paths are repository-root relative. Public records below are `class_name` GDScript types.
Published output records are immutable snapshots for documented public fields: constructor arrays
and nested containers are deep-copied, container getters return detached copies, and assignments
after sealing do not change public field values. `_sealed` is private by convention, not
tamper-proof. Records may be mutable while being built or used as command/filter inputs before
publication. Exact provider references are retained only where identity is part of the contract.
Whenever this contract compares typed snapshots, compare the complete typed field structure and
all values exactly; for each floating field, equality means numeric equality or that both values
are NaN. Apply this recursively to nested snapshot values, including output payloads. Do not use
serialized bytes or object addresses as a substitute for typed value comparison.

Ownership is split explicitly. S2 owns its typed codec result and codec-minted wire bundles;
S1 owns generic readback, append, receipt, and replay transaction/candidate values. A dependency
listed as pending below is not approved merely because another S1 candidate mentions it. The
referenced `docs/specs/S1-test-api.md` is absent from this checkout, so its required rows and
factories below are pending S1 documentation/source updates.

| Type | Required path | Status at `c4b5adb` |
|---|---|---|
| `S2RuntimePortOwner` | `game/match/s2_runtime_port_owner.gd` | Missing; required adapter implementing the S1 owner seam |
| `S2OutputSuffixResult` | `game/match/s2_output_suffix_result.gd` | Missing; required typed one-shot staged suffix readback |
| `S2ProviderBindings` | `game/match/s2_provider_bindings.gd` | Missing; required typed factory input |
| `S2ReplayInstanceResult` | `game/match/s2_replay_instance_result.gd` | Missing; required typed factory result |
| `S2ReplayCodec` | `game/match/s2_replay_codec.gd` | Missing; required typed codec |
| `CodecResult` (S2-owned) | `game/match/s2/codec_result.gd` | Pending S2; `{ok: bool, value: Variant | null, error: Error}`; `succeeded(value)` yields `(true, value, OK)`, `failed(error)` yields `(false, null, non-OK)` |
| `EncodedCommandBundle` (S2-owned) | `game/match/s2/encoded_command_bundle.gd` | Pending S2; opaque codec-minted command records, source-bundle identity, exact detached records; no public constructor |
| `PreparedOutputBundle` (S2-owned) | `game/match/s2/prepared_output_bundle.gd` | Pending S2; opaque codec-minted output records bound to exact `PreparedTick` and output identity; no public constructor |
| `CanonicalPortReadback` (S1-owned) | `game/match/canonical_port_readback.gd` | Pending S1; opaque one-read value bound to source row/candidate and exact detached canonical queue; no public constructor or mutable queue getter |
| `CanonicalPortReadbackResult` (S1-owned) | `game/match/canonical_port_readback_result.gd` | Pending S1; `{ok: bool, readback: CanonicalPortReadback | null, command_bundle: DetachedCommandBundle | null, error: Error}`; internal success `(true, readback, bundle, OK)` and public `failed(error)` returning null handles and non-OK |
| `AppendPrepareResult` (S1-owned) | `game/match/append_prepare_result.gd` | Pending S1 update; `{ok: bool, token: PreparedAppendToken | null, error: Error}`; add/document `.prepared(token)` and `.failed(error)` |
| `PreparedAppendToken` (S1-owned) | `game/match/prepared_append_token.gd` | Pending S1; opaque exact-log/row/tick/command/output capability; no caller constructor |
| `CandidateEnqueueLease` (S1-owned) | `game/match/candidate_enqueue_lease.gd` | Pending S1; opaque runner-issued one-use capability bound to exact port, pre-enqueue snapshot, candidate, and lifecycle; no caller constructor or inspectable snapshot |
| `ReplayValidationResult` (S1-owned) | `game/match/replay_validation_result.gd` | Pending S1; `{ok: bool, token: ReplayValidationToken | null, error: Error}`; internal success `(true, token, OK)` and public `failed(error)` |
| `ReplayValidationToken` (S1-owned) | `game/match/replay_validation_token.gd` | Pending S1; opaque exact-row validation receipt; no caller constructor |
| `ReplayRowTransaction` (S1-owned) | `game/match/replay_row_transaction.gd` | Pending S1; opaque; internally bound to sim generation, log-issued source-row identity, monotonic attempt ID, full sim/owner checkpoint, opened owner transaction, and one-use lifecycle state; no caller constructor or inspectable checkpoint payload |
| `ReplayRowBeginResult` (S1-owned) | `game/match/replay_row_begin_result.gd` | Pending S1; `{ok: bool, transaction: ReplayRowTransaction | null, error: Error}`; internal success, public `failed(error)`; success `(true, transaction, OK)`, failure `(false, null, non-OK)` |
| `ReplayCandidate` (S1-owned) | `game/match/replay_candidate.gd` | Pending S1; opaque immutable; bound to transaction, source-row identity, attempt ID; stores detached frame, exact full S2 typed command bundle, validated contiguous new suffix, and exact canonical readback; no public constructor |
| `ReplayCandidateResult` (S1-owned) | `game/match/replay_candidate_result.gd` | Pending S1; `{ok: bool, candidate: ReplayCandidate | null, error: Error}`; internal success `(true, candidate, OK)`, public `failed(error)` returns `(false, null, non-OK)` |

Already declared in this worktree are `S2RuntimePort` at `game/match/s2_runtime_port.gd`,
`S2RuntimeCommand` at `game/match/s2_runtime_command.gd`, `S2RuntimeResult` at
`game/match/s2_runtime_result.gd`, `S2PlayerTickInput`, `PlayerFatigueSnapshot`,
`S2BallInitialization`, `S2PlayerInitialization`, and `S2WindPolicy` under
`game/physics/state/`, plus `MatchBuildResult` and `MatchReadinessReport`. Section 8 names the
concrete declared payload fields. Their present signatures do not supply the missing adapter,
codec, append, or replay guarantees. All tabled types are pending until their owning slice
documents and implements them. S1 must add every S1-owned row above to its public test API; the
three S2-owned codec types above must be added by S2. `AppendPrepareResult` currently has only a
positional constructor in S1; its named factories are a required pending S1 update.

## 2. `S2RuntimePort` test seam

Path/class: `game/match/s2_runtime_port.gd`, `class_name S2RuntimePort extends RefCounted`.
The declared public calls used by this contract are:

```gdscript
func enqueue(command: S2RuntimeCommand) -> int
func queued_command_snapshots() -> Array[Dictionary]
func results() -> Array[S2RuntimeResult]
func results_since(first_index: int) -> Array[Dictionary]
func commands_for_phase(phase: S2RuntimeCommand.Phase) -> Array[S2RuntimeCommand]
func enqueue_replay_commands(values: Array[Dictionary]) -> bool
func setup_snapshot() -> Dictionary
func snapshot() -> Dictionary
func begin_tick(candidate_frame_tick: int, candidate_attempt_id: int,
        candidate_commands: Array[S2RuntimeCommand]) -> bool
func begin_replay_row(candidate_frame_tick: int, candidate_attempt_id: int) -> bool
func enqueue_validated_replay_commands(commands: Array[S2RuntimeCommand]) -> bool
func seal_replay_candidate(commands: Array[S2RuntimeCommand]) -> bool
func tick_succeeded() -> bool
func commit_tick() -> bool
func rollback_tick() -> void
func complete_command(command: S2RuntimeCommand,
        consumer_phase: S2RuntimeCommand.Phase, result: S2RuntimeResult) -> bool
func take_staged_output_suffix(candidate_frame_tick: int,
        candidate_attempt_id: int) -> S2OutputSuffixResult
func reset_runtime() -> bool
```

`S2OutputSuffixResult` is the S2-owned typed one-shot readback value at
`game/match/s2_output_suffix_result.gd`, with fields in this order:
`ok: bool`, `results: Array[S2RuntimeResult]`, `error: Error`. Success is `(true, detached ordered
results, OK)` and may contain an empty suffix; failure is `(false, [], non-OK)`. Its `results`
property returns a detached typed array of immutable published values.

### Queue and result rules

`enqueue` accepts one valid command whose `sequence == -1`, assigns the current non-negative
`next_sequence`, increments `next_sequence` once, and returns the assigned sequence. It returns
`-1` for a null/invalid command, an explicitly assigned sequence, or a command rejected by
validation; rejection leaves the complete runtime snapshot unchanged. The accepted command is
detached from the caller and appended to the pending queue. A test fake follows these same rules.

`S2RuntimeCommand.detached_copy() -> RefCounted` returns a distinct command object of the same
concrete script type with every public command field preserved. `queued_command_snapshots()` returns a detached ordered copy of the full pending command queue.
Each dictionary is exactly `S2RuntimeCommand.snapshot()` for that command; it is not a second
command schema. `commands_for_phase(phase)` returns detached typed command copies, in canonical
queue order, for that fixed phase, excluding commands consumed in the active transaction; no
producer receives a mutable reference to the canonical queue. `results()` returns detached typed
immutable copies of all results retained by the port.
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

`enqueue_replay_commands(values)` is a compatibility-only legacy entry point, not used by the S2
replay path. Its sole allowed caller is the legacy replay importer before a checked S1 transaction
exists; it decodes every dictionary to a valid typed command, applies the carried-prefix and
contiguous-new-suffix rules below, and is forbidden during an active/staged transaction. New S2
replay code passes typed `S2RuntimeCommand` values only. This legacy method is the only raw-dictionary
compatibility boundary. The shared coordinator in §3 uses `begin_replay_row`,
`enqueue_validated_replay_commands`, and `seal_replay_candidate`. `begin_replay_row(frame_tick,
attempt_id)` snapshots the complete pre-row port state and freezes the primitive frame tick and
monotonic attempt ID while leaving the queue unchanged. `enqueue_validated_replay_commands`
accepts only the validated new suffix as detached typed `S2RuntimeCommand` values, validates
contiguous sequence assignment, and injects atomically. The one canonical full-queue read is
compared with the row before `seal_replay_candidate(commands)` freezes candidate membership and
the result baseline for system execution. Replay does not call live `begin_tick`; abort ownership
and ordering are defined in §3.

The older `enqueue_replay_commands(values)` declaration receives the full pending-queue row from
the replay log, not only its newly introduced suffix. It succeeds only if every dictionary decodes as a valid
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

`begin_tick(candidate_frame_tick, candidate_attempt_id, candidate_commands)` is called exactly once by the owner after
it has compared S1's complete ordered `context.commands` candidate to the port's complete
canonical pending queue. It snapshots the full pre-tick runtime state and freezes the primitive
0-based candidate frame tick, S1-assigned monotonically increasing attempt id, tick-start results
index, and per-sequence canonical typed snapshot, kind, and phase for every candidate, including
carried commands. The attempt id is opaque transaction identity: it is not rewound after abort and
is excluded from deterministic runtime snapshots and hashes. Candidate sequences must be unique.
Invalid arguments, duplicate sequences, an existing active transaction, or an existing
staged transaction whose S1 finalization has not completed return `false` without opening or
changing the transaction. `tick_succeeded()` is true only while a transaction is active and no
S2 command/system failure has occurred.

`commit_tick()` is called once after systems and S1 flow staging succeed. It returns `true` only if
the active transaction has no failure and the current-tick consumed sequence set is in bijection with
the appended result suffix beginning at the captured tick-start index: each consumed candidate has
exactly one successful result with the frozen sequence and kind, and every suffix result maps to
exactly one consumed candidate. The pending queue must equal the original-order projection of the
frozen candidates that remain unconsumed. Every unconsumed candidate therefore remains pending
with its original sequence and full typed value and has no result. A malformed, rejected, unresolved, missing,
duplicate, or extraneous result makes commit fail as an S2 tick failure; S1 publishes no outputs
and aborts. A successful commit marks the transaction staged for codec validation, but retains the
pre-tick snapshot and all candidate/baseline state so S1 can abort through output validation, row
preparation, and finalization. In particular, `commit_tick()` must not discard rollback state.

`take_staged_output_suffix(candidate_frame_tick, candidate_attempt_id)` succeeds only once for the
staged transaction whose frozen integer frame tick and attempt id equal the argument pair. It
returns exactly the ordered result suffix
from the captured tick-start index without removing or reordering retained results. Missing or
unstaged state, failed transaction, wrong/stale tick, or a repeated read returns `(false, [],
non-OK)` and does not change queue or result history. The lease-used state is part of rollback state.
Attempt identity prevents a stale prepared handle from consuming a retry's otherwise identical
frame suffix.

For a live transaction after a real `PreparedTick` exists, the sole S1 abort route is
`MatchSim.abort_prepared_tick(prepared_tick)`, which invokes the registered
`S2RuntimePortOwner.restore(checkpoint)`; no runner, codec, system, or producer calls
`rollback_tick()` directly. Before a live enqueue, the runner obtains an opaque one-use
`CandidateEnqueueLease` bound to the exact port, pre-enqueue snapshot, candidate, and lifecycle.
For any pre-tick enqueue/readback/sealing failure, the S2 owner consumes that lease once, restores
and verifies the exact snapshot, and rejects reuse. This lease path is separate from replay's
`abort_replay_row(transaction)` and prepared-tick rollback, so no path can restore the port twice.
The adapter checkpoint contains only a complete immutable copied runtime snapshot and no
external `Object` reference. The adapter's one-time nonreplaceable `_port` attachment
binds identity. Adapter `restore` uses that fixed attachment, calls `port.rollback_tick()` exactly
once when its nested transaction is open, then compares the resulting snapshot to the checkpoint
value. It returns `OK` only on exact restoration; a mismatch returns non-OK and S1 latches terminal
`FATAL_ROLLBACK`. If capture failed before `begin_tick` or replay begin opened no nested port
transaction, `rollback_tick()` is a no-op and restore still requires exact snapshot equality. This
no-op applies only when no nested port transaction was opened. Rollback clears the active candidate,
candidate membership map, result baseline, staged suffix state, and all issued-command references.
The exact S1 candidate frame and commands remain available to S1 for a retry; a retry therefore
recreates the same sequence and output suffix once with a fresh attempt id. A rollback without a
retained transaction is a no-op. Only a later capture after the prior S1 commit boundary has
completed may retire the prior rollback snapshot and replace the candidate state. Historical
results remain in append/completion order until `reset_runtime()`; a later tick's suffix always
starts at its own captured result index, so older results never leak into that tick's output.
The outer S1 transaction owns call order and invokes restore after every later-system, output
preparation, row-preparation, or other pre-finalization failure.

Every active `commands_for_phase(phase)` call returns newly detached copies in canonical queue
order and registers each exact returned Object reference as issued by this port. The port retains
issued references and frozen expected snapshots keyed by candidate sequence and phase.
`complete_command(command, consumer_phase, result)` returns `true` only when there is an active,
non-failed transaction; the sequence is a member of the frozen candidate map; Godot `is_same()`
confirms `command` is one of the exact detached references issued by this port for that
sequence/phase; its full typed snapshot equals the frozen expected snapshot; the command phase and
`consumer_phase` both equal the frozen expected phase; the sequence is still pending and has not
already been consumed or emitted; and the result is a valid successful result with exactly the
payload required for the frozen command kind. `is_same()` is the documented reference identity
check for Objects. A public constructor/from-snapshot command with byte-identical values, or a
command issued by another port, fails identity validation. Completion assigns result sequence and
kind from the frozen candidate, never from producer fields. It returns `false` for wrong phase,
nonmember, altered, foreign, duplicate, malformed, rejected, or unresolved input, appends no
result, and marks the active S2 tick failed so the owner cannot commit it. The fixed built-in
producer call sites pass statically assigned phase constants. This seam is scoped to trusted fixed
built-in producer call sites: the phase argument is only a claim and does not authenticate the
calling system. Only trusted built-in producer implementations with statically fixed phase
ownership may receive the raw port and call `complete_command`. Mods, extension callbacks, and
other callers receive neither the port nor owner reference and have no route to call completion.
Issued references are cleared on commit, rollback, and transaction retirement.

`reset_runtime()` clears pending commands, retained results, consumed sequences, failure detail,
and failure sequence; resets `next_sequence` to zero; and sets `tick_failed` to `false` (the
internal `_tick_failed` state is also reset). It does not change providers, initialized ball/player
setup, wind policy, pitch/fatigue environment, attached systems, or setup identity. It returns
`true` after reset. A fake may return `false` to represent a checked reset rejection; that is an
ordinary failure result and must leave the complete runtime snapshot, including `tick_failed`,
unchanged.

For checked failures, port fakes use the declared `-1`/`false` results and preserve state as
specified; codec failures use the S2 `CodecResult` shape and append failures use the S1
`AppendPrepareResult` shape.
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
func restore_candidate_reservation(lease: CandidateEnqueueLease) -> Error
func setup(sim: MatchSim) -> SetupResult
func capture_tick(context: SimTickContext) -> OwnerCaptureResult
func begin_replay_row(source_row: ReplaySourceRow, candidate_frame_tick: int,
        candidate_attempt_id: int) -> OwnerCaptureResult
func capture_replay_candidate(context: SimTickContext,
        commands: DetachedCommandBundle,
        canonical_port_readback: CanonicalPortReadback) -> OwnerCaptureResult
func commit_tick(context: SimTickContext, capture: OwnerCapture,
        outcome: SimTickOutcome) -> OwnerCommitResult
func checkpoint() -> CheckpointResult
func restore(checkpoint: Variant) -> Error
func create_replay_instance() -> ReplayInstanceResult
```

`restore_candidate_reservation(lease)` is the sole live pre-tick rollback entry point: the runner
issues an opaque one-use `CandidateEnqueueLease` bound to the exact attached port, exact
pre-enqueue snapshot, and exact candidate; the owner consumes it once, restores through that
attachment, verifies complete snapshot equality, and returns `OK` only on exact restoration. A
stale, foreign, or reused lease returns an error without a second restore. It is never used by
replay or by `abort_prepared_tick`.

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

`capture_tick` first reads the complete canonical pending queue and enumerates every S1
`context.commands.records_in_order()` item, which returns `Array[RefCounted]` defensive copies in
order. It validates and casts every record as `S2RuntimeCommand`, then builds an
`Array[S2RuntimeCommand]` in the same order for `S2RuntimePort.begin_tick`; the S1 bundle type
never crosses the port boundary. It compares the complete typed candidate to the complete
canonical pending queue by full typed command snapshots, including length, order, sequence, kind,
phase, and every payload field, using the NaN-aware exact comparison defined in §1. It rejects any
non-command item, duplicate sequence, altered value, foreign command, or length/order mismatch
with a failed `OwnerCaptureResult`, without changing port state or opening a nested transaction.
Only after this comparison succeeds does the adapter call
`begin_tick(context.candidate_frame.tick, context.candidate_attempt_id,
typed_candidate_commands)`; the frame `tick` is the primitive 0-based integer and the attempt id
is S1 transaction identity. S1 allocates one monotonically increasing id when a live checked
attempt opens. For replay, S1 allocates it at `begin_replay_row()` and carries that same id into
`tick_replay_row()` and the resulting `PreparedTick`/owner context. Abort does not rewind the id;
it is excluded from deterministic snapshot/hash state. The port freezes the candidate map, result
baseline, and attempt pair at tick start. `commands_for_phase()` returns detached typed commands,
so a producer cannot mutate the canonical queue after capture.

The S1 dependency is normative even where the current S1-core text is older: S1 allocates
`candidate_attempt_id` at live attempt or replay-row opening, carries it through `SimTickContext`
and `PreparedTick`, and excludes it from snapshots, hashes, and serialized replay. S1 must expose
`DetachedCommandBundle.records_in_order() -> Array[RefCounted]`, returning fresh detached values
in stable order. `PreparedTick.outputs` must contain the exact detached, ordered validated output
values successfully returned by checked systems; an empty placeholder output array does not meet
this dependency. Until S1 API/source implements these guarantees, S2 implementation is blocked.

For replay, the adapter's owner-begin and candidate-seal callbacks implement the port operations
from §2 and receive the exact transaction/readback objects from the single §3 coordinator. They
do not open another transaction, take another checkpoint, or read the port a second time.
Pre-handle failures use `MatchSim.abort_replay_row(transaction)`; a later failure uses
`MatchSim.abort_prepared_tick(prepared_tick)` only after a real prepared handle exists. Both
restore routes are one-use and cannot restore the port twice.

`commit_tick(context, capture, outcome)` reports successful S2 work only after systems and S1
flow staging succeed. Before it succeeds, the adapter requires the consumed-sequence/result-suffix
bijection specified in §2; an unresolved or malformed result, missing/extra result, or duplicate
sequence rejects owner commit and fails the S2 tick. It leaves the port state restorable through
output validation, row preparation, and sim finalization; S1 can still abort and restore after an
owner commit. `checkpoint()` and `restore(checkpoint)` implement the generic S1
participant checkpoint contract over that same complete snapshot. Failed capture/commit/
checkpoint/restore uses the exact S1 checked result/error shape. Restore failure is fatal rollback
per S1. Neither the generic capture nor checkpoint exposes the port's internal dictionary by
mutable reference.

Replay needs an explicit S1 dispatch path; the S2 owner method alone is not callable by the
current generic owner protocol. The following are required S1 signatures, unapproved until the
separate S1 candidate is reviewed:

```gdscript
# S1-owned opaque replay transaction/result and candidate/result rows (all pending S1 updates).
# MatchSim opens transaction and dispatches the generic owner begin hook before injection.
func begin_replay_row(source_row: ReplaySourceRow) -> ReplayRowBeginResult
# MatchRunner/codec coordinator packages the validated row candidate and exact readback.
func capture_replay_candidate(transaction: ReplayRowTransaction, frame: InputFrame,
        command_bundle: EncodedCommandBundle, new_suffix: Array[RefCounted],
        canonical_port_readback: CanonicalPortReadback) -> ReplayCandidateResult
# Runs checked systems against the already-open transaction; creates PreparedTick only on success.
func tick_replay_row(transaction: ReplayRowTransaction,
        candidate: ReplayCandidate) -> TickResult
# One-use rollback for any pre-PreparedTick replay failure, including C-67 extensions.
func abort_replay_row(transaction: ReplayRowTransaction) -> Error
```

`ReplayRowTransaction` is internally bound to the sim generation, log-issued source-row identity,
monotonically allocated attempt ID, full sim/owner checkpoint, opened owner transaction, and a
one-use lifecycle state. Callers cannot construct it or inspect its checkpoint. `ReplayCandidate`
is immutable and bound to that transaction, source-row identity and attempt ID; it retains the
detached frame, exact full typed command bundle, validated contiguous new suffix, and exact
canonical readback. `capture_replay_candidate` verifies all linkage and invokes the registered
S2 owner seal callback exactly once, passing through the same readback object. The coordinator
does not invoke another seal callback. The candidate retains that readback unchanged.

Runner-driven replay and direct `MatchReplay.run` use the same coordinator implementation and
share one normative ordering: call `InputLog.read_replay_row(index)` once for the current row;
call `MatchSim.begin_replay_row(source_row)` to validate provenance, allocate a nonrewinding
attempt ID, capture full sim/owner checkpoints, then dispatch
`SimTickOwner.begin_replay_row(source_row, candidate_frame_tick, candidate_attempt_id)` to open the
S2 port transaction before any command validation/injection; validate the row against current
pending commands and prepare only its typed contiguous new suffix; atomically enqueue that suffix
under an exact one-shot reservation/lease; call
`S2ReplayCodec.capture_canonical_port_readback(port)` exactly once for the full canonical queue;
package and pass that same readback to
`MatchSim.capture_replay_candidate(transaction, frame, command_bundle, new_suffix,
canonical_port_readback)`, which invokes the registered S2 owner seal hook once; then call
`MatchSim.tick_replay_row(transaction, candidate)` to run checked systems against the original
checkpoint and attempt. There is no second port read, `begin_tick`, or checkpoint. A failed
`tick_replay_row` restores this replay transaction exactly once before returning its failed
`TickResult`; no live pre-tick enqueue lease is used for replay. Any failure before a real
`PreparedTick` exists calls `abort_replay_row(transaction)`. Only failures after a real prepared
tick exists may call `abort_prepared_tick(prepared_tick)`.

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
The result/bundle types below retain their exact canonical signatures and ownership rules; the
codec result and both codec-minted bundles are S2-owned, while generic append/readback/receipt
values are S1-owned.
The codec is bound once to the same exact `S2RuntimePort` instance held by the owner and producers:

```gdscript
func attach_port(port: S2RuntimePort) -> Error
```

It rejects null, repeated, or later-replaced port attachments. `prepare_outputs` uses only this
attached port for the staged suffix readback.

Required S1 codec methods implemented by the S2 codec are:

```gdscript
func prepare_commands(command_bundle: DetachedCommandBundle) -> CodecResult
func decode_commands(records: Array[Dictionary]) -> CodecResult
func decode_outputs(records: Array[Dictionary]) -> CodecResult
func prepare_outputs(prepared_tick: PreparedTick) -> CodecResult
func encode_commands(command_bundle: EncodedCommandBundle) -> Array[Dictionary]
func encode_outputs(output_bundle: PreparedOutputBundle) -> Array[Dictionary]
func capture_canonical_port_readback(port: S2RuntimePort) -> CanonicalPortReadbackResult
func validate_replay_row(prepared_tick: PreparedTick, source_row: ReplaySourceRow,
        canonical_port_readback: CanonicalPortReadback) -> ReplayValidationResult
```

`DetachedCommandBundle.records_in_order() -> Array[RefCounted]` returns new detached command
values in stable order. `PreparedTick` retains `candidate_attempt_id` and the exact detached,
ordered validated output values successfully returned by checked systems in `outputs`; an empty
placeholder array is incomplete. The attempt ID is allocated monotonically at live attempt or
replay-row opening, carried through owner context and `PreparedTick`, and excluded from
deterministic snapshots, hashes, and serialized replay. S1 API/source must implement these
guarantees before S2 implementation can proceed.

`prepare_commands` returns a `CodecResult` containing the opaque `EncodedCommandBundle` bound to
the exact source `DetachedCommandBundle` and detached v3 records. S1's `PreparedTick` retains
that exact command candidate identity, so the encoded command bundle is paired with the same
`PreparedTick` used for output preparation and append. `prepare_outputs` returns the
opaque `PreparedOutputBundle` bound to that exact `PreparedTick`. The exact
`EncodedCommandBundle` and `PreparedOutputBundle` values are passed with the exact `PreparedTick`
to `InputLog.prepare_append`; raw `Array[Dictionary]` or untyped `Array` substitutes are
forbidden at this identity boundary. `encode_commands` and `encode_outputs` consume only their
respective typed bundles. Decode calls return the
appropriate existing concrete S2 typed values in `CodecResult`; malformed records produce a
non-OK result and no partial bundle. For `decode_outputs`, any record whose status is not
`Status.SUCCEEDED` is malformed under this output contract. `prepare_outputs(prepared_tick)` reads
the exact retained candidate frame through the existing `PreparedTick.candidate_frame` property;
that accessor returns the copied frame and its `tick` is the candidate's 0-based integer. It calls
the exact shared port's
`take_staged_output_suffix(candidate_frame_tick, prepared_tick.candidate_attempt_id)` once. Before any payload
or status validation, it compares the returned suffix to `prepared_tick.outputs` by equal length
and, at each index, complete typed `S2RuntimeResult.snapshot()` equality using the NaN-aware
comparison in §1. This rejects fabricated,
missing, duplicate, reordered, stale, or otherwise mismatched records and consumes the staged
suffix lease only on a successful one-shot read. It then validates each output against the S2 typed
output contract in §8, including successful status and kind-specific payload shape, and returns the
opaque `PreparedOutputBundle` paired with that tick. No method accepts a caller-supplied output
array to mint a prepared bundle. `encode_outputs` consumes only that bundle. The port stores no S1
types; its staged readback key and candidate-frame binding are primitive `int` values. Replay
row-to-command and expected-output linkage remains independently checked by `validate_replay_row`.

`capture_canonical_port_readback(port)` reads the full pending queue exactly once, validates and
decodes those canonical records, and returns the S1 `CanonicalPortReadbackResult` with fields
`ok: bool`, `readback: CanonicalPortReadback | null`,
`command_bundle: DetachedCommandBundle | null`, and `error: Error`. Failure returns no readback
or bundle. The opaque readback identity is paired with those exact decoded commands; copying an
array or reading the port again cannot create an equivalent authority.

`validate_replay_row` obtains the exact typed command and validated output identities from
`PreparedTick`; it validates the exact `ReplaySourceRow`, carried/new sequence rules, canonical
readback, command/output linkage, and expected outputs against generated outputs on the
`PreparedTick`. Each output must link to exactly one command in that row by sequence and kind and
must have `Status.SUCCEEDED`. It returns the S1 `ReplayValidationResult` `{ok, token, error}`. The
codec's receipt mint operation is private to this validation path and the build-owned authority; there is
no public `mint_replay_receipt`, arbitrary output-array input, or caller-supplied success boolean.
Only a successfully validated exact row can produce the opaque registered
`ReplayValidationToken` consumed by `MatchSim.finalize_replay_tick`.

V3 commands and outputs retain the existing snapshot field names, kinds, order, and meanings. A
row is valid only when each output refers to exactly one command with the same sequence and kind,
has `Status.SUCCEEDED`, and generated output records equal the recorded expected records. Tests use
the S2 `CodecResult`,
`CanonicalPortReadbackResult`, and `ReplayValidationResult` contracts; they must not invent
parallel result shapes or inspect private authority state.

## 6. Prepared append and capability pairing

`InputLog` uses the S1-owned prepared append API:

```gdscript
func prepare_append(prepared_tick: PreparedTick, command_bundle: EncodedCommandBundle,
        output_bundle: PreparedOutputBundle) -> AppendPrepareResult
func commit_append(token: PreparedAppendToken) -> Error
func cancel_append(token: PreparedAppendToken) -> Error
```

The return type is the S1 `AppendPrepareResult` with `{ok, token, error}` and named
`.prepared(token)` / `.failed(error)` factories. The
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

A deterministic checked output-preparation failure is an ordinary non-OK S2 `CodecResult`; a
row-preparation failure is an ordinary non-OK `AppendPrepareResult`, both before finalization.
S2 provides `CodecResult` at `game/match/s2/codec_result.gd`, with
`{ok: bool, value: Variant | null, error: Error}`, `succeeded(value)`, and `failed(error)`.
S1 must add/document the `AppendPrepareResult` factories above; its current positional
constructor is not the named factory contract. `commit_append(token) -> Error` returns `OK` only
after valid publication and an error for an invalid capability. Allocation failure and
production failure toggles are not test inputs. The following exact S1 `MatchRunner` signatures
are unapproved dependencies because current S1 source has neither method. Tests subclass S1
`MatchRunner` and override only
these private-by-convention seams:

```gdscript
func _prepare_output_bundle(prepared_tick: PreparedTick) -> CodecResult
func _prepare_log_append(prepared_tick: PreparedTick,
        command_bundle: EncodedCommandBundle,
        output_bundle: PreparedOutputBundle) -> AppendPrepareResult
```

Production methods delegate to the build-owned codec and `InputLog`. The test codec subclass calls
`super`, performing the actual one-shot suffix read, comparison, and output validation, then returns
`CodecResult.failed(error)` exactly once. The append subclass calls the real append reservation via
`super`, cancels that reservation, then returns `AppendPrepareResult.failed(error)` exactly once.
Both follow `MatchSim.abort_prepared_tick(prepared_tick)` and restore only through
`S2RuntimePortOwner.restore(checkpoint)`. This runner subclass seam leaves production composition
unchanged: production `_prepare_output_bundle` delegates to the build-owned `S2ReplayCodec`, and
production `_prepare_log_append` delegates to the exact `InputLog.prepare_append`. C-69's
typed-factory spy/failure
branches and C-70's fake reset-rejection/order branch remain deferred because the current static
typed factory has no public fake-factory injection point. Real successful factory/reset behavior
and ordinary invalid-input validation remain specifiable without that injector.

## 7. S1 transaction order retained

Live S2 order: poll/fill once and seal the detached typed submission bundle; validate/encode that
bundle before enqueue; then issue an opaque runner-issued enqueue lease bound to the exact port,
pre-enqueue snapshot, and candidate. Enqueue each submitted command once; read the canonical full
pending queue exactly once through `capture_canonical_port_readback`; use its paired detached
command bundle as the tick candidate; verify its assigned sequence values against successful
preflight encoding; then call `MatchSim.tick_checked(frame, command_bundle)`. Partial enqueue,
enqueue failure, assigned-sequence mismatch, readback failure, or sealing failure before
`tick_checked` opens must restore through the S2 owner exactly once using that lease and verify
exact restoration. A preflight validation/encoding failure has no `PreparedTick` or sim
checkpoint, so it must not call `abort_prepared_tick`. The lease is one-use and covers live
pre-tick work only; replay never uses it. The lease restore path must not also be used by
`abort_replay_row` or `abort_prepared_tick`, preventing a double restore of the same port. Keep
the exact sampled frame and typed commands for retry, and never re-enqueue or renumber until exact
restoration succeeds. This pre-tick path does not claim a live `begin_tick` was opened. The prepared tick's own detached typed, pre-codec
`TickResult.outputs` are the sole source for
`prepare_outputs(prepared_tick)`, which validates them under §8 before encoding via
`encode_outputs(prepared_output_bundle)` and
`InputLog.prepare_append(prepared_tick, encoded_command_bundle, prepared_output_bundle)` while the
tick remains abortable. The owner and port retain their pre-tick rollback state through all of this
work and through sim finalization.

If any checked phase or fallible preparation fails after a prepared handle exists and before
finalization, abort that prepared tick,
cancel any prepared append token, and restore the sim, generic owners/providers, and complete S2
port snapshot, including `_tick_failed` and its observable `tick_failed` snapshot value. Keep the
exact sampled frame, typed candidate, and already assigned port sequences for explicit retry; do
not poll, enqueue, or assign replacement sequences again. On success,
`MatchSim.finalize_prepared_tick(prepared_tick, append_token)` and
`InputLog.commit_append(append_token)` are infallible, allocation-free, and callback-free, with no
callback between them. The complete row is visible before staged MatchSim signals, EventBus relay,
and `ticked` last. A retryable failure publishes no row, output, or signal; a restore failure is
fatal under S1.

Replay startup builds fresh participants/providers/port, checks the v3 header against current
request identity, and resets the fresh port exactly once after compatibility. Per row, all calls,
arguments, order, candidate sealing, and rollback behavior are the single coordinator algorithm
in §3. The coordinator and `MatchSim` perform the exact command/output validation represented by
`validate_replay_row(prepared_tick, source_row, canonical_port_readback)`; the codec obtains
command and output identities from `PreparedTick`. Only the successful S1
`ReplayValidationResult` can carry the private-minted receipt. Finalize with
`MatchSim.finalize_replay_tick(prepared_tick, token)` and publish events only after success;
replay never appends to its source log. Any failure before a prepared handle exists calls
`abort_replay_row(transaction)`; only a failure after a real prepared handle exists calls
`abort_prepared_tick(prepared_tick)`. Fatal restore failure is distinct from retryable tick failure
and latches the sim stopped. `MatchReplay.run` and runner-driven replay use this same coordinator,
so validation, receipt, finalization, and event-publication order has one implementation.

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
`static from_snapshot(Dictionary)` are declared. Only records whose `status == Status.SUCCEEDED`
may appear in a successful `SystemTickResult.outputs`, `PreparedTick.outputs`, or v3
`runtime.outputs` row. A rejected or unresolved command outcome fails the active S2 tick and is
not appended as an output; the enclosing S1 transaction rolls back the tick. Successful results
carry only the payload owned by their command kind.

Successful payload validation uses these existing result rules: `PLAYER_TICK_INPUT` and
`BALL_STATE` have no payload record; `KICK` has only a resolved `kick_launch`; `PASS` has only a
resolved `pass_launch`; `CATCH` has only a resolved `catch_result` whose outcome is `CAUGHT` or
`DROPPED`; `FUMBLE` has only a resolved `catch_result` with finite probability and outcome
`CAUGHT` or `FUMBLED`; `PICKUP` has only a `pickup_result` whose outcome is not `UNRESOLVED`; and
`TACKLE` or `SPILL` has only a resolved `tackle_result`. No successful result may carry a payload
owned by another kind. These checks apply before copy-on-publication and again to decoded successful
outputs.

Production linkage is checked first by `complete_command(command, consumer_phase, result)` against
the active frozen candidate map and issued-reference registry, as specified in §2, and then
independently at the codec boundary. Only the exact command object issued by the same shared port
may complete; a same-sequence byte-identical command from another port or an altered copy fails.
The port stamps sequence and kind from the
frozen canonical entry and accepts at most one successful completion per consumed sequence.
`S2ReplayCodec.prepare_outputs` then compares the complete ordered staged port suffix to the
aggregate `PreparedTick.outputs` by typed snapshot value, so caller-created, missing, duplicate,
reordered, stale, or payload-mismatched aggregate records cannot pass merely because the producer
path is trusted. Replay independently checks each output against the exact row's commands in
`validate_replay_row` (§5).

Resolved records include the existing `KickLaunch`, `PassLaunch`, `CatchResult`, `PickupResult`,
and `TackleResult` types. Before publication through a port result readback or as an S1 output,
`S2RuntimeResult` and its active nested payload must be immutable after publication. In
`complete_command`, first validate the mutable producer-owned result and its active payload; then
construct a detached typed copy with canonical command sequence/kind already assigned, seal that
copy and its active payload, and append only the sealed copy. Do not stamp or seal the producer's
pre-sealed value, and do not freeze or mutate any producer-owned alias. Construction and
producer/filter use before publication remain mutable. Keep the declared public field names and
types: before publication, field assignment updates the builder; after publication, assignment to
a documented public outer field or active payload field is a deterministic no-op that leaves the
published value unchanged. This is application-level protection for documented public fields;
`_sealed` is private by convention and is not tamper-proof. `results()` and producer suffix arrays
expose immutable published values; decoded successful outputs are also immutable. Detached arrays
may safely share those immutable record references. Detached arrays alone do not establish record
immutability. `snapshot()` dictionaries and their nested containers remain detached mutable copies.

`PassLaunch` and command/filter construction remain mutable before publication; in particular,
builders, `S2RuntimeCommand.pass()`, pass assist, and extension filters must be able to construct
and update unpublished launch values. Seal only the detached result copy when a successful result
crosses the output publication boundary. `KickLaunch`, `PassLaunch`, `CatchResult`, `PickupResult`,
and `TackleResult` follow the same boundary rule when active payloads. Their active payload graph
has at most the one payload record directly held by `S2RuntimeResult`; payload vector values are
value types, while snapshot dictionaries/arrays are fresh mutable containers. The mutable public
fields in declarations at `c4b5adb` describe current declaration state and do not satisfy this
target until copy-on-publication and sealing semantics are implemented. This contract preserves
declared signatures and v3 wire fields and values; it adds no fields or wire behavior. Pending
commands carry forward byte-for-value with their original sequence.

### Producer bridge and output order

Each S2 system that consumes commands implements the S1 `tick_checked(sim, context) ->
SystemTickResult` method and is a producer of its own successful command outputs through
`SystemTickResult.outputs`; it does not rely on the default legacy `tick(sim)` adapter, which returns
no outputs. Immediately before consuming commands, the system records the current result count from
the exact shared `S2RuntimePort` attached to the owner and used for those commands. For each
successful completion, that same port's `complete_command` assigns sequence/kind from the exact
consumed command and appends once. After processing, the newly appended suffix from that same port,
in original completion order, is exactly the set returned by the producer in a successful
`SystemTickResult.outputs`; no older result or other output is included. The producer obtains that
suffix from detached typed `results()` readback, preserving the existing result records and fields.
If command processing fails, the system returns the S1 failure `SystemTickResult` with no outputs;
the outer S1 rollback removes provisional results added during this tick.

The generic registry invokes systems sequentially in registered order. `MatchSim` concatenates each
successful `SystemTickResult.outputs` in that registry order, preserving each system's completion
order, into `PreparedTick.outputs` and `TickResult.outputs`. Thus each successful
`Status.SUCCEEDED` result produced by `complete_command` appears once in the port result queue and
once in the aggregate tick outputs;
the `S2RuntimePortOwner` only checkpoints/restores port state and emits no `SystemTickResult`
outputs, so it cannot duplicate them. `prepare_outputs` validates and encodes this aggregate once;
`validate_replay_row` separately checks row/output linkage and expected-output equality.

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
| C-45 | Partial | `test_c45_owner_capture_and_commit_order`; generic owner order is S1, adapter checks are §3. S2 output ordering extension is specified below and is not covered by this generic case. |
| C-46 | Partial | `test_c46_each_phase_failure_restores_full_checkpoint`; S2 runtime snapshot restoration is §2–3. S2 provisional-output rollback extension is specified below and is not covered by this generic case. |
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
| C-59 | Authorable now | `test_c59_fake_result_records_are_constructible`; this generic construction case does not cover S2 published-record immutability, specified below. |
| C-60 | Wait for S2 | `test_c60_typed_submission_bundle_detaches`; declared concrete command types and empty bundle |
| C-61 | Partial | `test_c61_versioned_header_and_input_roundtrips`; S1 header rules plus S2 typed v3 rows |
| C-62 | Wait for S2 | `test_c62_runner_replay_current_identity_matrix`; explicit current layout and typed build |
| C-63 | Wait for S2 | `test_c63_runner_terminal_statuses_distinct`; composed runner/rollback path |
| C-64 | Partial | `test_c64_provider_identity_scope_and_fingerprint` |
| C-65 | Partial | `test_c65_setup_claim_validation_and_fingerprint` |
| C-66 | Wait for S2 | `test_c66_direct_replay_identity_and_result_shape`; S1 result shape plus typed fresh build |
| C-67 | Wait for S2 | `test_c67_live_v3_row_atomicity_and_replay_validation`; port/codec/log rollback; S2 linkage and separate output/row preparation failure assertions are extended below; the generic inventory does not currently cover them. |
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

### S2-specific acceptance extensions

The following named assertions extend the listed inventory cases; they are additional S2 seam
requirements, not claims that the current generic inventory already tests these behaviors.

| Extension | Mapped criterion | Required assertion |
|---|---|---|
| `test_s2_replay_transaction_precedes_injection_c67` | C-67 extension | Assert the single §3 coordinator calls `InputLog.read_replay_row(index)`, `MatchSim.begin_replay_row(row)`, owner begin, validation, atomic typed-suffix enqueue, one canonical readback, `MatchSim.capture_replay_candidate(transaction, frame, command_bundle, new_suffix, readback)`, and `MatchSim.tick_replay_row(transaction, candidate)` in order. Force failures before and after a real `PreparedTick`; pre-handle failures call `abort_replay_row(transaction)`, later failures call `abort_prepared_tick(prepared_tick)`, each exactly once. |
| `test_s2_s1_attempt_and_output_contract_c46_c67` | C-46/C-67 extensions | Assert live/replay attempt IDs allocate monotonically at opening, remain on owner context and `PreparedTick` across retry boundaries, and never enter snapshots, hashes, or replay bytes. Assert `DetachedCommandBundle.records_in_order()` returns new ordered detached `RefCounted` values; `SystemTickResult(ok: bool, outputs: Array[RefCounted], error: Error)` has detached ordered outputs, errors have an empty array, and `MatchSim` concatenates successful outputs in registration/local order into `PreparedTick.outputs`. |
| `test_s2_typed_bundle_append_identity_c67_c73` | C-67/C-73 extensions | Assert `InputLog.prepare_append` receives exact `PreparedTick`, `EncodedCommandBundle`, and `PreparedOutputBundle` identities. Raw dictionaries/arrays cannot substitute for typed bundles; bundle identity mismatch rejects before row visibility. |
| `test_s2_test_dependency_injection_rollback_c46_c67` | C-46/C-67 extensions | Install codec and row-preparer fakes through `MatchRunner` subclass overrides. The codec fake performs the real one-shot suffix read before failure; row fake reserves then cancels the real append after successful output preparation. Both assert normal `abort_prepared_tick -> S2RuntimePortOwner.restore` and exact rollback. |
| `test_s2_exact_candidate_capture_c52` | C-52 extension | The owner enumerates `context.commands.records_in_order()`, validates/casts every record to `S2RuntimeCommand`, builds an ordered typed array, and compares full typed snapshots (NaN-aware for floats) to the complete canonical pending queue. It captures the exact 0-based frame tick, attempt ID, candidate map, and tick-start result index. Altered payload/phase/kind/sequence, duplicate, foreign, reordered, missing, extra, or wrong concrete type fails capture and leaves the entire port snapshot unchanged. The S1 bundle remains outside the typed port signature. |
| `test_s2_phase_reads_and_completion_checks_c45` | C-45 extension | `commands_for_phase()` returns detached typed copies in canonical queue order and registers each exact reference issued by that port. Mutating a copy cannot alter pending snapshots. `complete_command` succeeds only for an active candidate member that is `is_same()` to a registered issued reference, still matches its frozen full snapshot, expected phase, valid successful kind-specific payload, canonical sequence/kind, and has no prior consumption/emission. A byte-identical constructor/from-snapshot command, another port's issued object, old retry reference, wrong phase, nonmember, altered, duplicate, malformed, rejected, and unresolved input is rejected and makes the S2 tick fail. Assert the phase argument is only a claim and does not authenticate caller identity; fixed built-in call sites use static phase constants and external/mod producers cannot call completion directly. |
| `test_s2_consumed_result_bijection_c45` | C-45 extension | At owner commit, assert an exact bijection between consumed candidate sequences and the current tick's appended result suffix. Missing, extra, duplicate, wrong-kind, or non-success results fail commit and publish no output. Unconsumed candidates remain pending byte-for-value with no result. Each producer returns exactly its own newly appended suffix; aggregate order is producer registry order then local completion order, with no owner duplicate and no sorting. |
| `test_s2_carried_command_success_next_tick_c72` | C-72 extension | Carry an unconsumed command with its original sequence and complete value through a successful tick with no result for it. In the next candidate it remains unchanged and may complete once; the next tick's result links to that sequence and appears only in that tick's aggregate suffix. |
| `test_s2_current_result_suffix_and_codec_compare_c67` | C-67 extension | Retain historical results across ticks. Assert `take_staged_output_suffix` starts at the captured tick-start index and returns only the current append-ordered suffix. `prepare_outputs` passes both `prepared_tick.candidate_frame.tick` and `prepared_tick.candidate_attempt_id`, takes once, compares equal length and every ordered typed snapshot (NaN-aware for floats) to `prepared_tick.outputs`, then validates status/payload. Independently inject extra, missing, duplicate, reordered, fabricated, stale, wrong-kind, and mismatched-payload records and assert preparation rejection. |
| `test_s2_suffix_read_lease_c67` | C-67 extension | The staged suffix read succeeds once for the exact frame tick/attempt ID pair, including for an empty suffix. A wrong tick, wrong/stale attempt ID, absent/failed stage, or second read returns the failure shape without changing queue or retained results. A prepared handle from an aborted attempt cannot consume the retry's suffix. |
| `test_s2_output_prepare_failure_rollback_retry_c46_c67` | C-46 and C-67 extensions | Complete commands and stage owner commit, then use a test-owned codec fake to reject output preparation after the suffix read. Assert exact full port snapshot restoration, no failed row or signal, stale PreparedTick/suffix rejection, rejection of references issued in the failed attempt, and retry with the same frame, typed candidate, and sequences but a new attempt ID/fresh one-shot suffix. Retry outputs are identical and ordered; exactly one row and one results batch commit. |
| `test_s2_row_prepare_failure_rollback_retry_c46_c67` | C-46 and C-67 extensions | Allow output preparation to read/validate the suffix, then use a test-owned row-preparer fake to reject row preparation. Assert the same exact restoration, no row/signal, stale handle/suffix and old issued-reference rejection, and same frame/candidate/sequences with a new attempt ID and fresh suffix on retry. Retry outputs remain identical and ordered; exactly one row and one results batch commit. |
| `test_s2_restore_mismatch_fatal_rollback_c54_c68` | C-54 and C-68 extensions | Make adapter restore observe a port snapshot that differs from its exact pre-tick checkpoint after `abort_prepared_tick`. Restore returns non-OK, `MatchSim` latches terminal `FATAL_ROLLBACK`, and no retry, row, output, or signal is reported as successful. The checkpoint is bound to the exact attached port object. |
| `test_s2_copy_on_publication_immutability_c59` | C-59 extension | Publish a valid producer result. Assert `complete_command` did not stamp, seal, freeze, or mutate producer-owned result/payload aliases. Mutating those aliases after completion cannot change the detached published copy. Outer and active-payload public-field assignments on published values are no-ops; `results()`, producer suffix arrays, and decoded successful outputs expose immutable published values. Mutating detached arrays and `snapshot()` dictionaries/nested arrays changes only those mutable containers. Verify unpublished `PassLaunch` command/filter builders remain mutable. This is application-level public-field protection; `_sealed` remains private-by-convention, not tamper-proof. |

No case is test evidence until a separate author implements and runs it. The failure/retry
assertions use the concrete codec/row-preparer substitution described in §6. Fake typed-factory
branches for C-69/C-70 remain deferred under §6. Implementation and two independent reviews
remain separate gates.
## 10. Open decisions and implementation delta

No open choice in this document changes approved S2 physics behavior. The C-45–C-77 acceptance
behaviors are retained. The contract resolves the seam-level names and value rules for test
authors; it does not assert that missing code exists.

The following implementation work is required before the S2-dependent cases can run: add
`S2RuntimePortOwner`, `S2OutputSuffixResult`, `S2ProviderBindings`, `S2ReplayInstanceResult`, and
`S2ReplayCodec`; make port snapshots/checkpoints cover queue, historical results, consumed
sequence set, next sequence, failure state, frozen candidate map/frame tick/attempt id/result
baseline, staged flag, suffix-read lease, and issued-reference lifetime; implement exact owner
capture, checked S2 producer bridge, candidate/phase/identity/payload validation,
consumed/result bijection, typed codec suffix comparison, and copy-on-publication
immutability; implement the S1-owned prepared append and replay receipt contracts; wire
`MatchBuildResult.codec`; add the explicit current-layout identity to replay entry points; enforce
factory/setup/compatibility/reset order. Separately reviewed test-only injection seams are still
required for the deferred branches identified in §6.

### Cross-spec dependencies and status

| Dependency | Required contract | Status / blocker |
|---|---|---|
| S1 transaction identity | Allocate monotonic `candidate_attempt_id` at live/replay opening; retain on context and `PreparedTick`; exclude from deterministic snapshot/hash/replay serialization. | Unapproved S1 API/source dependency; must be documented in the absent S1 test API and reviewed before S2 implementation. |
| S1 command/output values | `DetachedCommandBundle.records_in_order() -> Array[RefCounted]` returns fresh ordered detached values; `SystemTickResult(ok: bool, outputs: Array[RefCounted], error: Error)` has detached validated outputs (empty on error); `MatchSim` concatenates in registration/local order into `PreparedTick.outputs`. | The latest S1-core candidate states the three-field system result, while the latest S1-test-api candidate still lists a two-field result. Treat the exact three-field constructor and output aggregation as unapproved S1 dependencies pending that API update/review. |
| S1 append identity | `InputLog.prepare_append(prepared_tick: PreparedTick, command_bundle: EncodedCommandBundle, output_bundle: PreparedOutputBundle) -> AppendPrepareResult`; `commit_append(token: PreparedAppendToken) -> Error`; `cancel_append(token: PreparedAppendToken) -> Error`. | Required S1 API/source update; S2 owns both bundle types. S1 must add `.prepared(token)` / `.failed(error)` factories to its positional-only `AppendPrepareResult`. |
| S1 replay dispatch | `MatchSim.begin_replay_row(source_row: ReplaySourceRow) -> ReplayRowBeginResult`; `SimTickOwner.begin_replay_row(source_row: ReplaySourceRow, candidate_frame_tick: int, candidate_attempt_id: int) -> OwnerCaptureResult`; `MatchSim.capture_replay_candidate(transaction: ReplayRowTransaction, frame: InputFrame, command_bundle: EncodedCommandBundle, new_suffix: Array[RefCounted], canonical_port_readback: CanonicalPortReadback) -> ReplayCandidateResult`; `MatchSim.tick_replay_row(transaction: ReplayRowTransaction, candidate: ReplayCandidate) -> TickResult`; `MatchSim.abort_replay_row(transaction: ReplayRowTransaction) -> Error`. The owner seal callback receives the same readback exactly once. | All are pending S1 API/source additions, unapproved. Exact value paths, fields, factories, and lifecycle are listed in §1; the shared coordinator order is §3. |
| S1 checkpoint value | Owner checkpoint contains only a complete immutable copied runtime snapshot, no `S2RuntimePort` or other external `Object`. The adapter's one-time `_port` binding carries identity; restore rolls back through it once and compares the resulting snapshot. | Required S1 update. |
| Test failure seam and factories | Exact unapproved S1 methods: `MatchRunner._prepare_output_bundle(prepared_tick: PreparedTick) -> CodecResult`; `MatchRunner._prepare_log_append(prepared_tick: PreparedTick, command_bundle: EncodedCommandBundle, output_bundle: PreparedOutputBundle) -> AppendPrepareResult`. `CodecResult` is S2-owned at `game/match/s2/codec_result.gd`, `{ok: bool, value: Variant | null, error: Error}`, factories `succeeded(value)` / `failed(error)`. `AppendPrepareResult` is S1-owned at `game/match/append_prepare_result.gd`, `{ok: bool, token: PreparedAppendToken | null, error: Error}`, factories `.prepared(token)` / `.failed(error)`. | S1 source has neither runner method and only positional AppendPrepareResult construction; both signatures and factories are pending, unapproved S1 dependencies. Test subclasses call `super`; production methods delegate to codec/log. |
| Typed factory failure fakes | C-69/C-70 factory/reset spies need a separately approved seam. | Explicitly deferred; not required to weaken other contracts. |

Other open decisions remain deferred for these issues recorded by the S2 API inventory / S1 inventory:
- The exact behavior-complete public observer for S2 post-hit classifier B-12 remains unresolved;
  do not use undocumented classifier internals as an S1 test oracle.
- The interaction ordering conflict remains open. Keep `commands_for_phase()` read order in
  canonical queue order and preserve producer completion/append order; do not sort commands or
  settle actor/sequence tie-breaking here. Tests assert only declared queue order, phase membership,
  and observed completion order, not a disputed actor/sequence interaction order.
- The `physics.wind_provider` callable's exact typed signature remains undeclared; S2 bindings
  here cover the existing contact source and solver only.
- Serialized parser/framing details not fixed by the approved v1/v2/v3 specs remain outside the
  acceptance oracle. Do not expand C-61 from this seam document.

If an implementation proposal requires changing any approved physics outcome, numeric value,
system order, command payload, replay compatibility rule, or S1 transaction boundary, stop that
affected criterion as deferred and obtain an ADR/spec decision before changing this contract.
