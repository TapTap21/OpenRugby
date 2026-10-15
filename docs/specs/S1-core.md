# S1-core: match simulation, flow, clock, pitch, data model

- Slice: S1 (core). Architecture: [ADR-004](../adr/ADR-004-core-architecture.md), ADR-001.
- Canonical public test API for generic results, claims, tick context and composition records: [S1 public test API](S1-test-api.md).
- Depends on: nothing game-specific. Phase 1 RE later fills data, never code.
- Reimplementation, not a port (PLAN section 4 rule 0, CONVENTIONS "Reimplementation, not a
  port"): only Rugby 08's observable behaviour and numeric constants are carried over, always
  into named Resource fields with units. Names, structure, update order and data layouts are
  ours; when RE findings land they fill data, never reshape these classes after the original.
- Out of scope: ball, players on the pitch, rules/laws, AI, rendering, mod loading
  ([S1-modloader](S1-modloader.md)), device input ([S9-input](S9-input.md)).

Words: **must** is required and tested. "PROVISIONAL" marks a field whose name, range or default
Phase 1 may change; it still exists and is tested for presence and default. "TBC-RE" marks a
default taken from real-world World Rugby law that RE must confirm against Rugby 08.

## 1. Files and classes

All scripts are typed GDScript, follow `docs/CONVENTIONS.md`, and have `class_name`.

| Path | `class_name` | Base |
|---|---|---|
| `game/match/match_sim.gd` | `MatchSim` | `RefCounted` |
| `game/match/sim_rng.gd` | `SimRng` | `RefCounted` |
| `game/match/sim_system.gd` | `SimSystem` | `RefCounted` |
| `game/match/sim_tick_owner.gd` | `SimTickOwner` | `SimSystem` |
| `game/match/s2_runtime_port_owner.gd` | `S2RuntimePortOwner` | `SimTickOwner` |
| `game/match/sim_tick_context.gd` | `SimTickContext` | `RefCounted` |
| `game/match/sim_tick_outcome.gd` | `SimTickOutcome` | `RefCounted` |
| `game/match/detached_command_bundle.gd` | `DetachedCommandBundle` | `RefCounted` |
| `game/match/detached_command_bundle_builder.gd` | `DetachedCommandBundleBuilder` | `RefCounted` |
| `game/match/match_clock.gd` | `MatchClock` | `RefCounted` |
| `game/match/match_config.gd` | `MatchConfig` | `Resource` |
| `game/match/match_runner.gd` | `MatchRunner` | `Node` |
| `game/match/match_replay.gd` | `MatchReplay` | `RefCounted` (static helpers) |
| `game/match/input_frame.gd` | `InputFrame` | `RefCounted` |
| `game/match/input_source.gd` | `InputSource` | `RefCounted` |
| `game/match/input_log.gd` | `InputLog` | `RefCounted` |
| `game/match/replay_source_row.gd` | `ReplaySourceRow` | `RefCounted` |
| `game/match/replay_source_row_result.gd` | `ReplaySourceRowResult` | `RefCounted` |
| `game/match/replay_row_begin_result.gd` | `ReplayRowBeginResult` | `RefCounted` |
| `game/match/replay_validation_token.gd` | `ReplayValidationToken` | `RefCounted` (opaque capability) |
| `game/match/prepared_append_token.gd` | `PreparedAppendToken` | `RefCounted` (opaque capability) |
| `game/match/match_readiness_blocker.gd` | `MatchReadinessBlocker` | `RefCounted` |
| `game/match/match_readiness_report.gd` | `MatchReadinessReport` | `RefCounted` |
| `game/match/match_build_result.gd` | `MatchBuildResult` | `RefCounted` |
| `game/match/replay_validation_authority.gd` | `ReplayValidationAuthority` | `RefCounted` (private build-owned registry) |
| `game/match/replay_validation_result.gd` | `ReplayValidationResult` | `RefCounted` |
| `game/match/canonical_port_readback.gd` | `CanonicalPortReadback` | `RefCounted` (codec-authored opaque identity) |
| `game/match/canonical_port_readback_result.gd` | `CanonicalPortReadbackResult` | `RefCounted` |
| `game/match/s2_provider_bindings.gd` | `S2ProviderBindings` | `RefCounted` (S2-owned typed factory input) |
| `game/match/s2_replay_instance_result.gd` | `S2ReplayInstanceResult` | `RefCounted` (S2-owned typed factory result) |
| `game/match/replay_header.gd` | `ReplayHeader` | `RefCounted` |
| `game/match/replay_input_source.gd` | `ReplayInputSource` | `InputSource` |
| `game/match/flow/match_state_ids.gd` | `MatchStateIds` | `RefCounted` (constants only) |
| `game/match/flow/match_triggers.gd` | `MatchTriggers` | `RefCounted` (constants only) |
| `game/match/flow/match_flow_config.gd` | `MatchFlowConfig` | `Resource` |
| `game/match/flow/match_state_def.gd` | `MatchStateDef` | `Resource` |
| `game/match/flow/match_transition_def.gd` | `MatchTransitionDef` | `Resource` |
| `game/match/flow/match_state_machine.gd` | `MatchStateMachine` | `RefCounted` |
| `game/match/flow/match_condition.gd` | `MatchCondition` | `Resource` |
| `game/match/flow/conditions/condition_ticks_in_state.gd` | `ConditionTicksInState` | `MatchCondition` |
| `game/match/flow/conditions/condition_period_expired.gd` | `ConditionPeriodExpired` | `MatchCondition` |
| `game/match/flow/conditions/condition_all.gd` | `ConditionAll` | `MatchCondition` |
| `game/match/flow/default_match_flow.tres` | (a `MatchFlowConfig`) | |
| `game/match/pitch/pitch_geometry.gd` | `PitchGeometry` | `Resource` |
| `game/match/pitch/default_pitch.tres` | (a `PitchGeometry`) | |
| `game/data/player_profile.gd` | `PlayerProfile` | `Resource` |
| `game/data/player_attribute_schema.gd` | `PlayerAttributeSchema` | `Resource` |
| `game/data/team.gd` | `Team` | `Resource` |
| `game/data/kit.gd` | `Kit` | `Resource` |
| `game/data/stadium.gd` | `Stadium` | `Resource` |
| `game/data/rules_config.gd` | `RulesConfig` | `Resource` |
| `game/data/difficulty_profile.gd` | `DifficultyProfile` | `Resource` |
| `game/data/camera_preset.gd` | `CameraPreset` | `Resource` |
| `game/data/defaults/default_rules.tres` | (a `RulesConfig`) | |
| `game/data/defaults/default_attribute_schema.tres` | (a `PlayerAttributeSchema`) | |
| `game/data/defaults/default_difficulty.tres` | (a `DifficultyProfile`) | |
| `game/data/defaults/default_camera_preset.tres` | (a `CameraPreset`) | |

Patchability rule (the mod loader depends on it): every data field is a typed `@export` var. No
data in non-exported vars, no setters with side effects on data Resources, nested data is an
exported `Resource` field or a typed `Array`/`Dictionary` of them.

## 2. Simulation

### 2.1 `SimRng`

Wraps one `RandomNumberGenerator` (PCG32).

- `_init(p_seed: int)`; read-only `seed: int` (the constructor value).
- `next_int() -> int` (unsigned 32-bit, like `randi()`), `range_int(from: int, to: int) -> int`
  (inclusive), `next_float() -> float` in [0, 1), `range_float(from: float, to: float) -> float`,
  `chance(probability: float) -> bool` (true when `next_float() < probability`).
- `get_state() -> int`, `set_state(state: int) -> void`.

### 2.2 `InputFrame` (the sim's only input)

One tick of input for every controller slot. Shape is fixed at construction.

- `const AXIS_MAX: int = 127`
- `_init(p_slot_count: int = 1, p_axes_per_slot: int = 2)`
- `var tick: int` (0-based index of the tick it belongs to)
- read-only `slot_count: int`, `axes_per_slot: int`
- `buttons: PackedInt64Array` (size `slot_count`; bit `b` of `buttons[s]` = button action `b` held)
- `axes: PackedInt32Array` (size `slot_count * axes_per_slot`, slot-major; each in [-127, 127])
- `is_held(slot: int, bit: int) -> bool`, `set_held(slot: int, bit: int, held: bool) -> void`
  (bits 0..62)
- `get_axis(slot: int, axis: int) -> int`, `set_axis(slot: int, axis: int, value: int) -> void`
  (clamps to [-127, 127])
- `clear() -> void` (all buttons 0, all axes 0, tick unchanged)
- `copy_from(other: InputFrame) -> void` (same shape required; copies tick, buttons, axes)
- `equals(other: InputFrame) -> bool` (shape, tick, buttons and axes equal)

Bit and axis meaning comes from the input action set (S9); the core never names actions.

### 2.3 `SimSystem`

Base for ordered tick participants. `setup(sim) -> SetupResult` identifies exactly one declared
capability: `COMPLETE_TRANSACTIONAL`, `EXPLICITLY_STATELESS`, or `UNSUPPORTED`. Setup rejects
`UNSUPPORTED`; `COMPLETE_TRANSACTIONAL` requires complete `checkpoint() -> CheckpointResult` and
`restore(checkpoint) -> Error` behavior; `EXPLICITLY_STATELESS` is an explicit assertion that the
participant has no mutable state that can affect this or a future tick. The default empty
checkpoint is valid only with that explicit stateless declaration and never certifies a stateful
participant. Its compatibility methods are `tick(sim: MatchSim) -> void` and
`tick_checked(sim: MatchSim, context: SimTickContext) -> SystemTickResult`. The former remains
available for existing subclasses. The core calls only the checked method; its default
implementation calls legacy `tick(sim)` and returns success, while a system that can fail overrides
the checked method and returns a failure result. `snapshot()` remains the deterministic/hash representation; rollback checkpoints
additionally cover every value that can affect future state or RNG draws. Participants must not
publish externally during setup, capture, tick, or commit.

`SetupResult` is a constructible value record with `ok: bool`, `error: Error`,
`capability: TransactionCapability`, `participant_claim: ParticipantClaim | null`, and
`owned_provider_claims: Array[ProviderClaim]`. Success is `(true, OK, declared capability, valid
participant claim, claims)`; failure is `(false, non-OK, UNSUPPORTED, null, empty claims)`.
`ParticipantClaim` is the canonical participant identity consumed by setup fingerprinting and
contains `stable_participant_id: String`, `participant_version: String`,
`configuration_fingerprint: String`, and `deterministic_initial_state_fingerprint: String`.
Every field must be stable, canonical, and non-empty. Setup rejects missing/malformed claims and
duplicate stable participant identities. `system_id()` may remain a diagnostic/display accessor;
its legacy default `&"system"` is never a participant identity or fingerprint input. Fake
participants can construct both successful and failing `SetupResult` values directly.

Every mutable registered participant, including the required S2 port-state owner adapter, uses
exactly one generic typed replay factory:
`create_replay_instance() -> ReplayInstanceResult`. The result is a value record
`{ok: bool, instance: SimSystem | null, error: Error,
owned_provider_claims: Array[ProviderClaim]}`. Success requires `(true, new_instance, OK, claims)`;
failure requires `(false, null, non-OK, empty claims)`. The claims are detached immutable value
records, while each `provider` field intentionally retains the exact provider object reference for
per-registry duplicate-ownership checks and exact identity checks when constructing and validating
`S2ProviderBindings` and matching setup claims to factory claims. This reference is never serialized
or fingerprinted as an object address; only stable claim values feed setup fingerprinting. The
factory constructs the fresh initial participant and every stateful provider
it uniquely owns, then returns claims referring to those exact fresh providers; a participant with
no providers returns an empty array. A provider declared `EXPLICITLY_STATELESS` may retain its
original object reference across the separate live and replay registries, once in each registry;
the declaration means the provider has no mutable state and no calls can change behavior that
affects current or future deterministic ticks. This never permits a repeated reference within either
registry. Factory-result
claims describe the fresh initial instance; they are never claims copied from the live, advanced
source. The factory uses stable configuration, not the live instance's advanced runtime state, and
must not mutate or set up the original participant or source sim. An explicitly
`EXPLICITLY_STATELESS` participant may return itself. Missing/failed factories, a shared stateful
instance, or a result whose state/configuration is not independent and initial blocks replay setup
before capture or tick. `MatchCompositionBuilder.build_replay(request)` dispatches this same
no-argument signature once for each mutable entry in the effective ordered `SimSystem` registry;
there is no overload or runtime method-arity dispatch. Ordinary live `build(request)` retains the
supplied objects.

`SystemTickResult` is a constructible value record: `ok: bool`, `error: Error`. Success is
`ok = true, error = OK`; failure is `ok = false, error != OK`. A successful system tick has no
separate value payload. A fake participant can return either shape directly.

`SimTickOwner extends SimSystem` is an opt-in owner participant in the same ordered system
registry. It captures from an immutable generic `SimTickContext`, copied from candidate input and
pre-tick state, then commits its capture with the completed generic `SimTickOutcome`. Owners
capture in stable registration order before any system ticks. Systems then tick in their existing
registration order. Owner commits follow successful system execution and staged clock/flow
processing, in stable registration order. A capture describes pre-update state; committed owner
state is available to captures on the next tick. Ordinary systems gain no lifecycle no-op methods
and a second owner registry is not introduced. Context and outcome contain generic tick, input,
clock, flow, transition, and detached existing typed command-record information only. Copied values
exposed by the context cannot mutate sim state. Both are immutable value snapshots: getters return
copies of mutable packed/container values and no mutable sim/config/provider references.

An owner implements synchronous `capture_tick(context: SimTickContext) -> OwnerCaptureResult` and
`commit_tick(context: SimTickContext, capture: OwnerCapture, outcome: SimTickOutcome) ->
OwnerCommitResult`. `OwnerCapture` is an immutable record with `payload: Variant`, an opaque,
owner-defined immutable value detached from owner/provider state; S1 does not define its shape.
`OwnerCaptureResult` has `ok: bool`, `capture: OwnerCapture` (non-null only on success), and
`error: Error`; success is `(true, capture, OK)`, failure is `(false, null, non-OK)`. The capture
result carries that immutable owner payload to the lifecycle. `OwnerCommitResult` has
`ok: bool, error: Error`, with success `(true, OK)` and failure `(false, non-OK)`. Any failure
aborts the transaction. Systems do not publish external signals during either tick entry point and
do not get owner hooks.

Each injected stateful provider is owned by exactly one registered `SimSystem` or
`SimTickOwner`; that owner includes the provider's complete state in its own checkpoint/restore
and deterministic setup identity. A stateless provider object may serve as a read-only dependency
to multiple consumers in each of the separate live and replay registries only when one registered
owner in each registry emits its unique claim for that provider. Each effective ordered registry
has unique provider object ownership: no `ProviderClaim.provider` object reference may occur more
than once in that registry,
including stateless claims, repeated claims by one participant, or claims by different participants.
This rule applies independently to live setup claims and fresh replay factory claims. An explicitly
`EXPLICITLY_STATELESS` participant may be reused as the same instance in the separate live and
replay registries. A provider declared `EXPLICITLY_STATELESS` may be referenced once in each of
those registries, with one registered owner per registry emitting its unique claim even when
multiple consumers use it as a read-only dependency. This exception never permits a repeated
claim/reference within either registry, including repeats by the same owner. Provider state remains
owned by exactly one registered system/owner. Stateless providers are explicitly declared as such
during setup. No second provider
registry is introduced. Registration/setup rejects unsupported participants, unowned stateful
providers, repeated provider references within a registry, and any stateful participant/provider
without complete transactional checkpoint/restore before tick 1.

The uniquely owning participant's generic `create_replay_instance()` factory creates its own
distinct initial participant and each stateful provider it uniquely claims, exactly once. The S2
port itself is not a `SimSystem`, is not a registry entry, and never implements the generic
participant factory. A required `S2RuntimePortOwner extends SimTickOwner` adapter is the sole
registered owner of port queue/results/sequence/failure state. Its generic factory returns a fresh,
initial, unbound adapter; the builder then creates the fresh port through the separate S2-specific
factory `S2RuntimePort.create_replay_instance(bindings: S2ProviderBindings) ->
S2ReplayInstanceResult`, whose result is `{ok: bool, port: S2RuntimePort | null, error: Error}`.
Its success and failure shapes are `(true, fresh_port, OK)` and `(false, null, non-OK)`.
This S2-only signature is dispatched only by the S2 composition builder, never through generic
participant dispatch. `S2ProviderBindings` is an S2-owned typed value containing the exact fresh
provider references and corresponding `ProviderClaim`s, collected from fresh owners' validated
factory-result claims. The fresh port copies stable configuration and transient runtime setup,
receives those references, and never clones providers. The builder attaches that exact port to the
fresh adapter using the S2 adapter's typed construction path, verifies both the adapter-to-port
identity and each binding-to-claim provider reference by object identity, constructs the fresh sim
with the ordered registry and port, and calls normal `setup(sim)` exactly once. It requires each
owner's setup claims to match its factory-result claims in count, order, exact provider object
identity, stable strings, and transaction capability. A mismatch rejects before fingerprint
acceptance, capture, or tick. Only after setup and claim agreement does it compute/accept the fresh
setup fingerprint and start capture; setup confirms factory-result claims and is not their
pre-port source.
The effective registry is constructed once for live build: the builder's already ordered caller,
extension, and composed system entries retain their order, then exactly one `S2RuntimePortOwner`
is appended as the final entry. Replay substitutes each mutable entry at its original index,
retains that order, then appends the adapter in the same final position. The adapter exposes
`attach_port(port: S2RuntimePort) -> Error` as a builder-only construction operation; it succeeds
once, before setup, and rejects null, repeated, or already-owned port references. The builder also
rejects a factory result that is the original request port. Every provider is
cloned only by its one unique owner; a stateful provider cannot also be claimed by the adapter.
An `EXPLICITLY_STATELESS` provider declaration is the normative claim checked by setup/factory
comparison: the provider has no mutable state and no calls can change behavior that affects current
or future deterministic ticks. There is no second proof object or runtime reflection; a false
declaration violates the contract and is caught through tests and review. A stateless provider may
be referenced as a read-only dependency by multiple consumers only when one registered owner in
each effective registry emits its unique claim; the exact provider reference may appear once in the
live registry and once in the separate replay registry. Missing factories, malformed or failed
factory results, duplicate/shared stateful providers, or stale bindings block replay setup before
capture or tick. S2 owns concrete provider
signatures and its typed bindings/results; S1 defines no provider registry or S2 provider schema.
`reset_runtime()` remains a transient queue/result/sequence reset, never provider rewind or a replay
baseline.

The S2 port runtime queue, results, consumed-sequence state, next sequence, and failure metadata
are future-affecting mutable state. The `S2RuntimePortOwner` adapter, not the port, is registered
exactly once as a `SimTickOwner` in the effective ordered registry. The same port object is
referenced by that adapter, composed systems, and replay coordinator. The adapter alone
checkpoints, restores, snapshots/hashes, and commits all port runtime state; provider claims stay
with their existing unique owners and are not repeated by the adapter. The adapter's factory result
is bound to the newly constructed port before setup, and stale/absent binding identity proof rejects
the build. If the port reports a failed tick, its adapter returns a checked `OwnerCommitResult`
failure so the sim cannot remain prepared. Stable port configuration and initial provider identity
feed setup fingerprinting; advanced queues, results, and sequence values appear only in runtime
snapshots/hashes.

`ProviderClaim` in `SetupResult.owned_provider_claims` has these fields: `provider: RefCounted`
(the referenced instance, used for per-registry duplicate-ownership checks and exact identity checks
when constructing/validating `S2ProviderBindings` and matching setup claims to factory claims),
`stable_provider_id: String`,
`provider_version: String`, `transaction_capability` (`COMPLETE_TRANSACTIONAL` or
`EXPLICITLY_STATELESS`), `configuration_fingerprint: String`, and
`deterministic_initial_state_fingerprint: String`. All stable string fields are canonical and
non-empty; id and version are semantic identifiers, not object addresses. `provider` is never
serialized or included in setup fingerprinting as an object address; only the five stable claim
values (excluding the reference) feed setup fingerprinting. Each claim declares its
transaction capability. `EXPLICITLY_STATELESS` is the provider owner's explicit declarative
assertion that the provider has no mutable state and no calls can change behavior that affects
current or future deterministic ticks. This declaration is the normative claim checked by setup
and factory-claim comparison; S1 defines no second proof object or runtime reflection. A false
declaration violates the contract and is caught through tests and review, not dynamic introspection.
The claiming participant's checkpoint covers every stateful provider it owns. Providers are not
added to a second tick registry. A complete transactional participant's
checkpoint is an opaque immutable value that restores every future-affecting field; restore is
synchronous and returns `OK` only when that participant and its uniquely owned providers are fully
restored. The sim captures one checkpoint per registered participant before the first mutating
phase. `CheckpointResult` is a constructible value record with `ok: bool`, `value: Variant`, and
`error: Error`: success is `(true, immutable checkpoint value, OK)`; failure is `(false, null,
non-OK)`. A stateful participant cannot report an empty/default value as a successful checkpoint.
An explicitly stateless participant may use the immutable empty checkpoint value. Each
`SimDependencyCheckpoint` is an immutable record with `stable_provider_id: String`,
`provider_version: String`, and `state: Variant` (the provider's opaque immutable rollback value;
null/empty is permitted only for explicitly stateless providers). It is carried inside the owning
participant's checkpoint and restored by that owner; it is not independently registered. A fake
stateful participant can use a non-empty immutable checkpoint value and return `OK` from restore;
a fake failure returns `CheckpointResult(false, null, ERR_FAILED)`. A dependency checkpoint is
always a successfully captured value and has no independent `ok/error` status; provider checkpoint
failure is represented by the containing `CheckpointResult`. `SimTickContext` exposes the
1-based candidate tick, copied candidate
frame and previous-frame/edge view, detached typed command bundle, pre-tick clock/flow values, and
the exact rational clock delta (`numerator`, positive `denominator`; zero represented as `0/1`).
`SimTickOutcome` exposes the candidate tick, pre/post clock and flow values, selected transition
and period effect (if any), and actual rational clock delta. All exposed containers are copied;
the records contain no mutable sim, config, participant, or provider references.

### 2.4 `MatchClock`

- `_init(p_period_count: int, p_period_ticks: int, p_game_seconds_per_period: int)`
- vars: `period: int` (1-based, starts 1), `period_count: int`, `period_ticks: int`,
  `elapsed_ticks: int` (in current period, starts 0), `game_seconds_per_period: int`
- `advance() -> void`: `elapsed_ticks += 1`, no cap (rugby plays past time).
- `is_period_expired() -> bool`: `elapsed_ticks >= period_ticks`.
- `is_last_period() -> bool`: `period >= period_count`.
- `start_next_period() -> void`: `period += 1`, `elapsed_ticks = 0`.
- `game_time_seconds() -> int`: displayed match time with integer maths,
  `(period - 1) * game_seconds_per_period + (elapsed_ticks * game_seconds_per_period) / period_ticks`.

### 2.5 `MatchSim`

```
class_name MatchSim extends RefCounted
signal state_changed(from_state: StringName, to_state: StringName)
signal period_started(period: int)
signal period_ended(period: int)
signal finished
const TICKS_PER_SECOND: int = 60
var config: MatchConfig      # read-only after _init
var rng: SimRng
var clock: MatchClock
var flow: MatchStateMachine
var tick_count: int          # ticks executed so far
func _init(p_config: MatchConfig)
func is_valid() -> bool
func add_system(system: SimSystem) -> Error
func tick(frame: InputFrame) -> TickResult
func tick_checked(frame: InputFrame, commands: DetachedCommandBundle) -> TickResult
func begin_replay_row(source_row: ReplaySourceRow) -> ReplayRowBeginResult
func tick_replay_row(prepared_tick: PreparedTick, frame: InputFrame, commands: DetachedCommandBundle) -> TickResult
func finalize_prepared_tick(prepared_tick: PreparedTick, append_token: PreparedAppendToken) -> void
func finalize_standalone_tick(prepared_tick: PreparedTick) -> Error
func finalize_replay_tick(prepared_tick: PreparedTick, replay_validation_token: ReplayValidationToken) -> Error
func abort_prepared_tick(prepared_tick: PreparedTick) -> Error
func raise_trigger(trigger: StringName) -> void
func current_state() -> StringName
func is_finished() -> bool
func is_stopped() -> bool
func stop_reason() -> StringName
func is_held(slot: int, bit: int) -> bool
func just_pressed(slot: int, bit: int) -> bool
func just_released(slot: int, bit: int) -> bool
func get_axis(slot: int, axis: int) -> int
func snapshot() -> Dictionary
func state_hash() -> String
```

`ReplayValidationAuthority` is one private typed nonce registry created per replay build and shared
by that build's `MatchSim` and single `S2ReplayCodec`. Only the codec's private mint path can
register a `ReplayValidationToken`, and only after validating the exact `ReplaySourceRow`,
carried/new command sequence rules, canonical port readback, command/output linkage, and generated
outputs against expected outputs. The typed `ReplayValidationResult` is `{ok: bool, token:
ReplayValidationToken | null, error: Error}`; success is `(true, exact_registered_token, OK)` and
failure is `(false, null, non-OK)`. Generic S1 trusts this typed codec boundary; it accepts no
caller boolean or arbitrary row arrays.

`ReplayValidationToken._init()` is public and takes no arguments, but an ordinary caller-created
object is inert and unregistered; only the private build-owned authority mint path creates a
usable token. `ReplayValidationToken` is an opaque, single-use capability. Its registry entry binds the exact
authority, sim, active `PreparedTick`, `ReplaySourceRow` identity, canonical readback identity,
expected-output identity, generated-output identity, and successful exact comparison. The authority
stores the registered nonce and exact token object identity. `MatchSim.finalize_replay_tick` asks its
build-owned authority to validate and consume that exact registered token once. Forged or caller-constructed objects, copied/reassembled row values, cross-sim/tick/log/index/
row/readback/output pairings, aborted/stale receipts, and reused tokens fail. Token fields and a token
copy/reassembly constructor are not public, so copied-token-field tests are not expressible. `abort_prepared_tick`
invalidates any receipt registered for its handle. No usable token is returned on any failed check.
Finalization accepts only the exact active prepared tick and its matching live token; failure does
not finalize. Failed row validation aborts while rollback remains possible. Direct and runner-driven
replay publish no MatchSim signals, EventBus relays, or `ticked` before receipt-backed finalization
succeeds. Generic S1 does not duplicate the S2 wire schema.

The codec entry point is
`validate_replay_row(prepared_tick: PreparedTick, source_row: ReplaySourceRow,
canonical_port_readback: CanonicalPortReadback) -> ReplayValidationResult`. The typed source row
is issued by its `InputLog`; the canonical readback is codec-authored after validating the port's
full queue. The codec validates source-row fields, carried/new sequence rules, command/output
linkage, and generated output equality before its authority registers and returns a token.

Construction: if `config.validate()` returns errors, the sim is invalid (`is_valid()` false,
`push_error` once, and a checked tick does not change state). Otherwise:
`rng = SimRng.new(config.seed)`;
`clock = MatchClock.new(config.rules.period_count, config.period_real_seconds * TICKS_PER_SECOND,
config.rules.period_game_seconds)`; `flow` starts in `config.flow.initial_state`; two
preallocated `InputFrame`s of shape `(config.slot_count, config.axes_per_slot)` hold the current
and previous input, both cleared.

`add_system` and setup of registered owners/providers happen before tick 1. `add_system` returns
`OK` only after setup capability and provider ownership claims validate; otherwise it returns an
error and does not add the participant. The one ordered
registry contains ordinary systems and opt-in `SimTickOwner` participants. Adding participants
after ticking begins is rejected. Each setup explicitly declares complete transactional,
explicitly stateless, or unsupported capability; unsupported and incomplete participants are
rejected before tick 1. Registry order is stable and part of determinism. Stateful providers are
checkpointed/restored by their unique owning registered participant, never a second registry.

`TickResult` is a value record with `status`, `error`, `outcome`, `outputs`, `signal_batch`, and an
opaque prepared-tick handle when applicable. Status is one of `PREPARED`, `COMMITTED`,
`NO_OP_INVALID`, `NO_OP_FINISHED`, `NO_OP_STOPPED`, `FAILED_RETRYABLE`, or `FATAL_ROLLBACK`.
`PREPARED` is an abortable successful execution, not a committed tick: it retains the complete
pre-tick rollback checkpoint, and exposes detached validated typed outputs, the completed generic
outcome, and staged signals. `outputs` is a detached ordered bundle of existing typed output
records (for S2, `S2RuntimeResult` values); no new wire or command schema is introduced.
For live recording, `COMMITTED` is assigned only after the runner has finalized the sim and
committed the complete prepared log row. Replay uses its already complete, read-only source row and
marks the tick committed only after output validation and sim finalization. `NO_OP_INVALID` has
`error = ERR_INVALID_PARAMETER`, no outcome, and an empty
signal batch; it applies when the sim was constructed from an invalid config. It is distinct from
finished and stopped. All no-op statuses leave sim state unchanged and perform no capture.
`PREPARED` carries its outcome, detached output bundle, and ordered `SignalBatch`; all no-op and
failure statuses carry no outcome/outputs and an empty batch. `COMMITTED` carries the same values
after the coordinated boundary. Recoverable phase failures return `FAILED_RETRYABLE` only after full
rollback succeeds. If any restore fails, the result is `FATAL_ROLLBACK`, the sim latches
`stopped = true` with a stable fatal `stop_reason`, and all future checked ticks return
`NO_OP_STOPPED` without capture or mutation. This fatal state is terminal and cannot be retried
or reset in place. `is_stopped()` and `stop_reason()` expose this minimal state; normal completion
remains distinct (`is_finished()`). Invalid construction is still reported by `is_valid()` and is
not a stopped sim.

`begin_replay_row(source_row) -> ReplayRowBeginResult` first validates that the exact row carries a
log-issued identity. An inert caller-created row returns `(false, null, ERR_INVALID_PARAMETER)`
before checkpoint capture or opening the port transaction, with no sim or port state change. For a
valid source row, it captures the same complete sim and owner checkpoint used by `tick_checked` and opens the port owner's internal row transaction before any
replay command injection; it returns an active
`PreparedTick` handle bound to that exact `ReplaySourceRow`. The result is `{ok: bool,
prepared_tick: PreparedTick | null, error: Error}`; success is `(true, handle, OK)`, failure is
`(false, null, non-OK)` with no changed sim or port state. `tick_replay_row(prepared_tick, frame, commands)`
executes checked tick phases using that already-open port transaction and retained checkpoint and
binds the exact candidate to the same handle; it does not begin a second transaction or take a
second checkpoint. Replay sequence checks, new-command
injection, and canonical queue readback happen between `begin_replay_row` and `tick_replay_row`.
Any failure in that interval calls `abort_prepared_tick(prepared_tick)`, restoring the exact pre-row
queue and sequence together with the sim. On successful execution the handle becomes the ordinary
abortable `PREPARED` tick and follows receipt validation/finalization. The standalone/live
`tick_checked` path continues to capture its checkpoint internally.

`SignalBatch` is an immutable ordered array of `StagedSignal` values. Each value has kind
`STATE_CHANGED`, `PERIOD_STARTED`, `PERIOD_ENDED`, or `FINISHED`, and only the corresponding
typed arguments: `from_state`/`to_state`, `period`, `period`, or none. The array corresponds exactly
to the existing `state_changed(from_state, to_state)`, `period_started(period)`,
`period_ended(period)`, and `finished` signals and their current successful order/payloads. Only a
`PREPARED` and `COMMITTED` results carry the staged batch. `MatchSim` never emits it from inside
tick execution. A standalone `MatchSim.tick` publishes locally after standalone finalization. A
runner-owned live tick publishes through the existing MatchSim signal interface only after the
complete row commit, then relays to EventBus and emits `ticked`; replay publishes only after output
validation and replay finalization.

`tick_checked(frame, commands)` copies and normalizes the candidate frame (using the wrong-shape
all-zero fallback) and seals a detached immutable copy of the typed command bundle before any
mutation. Its opaque `PreparedTick` retains those exact immutable candidate values and exposes
read-only copied frame access plus candidate provenance; no getter permits mutation of the retained
values. It then runs all fallible simulation phases without finalizing. On success it returns
`PREPARED`, bound to this sim and exact candidate; the rollback checkpoint remains live.
`finalize_prepared_tick(prepared_tick, append_token)` is
infallible, allocation-free, and performs no callbacks for the already-verified live authorization;
it discards the rollback checkpoint and makes sim state irreversible. A replay tick uses its
validated read-only source row and the replay-specific finalization path. `abort_prepared_tick(prepared_tick)` restores the checkpoint and is
used for codec/log preparation failure or replay validation failure. Successful abort restores the
exact pre-tick state; failed restore latches terminal `FATAL_ROLLBACK`. A handle can be finalized or
aborted once only. For live recording, the runner exposes `COMMITTED` only after sim finalization
and row commit both complete; no callback or signal runs between those operations. Replay accepts
a tick only after validating its existing source row and finalizing sim state. The
`DetachedCommandBundle` is an immutable ordered container of the existing concrete typed command
records that accompany this candidate; it introduces no universal command record or payload
schema. `DetachedCommandBundleBuilder` is the mutable output object used only while sampling: its
`append(existing_command_record) -> Error` accepts existing concrete typed command record values
only (the existing command type/interface contract), preserving concrete types and order. It has
no dictionary/variant payload overload and defines no new command payload schema. `seal() ->
DetachedCommandBundle` copies/detaches the appended records into an immutable ordered bundle; a fresh builder seals to an immutable empty bundle. later
builder or record mutation cannot change the sealed bundle. `InputSource.fill_frame` receives this builder as a submission builder. The runner copies the sampled frame and seals submissions before preparation. For live S2, it validates/enqueues those submitted records, reads and decodes the S2 port-assigned canonical `queued_command_snapshots()` into a distinct final typed candidate bundle, and pairs that bundle with the sampled frame. This exact pair is passed to `tick_checked`, retained by `PreparedTick`, encoded by the codec, and recorded. Non-S2 input uses the sealed submission bundle as its candidate; commandless input uses an immutable empty bundle. Replay supplies recorded records through the same typed codec/port route and treats the verified canonical port readback as the final candidate. The method performs one transaction:

`MatchSim.tick(frame) -> TickResult` is a required compatibility wrapper for standalone sims. It
calls `tick_checked(frame, DetachedCommandBundleBuilder.new().seal())`; on `PREPARED`, it finalizes
through `finalize_standalone_tick(prepared_tick) -> Error`, marks the result `COMMITTED`, and publishes the
staged signals locally. If checked execution or standalone finalization fails, it returns the
failure result and publishes nothing; if finalization rejects the still-active handle, the wrapper
aborts it before returning. Standalone finalization accepts only that sim's exact active prepared
tick, consumes it once without a token, and is infallible for a valid standalone handle. It never
appends to an `InputLog` or relays to `EventBus`.
`MatchRunner` claims its sim as runner-owned before ticking; runner-owned sims reject standalone
finalization. The runner and both replay paths never call it. Recorded live ticks require the exact
append token, and replay ticks require the exact validation receipt before
`finalize_replay_tick(prepared_tick, replay_validation_token)`; neither path
mints a substitute token.

1. Invalid, finished, or stopped sims return without capturing owners or changing state. Copy and
   validate the candidate frame and detached typed command bundle; preserve the input shape
   fallback (a wrong-shaped frame becomes an all-zero frame).
2. Checkpoint the complete sim state and every stateful participant, including providers owned
   by each participant, including RNG,
   current and previous input/edges, clock and flow, pending triggers, finished state, and
   participant state. Every subsequent phase failure restores this checkpoint. A restore failure
   is fatal and makes the sim non-runnable.
3. Build an immutable generic `SimTickContext` from copies of candidate input/commands and
   pre-tick state, including pre-tick tick and clock/flow information plus the exact rational
   deterministic clock delta derived from actual advance. S1 exposes no pause API; world-pause
   behavior is unresolved and C-51 does not assert a paused-clock case.
   Registered owners capture in stable registration order before the first system tick.
4. Advance candidate input edges and tick count, then run systems in existing registration order.
   Systems observe the captured pre-update owner values for the full tick.
5. Stage clock advance and checked flow/transition processing with current trigger semantics, at
   most one transition, and trigger consumption only on commit. A failed condition/transition
   evaluation aborts this phase and follows rollback. Build the generic `SimTickOutcome` from
   pre/post clock and flow state and the selected transition.
6. Commit owners in stable registration order with their capture and completed outcome. Any
   capture, system, flow, or owner-commit failure restores the entire checkpoint. Successful
   rollback returns `FAILED_RETRYABLE`; failed rollback returns terminal `FATAL_ROLLBACK` as above.
   Neither path emits a signal or creates a log entry.
7. On success, retain the checkpoint and return `PREPARED` with the outcome, detached validated
   output bundle, and ordered staged signal batch. Participants emit no signals during tick phases.
   The runner must finish codec encoding/validation and complete-row preparation before finalizing
   this handle. Participants and the runtime port remain rollback-capable through that preparation.

The S2 port owner's checkpoint is the sole rollback authority for its pending commands, results,
consumed-sequence state, next sequence, and failure metadata. It also supplies these runtime values
in `MatchSim.snapshot()` and `state_hash()`. The port's internal `begin_tick`/`commit_tick`/
`rollback_tick` transaction is nested inside the sim transaction: `commit_tick` may stage queue and
result pruning, but retains its prior snapshot until the sim finalizes. `abort_prepared_tick` then
restores port state together with every other owner after any owner/system/output-codec/log-row
preparation failure. Finalization only consumes the matching append token or replay receipt and
discards the retained checkpoint; it performs no fallible port commit, allocation, callback, or
additional state mutation. Standalone finalization follows the same documented standalone
transaction path. For replay, one row transaction begins before injection of new recorded commands
and covers sequence validation, canonical queue readback, checked tick, output validation, and
receipt finalization. `begin_replay_row` opens the port's internal transaction and sim-owner
checkpoint before injection; `tick_replay_row` reuses them. A failed row restores the exact pre-row
queue and sequence; carried commands
are the prior committed survivors. Live retry retains the already sampled and enqueued candidate
with its assigned sequences. After each finalized replay row, the shared replay coordinator reads
port survivors for the next row in both direct and runner-driven playback.

`raise_trigger` appends to the pending list. Triggers raised by systems in step 4 or by callers
between ticks are evaluated in step 7 of the current (or next) tick.

Input edges: `just_pressed` is held in current and not in previous; `just_released` the reverse.
Before the first tick both frames are zero.

`snapshot()` returns a `Dictionary` built in this key order: `tick`, `rng_seed`, `rng_state`,
`state`, `ticks_in_state`, `period`, `elapsed_ticks`, `finished`, `pending_triggers`
(`Array[StringName]`), current and previous input state, and `systems` (array of
`{"id": system_id(), "data": snapshot()}` in registry order, including owners). It includes
deterministic owner setup identity/state needed to reproduce future captures. Rollback checkpoints
may contain more than the public/hash snapshot.
`state_hash()` is the lowercase hex SHA-256 (`HashingContext.HASH_SHA256`) of
`var_to_bytes(snapshot())`.

Purity: files under `game/match/` (except `match_runner.gd`) must not reference `EventBus`,
`Input`, `Time`, `OS.get_ticks_msec`/`OS.get_ticks_usec`, or call the global `randi`, `randf`,
`randfn`, `randi_range`, `randf_range`, `randomize` or `seed` functions. The same ban on global
random, `Time`, `OS.get_ticks_*` and `Input` applies to `game/ball/`, `game/player/`,
`game/rules/`, `game/setpiece/` and `game/ai/`.

### 2.6 Match flow data

`MatchStateIds` constants: `PRE_MATCH = &"pre_match"`, `KICK_OFF = &"kick_off"`,
`IN_PLAY = &"in_play"`, `STOPPAGE = &"stoppage"`, `HALF_TIME = &"half_time"`,
`FULL_TIME = &"full_time"`.

`MatchTriggers` constants: `KICK_OFF_TAKEN = &"kick_off_taken"`,
`WHISTLE_BLOWN = &"whistle_blown"`, `PLAY_RESUMED = &"play_resumed"`,
`RESTART_KICK_OFF = &"restart_kick_off"`.

`MatchTransitionDef` (`Resource`):
`enum PeriodEffect { NONE, START, ADVANCE }`; `@export var to: StringName`;
`@export var trigger: StringName = &""` (empty = no trigger needed);
`@export var condition: MatchCondition` (null = no condition);
`@export var period_effect: PeriodEffect = PeriodEffect.NONE`.
It is eligible when (`trigger` is empty or is in the pending triggers) and its checked condition
evaluation succeeds with `value = true` (or the condition is null).

`MatchStateDef` (`Resource`): `@export var id: StringName`, `@export var clock_runs: bool = false`,
`@export var ends_period: bool = false`, `@export var terminal: bool = false`,
`@export var transitions: Array[MatchTransitionDef] = []`.

`MatchFlowConfig` (`Resource`): `@export var initial_state: StringName = &"pre_match"`,
`@export var states: Array[MatchStateDef] = []`, `get_state(id: StringName) -> MatchStateDef`
(null if absent), `validate() -> PackedStringArray` with one error per problem: empty or duplicate
state id; `initial_state` not found; transition `to` not found; a transition with empty trigger
and null condition; no state with `terminal = true`.

`ConditionEvaluationResult` is `(ok: bool, value: bool, error: Error)`. Success uses `error = OK`
and carries the boolean condition value; failure uses `ok = false`, `value = false`, and a non-OK
error. `MatchCondition.evaluate_checked(sim: MatchSim) -> ConditionEvaluationResult` is the checked
API; the base returns successful false. `ConditionAll` evaluates children in order, immediately
propagates the first failure unchanged, and otherwise returns true only if every child succeeds
with true (an empty list succeeds with true). `TransitionEvaluationResult` is `(ok: bool,
transition: MatchTransitionDef, error: Error)`;
`MatchStateMachine.evaluate_transition_checked(sim, triggers) -> TransitionEvaluationResult`
returns the first eligible transition with `(true, transition, OK)`, successful no-match as
`(true, null, OK)`, or condition evaluation failure as `(false, null, non-OK)`. A plain nullable
transition result cannot represent checked flow failure.

`MatchCondition` (`Resource`): `evaluate_checked(sim: MatchSim) -> ConditionEvaluationResult`.
For acceptance injection, a test-owned fixture at
`tests/unit/match/fixtures/injectable_failure_condition.gd` extends `MatchCondition` and has an
explicit no-argument constructor plus `fail_enabled: bool = false`. Its
`evaluate_checked(sim: MatchSim) -> ConditionEvaluationResult` returns
`ConditionEvaluationResult(false, false, ERR_FAILED)` when enabled and
`ConditionEvaluationResult(true, true, OK)` otherwise. Evaluation does not mutate the flag; the
test enables it before the candidate tick and disables it before explicit retry. This fixture is
not a production class or failure switch and does not change generic flow semantics.
- `ConditionTicksInState`: `@export var ticks: int = 1`; true when `sim.flow.ticks_in_state >= ticks`.
- `ConditionPeriodExpired`: `enum Which { ANY, LAST, NOT_LAST }`, `@export var which: Which = ANY`;
  true when `sim.clock.is_period_expired()` and (`ANY`, or `LAST` and `is_last_period()`, or
  `NOT_LAST` and not `is_last_period()`).
- `ConditionAll`: `@export var conditions: Array[MatchCondition] = []`; true when all are true
  (empty list is met).

`MatchStateMachine` (`RefCounted`): `_init(p_config: MatchFlowConfig)`, vars `config`,
`current: StringName` (starts at `initial_state`), `ticks_in_state: int` (starts 0),
`evaluate_transition_checked(sim: MatchSim, triggers: Array[StringName]) ->
TransitionEvaluationResult` (first eligible transition, successful null no-match, or propagated
condition failure), `current_def() -> MatchStateDef`.

### 2.7 Applying a transition

Stage transition state and notifications transactionally. On successful publication, preserve
the existing order and payload exactly: set `current = to`, `ticks_in_state = 0`;
`state_changed(from, to)`; if `period_effect == START`, `period_started(clock.period)`; if
`ADVANCE`, call `clock.start_next_period()` then `period_started(clock.period)`; if the new state
has `ends_period`, `period_ended(clock.period)`; if it has `terminal`, mark finished and emit
`finished`. The runner publishes this staged batch only after the prepared log append commits. A
failed phase restores transition state and discards the batch.

### 2.8 Default flow (`default_match_flow.tres`), placeholder until S3

Initial state `pre_match`. Transitions listed in evaluation order. Entries marked P are
placeholders so the skeleton runs without rules; S3 replaces them in data.

| State | clock_runs | ends_period | terminal | Transitions (to: trigger / condition / effect) |
|---|---|---|---|---|
| `pre_match` | no | no | no | `kick_off`: TicksInState(1), START (P) |
| `kick_off` | no (TBC-RE) | no | no | `in_play`: `kick_off_taken`; `in_play`: TicksInState(1) (P) |
| `in_play` | yes | no | no | `stoppage`: `whistle_blown`; `half_time`: PeriodExpired(NOT_LAST) (P); `full_time`: PeriodExpired(LAST) (P) |
| `stoppage` | yes (TBC-RE) | no | no | `half_time`: PeriodExpired(NOT_LAST); `full_time`: PeriodExpired(LAST); `in_play`: `play_resumed`; `kick_off`: `restart_kick_off` |
| `half_time` | no | yes | no | `kick_off`: TicksInState(1), ADVANCE (P) |
| `full_time` | no | yes | yes | none |

With period length P ticks and 2 periods, a match with no triggers runs: tick 1 to `kick_off`
(period 1 starts), tick 2 to `in_play`, clock advances on ticks 3..P+2, tick P+2 to `half_time`,
tick P+3 to `kick_off` (period 2), tick P+4 to `in_play`, tick 2P+4 to `full_time`.

## 3. Runner, input log and replay

### 3.1 `InputSource`

Base class. `fill_frame(tick: int, frame: InputFrame,
commands: DetachedCommandBundleBuilder) -> bool` fills `frame` and the builder for `tick` and returns
true, or returns false when no more input exists (base: clears both, returns true). The runner
passes a fresh empty builder for the source to fill; on success it copies the sampled frame and seals the submission bundle. False is terminal source exhaustion: the runner stops and never polls the source again. The submission bundle is not necessarily the executed candidate: live S2 validates/enqueues its records, then decodes the port-assigned canonical `queued_command_snapshots()` readback into a distinct final typed candidate bundle paired with the sampled frame. That frame/readback pair is the exact candidate passed to `tick_checked`, retained by `PreparedTick`, encoded by the codec, and recorded. In non-S2 composition, the sealed submission bundle is the candidate; for commandless input, the fresh builder seals to an immutable empty bundle. The
bundle is an ordered copy of existing concrete typed command records; the source does not flatten
them into dictionaries or invent a command schema. Live input and replay both use this same
frame-plus-bundle route. `layout_hash() -> String` identifies the action layout (base: `""`).
S9's `InputSampler` extends it.

### 3.2 `ReplayHeader` and `InputLog`

`ReplayHeader` current contract carries `format_version: int = 3`, `game_version: String`, `seed: int`,
`mod_set_hash: String`, `action_layout_hash: String`, `tick_rate: int = 60`, `slot_count: int = 1`,
`axes_per_slot: int = 2`, and a deterministic setup fingerprint. The fingerprint is SHA-256 over a
canonical, version-tagged serialization with explicit value type tags and stable key ordering. It
covers the effective match configuration/resources plus the ordered registered participant
identities and versions, each participant's deterministic initial setup/state, and each injected
provider's stable identity/version/configuration/initial state as attested by its unique owning
participant. It includes all deterministic setup inputs that can alter future simulation;
transient presentation or machine-local values are excluded. `to_dict() -> Dictionary`,
`static from_dict(d: Dictionary) -> ReplayHeader`
(null when a required field for that record's `format_version` is missing or wrongly typed),
`is_compatible_with(p_mod_set_hash: String,
p_expected_action_layout_hash: String, p_expected_setup_fingerprint: String) -> bool` (true only
for playback format v3 with a correctly typed non-empty setup fingerprint, all three identities
equal, and `tick_rate == MatchSim.TICKS_PER_SECOND`). The expected values come from the current
configured action source/action set and freshly prepared current match setup; comparing the
header's action hash to itself is forbidden.

Replay migration policy: S1's legacy baseline is format v1. Format v1 and v2 header/input
structures remain parseable and round-trip compatible: serialization preserves the original
`format_version` and all fields defined for that version, without adding later-version fields to
legacy records or dropping version-specific fields. Version-specific fingerprint handling is:
format v1 omits the setup fingerprint on wire and parses with an empty in-memory value; format v2
requires the field to exist and be a String, preserving its value including the empty string on
parse/round-trip; format v3 requires a present, correctly typed, non-empty fingerprint. Playback accepts exactly format v3. Direct `MatchReplay.run` rejects a null log/header as
`INVALID_RECORD`, then rejects any typed header whose version is not v3 as `INCOMPATIBLE_HEADER`,
before starting replay composition; neither path runs extension, participant, provider, or system
setup. `MatchRunner.start` builds its replay composition first, then rejects a non-v3 header before
source polling, setup capture, tick, or publication, following its order in §3.4.
`ReplayHeader.is_compatible_with` applies the v3 format requirement together with identity and
tick-rate comparisons against the prepared current composition.
There is no supported v3-without-fingerprint variant or adapter. This contract is version-neutral
against the implementation checkout and does not assert the version or fields currently declared
by the public `ReplayHeader` class; integration preserves S2's v3 semantics.

`InputLog`: `const FORMAT_VERSION: int = 3` (current replay v3 record semantics and wire layout
remain stable), `var header: ReplayHeader`, `_init(p_header: ReplayHeader)`,
`read_replay_row(index: int) -> ReplaySourceRowResult`,
`prepare_append(prepared_tick: PreparedTick, command_bundle: EncodedCommandBundle,
output_bundle: PreparedOutputBundle) -> AppendPrepareResult`,
`commit_append(token: PreparedAppendToken) -> void`, and
`cancel_append(token: PreparedAppendToken) -> Error`. The explicitly fixture/import-only
`append_fixture_row(frame: InputFrame, command_records: Array[Dictionary],
output_records: Array[Dictionary]) -> Error` supports manual serialization fixtures and legacy raw
imports. It is never used by `MatchRunner`, does not finalize a sim tick, and makes no claim that a
simulation tick committed; a wrong-shaped frame is rejected without changing the log. `PreparedOutputBundle` is opaque and can be
created only by `S2ReplayCodec.prepare_outputs(prepared_tick: PreparedTick) -> CodecResult` from
that exact tick's validated detached `TickResult.outputs`; callers cannot pass an arbitrary output
array to the codec. A successful bundle retains the prepared-tick identity, encoded detached output
identity and exact records. Format v3 continues to encode each frame's
runtime data as the existing `runtime` array of `{ "commands": [...], "outputs": [...] }` rows;
command and output dictionaries retain the existing `S2RuntimeCommand.snapshot()` and
`S2RuntimeResult.snapshot()` field layouts and meanings. S1 does not define a second S2 command
schema. `MatchCompositionBuilder` provides exactly one `S2ReplayCodec` on its
`MatchBuildResult`; that codec converts v3 wire dictionaries to/from the existing concrete
`S2RuntimeCommand` and `S2RuntimeResult` records. Its API is `prepare_commands(command_bundle:
DetachedCommandBundle) -> CodecResult`, `decode_commands(records) -> CodecResult`,
`decode_outputs(records) -> CodecResult`,
`prepare_outputs(prepared_tick) -> CodecResult`, and
`encode_outputs(prepared_output_bundle) -> Array[Dictionary]`,
`capture_canonical_port_readback(port: S2RuntimePort) -> CanonicalPortReadbackResult`, and
`validate_replay_row(prepared_tick: PreparedTick, source_row: ReplaySourceRow,
canonical_port_readback: CanonicalPortReadback) -> ReplayValidationResult`. `prepare_outputs` accepts only the
opaque exact `PreparedTick` and obtains its validated detached `TickResult.outputs`; no API accepts
an arbitrary output array to create a prepared output bundle. Before execution, the codec converts
the exact sealed typed candidate bundle to detached v3 dictionaries and returns an opaque
`EncodedCommandBundle` carrying that source-bundle identity and the detached records. The runner
passes the final typed candidate bundle to `tick_checked`; in live S2 this is the decoded canonical
port readback, while non-S2 uses the sealed submission bundle. `PreparedTick` retains its immutable
copy and source identity, so an encoded bundle made from another candidate is not interchangeable.
`CodecResult` carries either the
appropriate detached typed/opaque bundle or a non-OK error; malformed records never become a partial
bundle. Generic `InputLog` treats codec-authored encoded bundles as opaque detached records and only
copies their rows; it contains no S2 wire encoder or typed-command conversion.
Generic S1 callers handle only the existing typed detached command/output bundles and never create
an S2-specific second command schema.

`CanonicalPortReadbackResult` carries `ok: bool`, `readback: CanonicalPortReadback | null`,
`command_bundle: DetachedCommandBundle | null`, and `error: Error`. The codec's capture method reads
the supplied port's canonical queue exactly once, validates/decodes that exact readback, and returns
the paired opaque identity and typed bundle; failure returns no readback or bundle. Callers cannot
construct a usable identity from a copied command array or from a second port read.

For live S2 composition, the runner validates the source's existing typed command records and
passes each to `S2RuntimePort.enqueue` once. It reads back `queued_command_snapshots()`, whose
assigned sequence values and canonical order are authoritative. The codec's
`capture_canonical_port_readback(port)` reads that queue exactly once, decodes it to the existing
typed command records, and returns the paired opaque readback identity and candidate bundle. Before
tick execution, `prepare_commands(candidate_bundle)` encodes this exact bundle. The
runner then calls `tick_checked(frame, candidate_bundle)` while retaining rollback state. Only the codec
may produce a `PreparedOutputBundle`, and only from the matching `PreparedTick`'s validated
detached `TickResult.outputs`; the runner cannot supply arbitrary output records. `InputLog`
`InputLog.prepare_append(prepared_tick, encoded_command_bundle, output_bundle)` obtains the exact
normalized immutable frame and retained command candidate from `PreparedTick`; it accepts no
caller-supplied frame or typed command arguments. It verifies that the encoded command source-bundle
identity matches that candidate and that the output bundle belongs to the same tick, then fully
builds/copies the exact v3 frame/command/output row and reserves its index. `AppendPrepareResult` is
either `PREPARED(token)` or `FAILED(error)`. `PreparedAppendToken._init()` is public and takes no
arguments, but an ordinary caller-created object is inert and unregistered. The opaque token is
minted only by that log through its internal minting path, is single-use, and binds the prepared-tick identity,
source/encoded-command identity, candidate-frame identity, output-bundle identity, log identity,
reserved index/generation, and exact row identity. Only the exact internally minted token object with its private registered nonce is accepted; a
caller-created object cannot reproduce that capability. Token fields and a token copy/reassembly
constructor are not public. The log verifies all
bindings and active reservation state on every use. `MatchSim.finalize_prepared_tick(prepared_tick, append_token)` requires the exact still-active tick and matching log token and consumes the prepared tick; `commit_append(append_token)` requires that same token to have been marked finalized by that sim. `finalize_prepared_tick`, `commit_append`, and `cancel_append` reject an inert caller-created token without consuming the active tick/reservation or publishing a row. Cancelled, consumed, stale, cross-log, cross-tick, independently-created-output, or row-substituted tokens are rejected and cannot publish. All validation, encoding, row construction/copying, and allocation happen before finalization, and ordinary failures abort the tick and cancel the token while rollback remains possible. No process-termination atomicity is promised: the enforceable contract is the capability pairing in normal execution. Finalization and commit are infallible, allocation-free, callback-free, with no callbacks between them; `commit_append` only publishes the already-built row. Thus the complete row is observable before staged sim signals, EventBus relays, or runner `ticked`.

The runner passes `tick_checked` the frame and detached typed command bundle represented by the
port's authoritative readback. For replay, it uses the verified canonical port readback after
recorded-command injection. The runner's success sequence is: finish all codec work; prepare the entire log row while the tick
is abortable; call infallible, allocation-free `MatchSim.finalize_prepared_tick(prepared_tick, append_token)`;
immediately call infallible, allocation-free `InputLog.commit_append(append_token)` with no callbacks between them;
then mark the `TickResult` `COMMITTED` and publish its staged batch. For replay, the source log row
is already observable and read-only: validate expected outputs, obtain the matching
`ReplayValidationToken`, finalize with that receipt, do not append or record a second row, and
publish only after successful receipt-backed finalization.

Any codec validation/encoding or log preparation failure aborts the prepared tick, cancels/releases
any reservation, and exposes no row, signal, or output. If rollback succeeds, retain the exact
sampled frame and commands for explicit retry without source polling, duplicate port enqueue, or
new sequence assignment; repeat all fallible preparation. If rollback fails, return terminal
`FATAL_ROLLBACK` and never retry. Tick execution does not start until candidate command encoding
has succeeded. Frame commands keep their existing meanings and canonical typed records; the
container adds no command schema.
`read_replay_row(index: int) -> ReplaySourceRowResult` returns one immutable row snapshot with
detached frame, command, and output values plus an opaque identity capability. `ReplaySourceRow`
has a public no-argument `_init()` that constructs an inert, unregistered row; its copied accessors
return `frame == null`, empty `command_records`, and empty `output_records`. A caller-created row
has no log-issued identity and cannot be made usable by setting values or copying a capability.
Populated rows have read-only copied accessors for `frame`, `command_records`, and `output_records`;
their identity is issued only by the exact `InputLog` for that stored index, stable row generation,
and full stored row values. Repeated reads of an unchanged row return the same internal identity.
The identity is bound to log object identity and cannot be constructed by callers, reassembled from
legacy accessor copies, or substituted after mutation of that indexed row; a stored-row mutation
invalidates its issued capability. `ReplaySourceRowResult` is `{ok: bool,
row: ReplaySourceRow | null, error: Error}`; an out-of-range index returns `(false, null,
ERR_INVALID_PARAMETER)`. Replay reads logs through this read-only API. No replay path mutates the
source log. `frame_count() -> int`, legacy `read_frame(index: int, into: InputFrame) -> bool`
(false when out of range; sets `into.tick = index`), `frame_commands(index: int) ->
Array[Dictionary]`, and `frame_outputs(index: int) -> Array[Dictionary]` remain defensive-copy
accessors for compatibility and fixtures; they are not token authority. They preserve stored order
and sequence values and return an empty array out of range. Also
`to_bytes() -> PackedByteArray`,
`static from_bytes(bytes: PackedByteArray) -> InputLog` (null when invalid or
`format_version` is newer than `FORMAT_VERSION`, including when its version-specific header fields
are missing or wrongly typed), `save(path: String) -> Error`,
`static load_file(path: String) -> InputLog`.

`ReplayInputSource`: `_init(p_log: InputLog)`; public `input_log() -> InputLog` and
`replay_header() -> ReplayHeader` accessors expose the backing log/header without private access.
Its `fill_frame` reads only the frame at `tick` and returns false past the end; it does not turn
wire command dictionaries into live source commands. The runner recognizes this source and obtains
exactly one `ReplaySourceRow` via `read_replay_row(tick)` for each index. That snapshot supplies
frame, command records, output records, and the log-issued identity capability to the one
composition-provided `S2ReplayCodec`; legacy accessor copies are never token authority. The codec decodes commands to the
existing concrete `S2RuntimeCommand` records. The runner compares the full pending queue with
commands carried from the previous committed frame, matching sequence and full canonical payload;
it does not re-enqueue those survivors. Only the new globally contiguous sequence suffix is
injected once through `S2RuntimePort.enqueue_replay_commands`. Outputs are decoded separately as
expected results.
`layout_hash()` reflects the recorded header for access only, never as the current expected
identity. Live sources instead provide detached typed commands through the builder; both paths use
the same codec and port without introducing an S1 command payload schema.

For `source is ReplayInputSource`, `MatchRunner.start` calls
`MatchCompositionBuilder.build_replay(request)`; for other sources it calls
`MatchCompositionBuilder.build(request)`. Replay first builds fresh participant/provider instances,
then checks format, non-empty explicit current
`request.action_layout_hash`; missing/empty identity or any header mismatch returns
`ERR_INVALID_PARAMETER` before source polling, setup capture, tick, log append, or publication.
It checks format v3, mod-set hash, current action-layout identity, freshly built current setup
fingerprint, and fixed tick rate. Only after those checks does replay call the fresh port's
`reset_runtime()` exactly once. It clears transient pending commands, results, consumed-sequence
state, next sequence, and failure metadata, while preserving fresh provider references, setup,
initialization, wind/environment values, and all other injected dependencies. It never clears or
replaces provider injection. If reset returns false, replay fails with a typed terminal error before
polling, ticking, or publication. Live input may use the base empty layout identity. The current
setup fingerprint comes from the actual effective config, ordered fresh participants, and provider
claims prepared for this runner.

### 3.3 `MatchReplay`

`MatchCompositionRequest` is the sole typed setup input: `config: MatchConfig`,
`systems: Array[SimSystem]`, `mod_set_hash: String`, explicit current `action_layout_hash: String`,
`extension_points: ExtensionPoints`, and `s2: S2RuntimePort`. The port owns contact source/solver,
ball initialization, wind policy, player initialization, fatigue option, and pitch/environment
initialization. `MatchCompositionBuilder.build(request)` constructs a live sim from supplied
objects, creates and registers exactly one `S2RuntimePortOwner` for the request's port, and derives
its setup fingerprint and single `S2ReplayCodec` in `MatchBuildResult`. `build_replay(request)`
follows this executable order:

1. Construct the effective ordered registry once. Clone each mutable registered participant
   exactly once through its generic no-argument factory, replacing entries in place, and collect
   each result's `owned_provider_claims`. Apply the stateless participant self-reuse and provider
   reuse rules above, each scoped to the separate live and replay registries. The S2 owner adapter
   is the final registered entry and is cloned once through the
   same generic factory, yielding a fresh unbound adapter.
2. Validate factory-result claim shape and capabilities, reject every repeated provider object
   reference in the effective ordered registry (including stateless repeats and repeats by one
   owner), and require unique ownership. These claims refer to fresh initial instances and are
   the pre-port source of provider identity; normal `setup(sim)` has not run yet.
3. Build `S2ProviderBindings` only from these validated fresh result claims. The S2 composition
   builder invokes the separate typed factory
   `S2RuntimePort.create_replay_instance(bindings: S2ProviderBindings) -> S2ReplayInstanceResult`
   exactly once. Its result is `{ok: bool, port: S2RuntimePort | null, error: Error}` with success
   `(true, fresh_port, OK)` and failure `(false, null, non-OK)`. The port copies stable
   configuration and transient runtime setup but never clones providers. Attach that exact fresh
   port to the fresh unbound adapter once with `attach_port(port)`, then verify adapter-to-port and
   binding-to-claim provider object identity.
4. Construct the fresh sim with the ordered fresh registry and port. Call normal `setup(sim)` exactly
   once. Require each owner's `SetupResult.owned_provider_claims` to match that owner's
   factory-result claims in count, order, exact provider object identity, stable strings, and
   transaction capability. Reject any mismatch before fingerprint acceptance, capture, or tick.
   Setup confirms the factory claims; it is not their pre-port source.
5. Only after setup and claim agreement, compute and accept the fresh setup fingerprint, then start
   replay capture.

Missing/failed factories, malformed or shared claims, stale bindings, failed/repeated attachment,
identity mismatch, or a setup/factory claim mismatch rejects the build before replay capture or
tick. No provider is cloned twice, no second registry is introduced, and the original request graph
is not mutated, reset, set up, or ticked.
The original request graph is never reset or ticked. Stable fingerprints use initial configuration
and claims; runtime snapshots include advanced owner and port state. Failed-tick rollback restores
each fresh instance to its exact immediate pre-tick state. The build result owns one
`ReplayValidationAuthority`; the builder injects that same private reference into its `MatchSim`
and single codec, and no caller receives a mint/consume method.

`MatchReadinessBlocker` is an immutable record with `code: Code`, `subject: StringName`, and
`message: String`. Its nested `Code` enum is `MISSING_REQUIRED_INPUT`, `INVALID_CONFIGURATION`,
`INVALID_TICK_RATE`, `UNSAFE_EXTENSION`, `PARTICIPANT_SETUP_FAILED`, and
`PROVIDER_OWNERSHIP_FAILED`. `subject` identifies a stable input key or participant/provider
identity when known and is empty only when no single subject applies. The diagnostic message is
not identity or fingerprint input. `MatchReadinessReport` is the single immutable public report
type for build blockers and evaluated replay readiness; it contains a detached
`blockers: Array[MatchReadinessBlocker]` and `is_ready() -> bool`, true exactly when the list is
empty.

`MatchCompositionBuilder.build(request)` and `build_replay(request)` each return a positional
immutable `MatchBuildResult` with fields in this order: `ok: bool`, `sim: MatchSim | null`,
`codec: S2ReplayCodec | null`, `setup_fingerprint: String`,
`readiness: MatchReadinessReport`, `error: Error`. Every result has a non-null readiness report.
Success is `(true, non-null sim, non-null single codec, non-empty fingerprint, ready report, OK)`.
Failure is `(false, null, null, empty fingerprint, report with one or more blockers, non-OK)`.
The report does not replace the `error`; diagnostic message text is not fingerprinted.

`static run(request: MatchCompositionRequest, log: InputLog) -> MatchReplayResult`, where
`MatchReplayResult` contains `sim: MatchSim | null`, `error: Error`, typed
`replay_failure: ReplayFailure` (`NONE` when there is no replay failure),
`fatal_reason: StringName` (empty except for `FATAL_ROLLBACK`),
`readiness_evaluation: ReadinessEvaluation`, and `readiness: MatchReadinessReport`.
`ReplayFailure` is one of `NONE`, `INVALID_RECORD`, `INVALID_LINKAGE`, `INCOMPATIBLE_HEADER`,
`PORT_RESET_FAILED`, `TICK_FAILED`, `OUTPUT_MISMATCH`, or `FATAL_ROLLBACK`.
`ReadinessEvaluation` is one of `NOT_EVALUATED`, `PREFLIGHT_ONLY`, or `BUILDER_COMPLETE`.

`readiness_evaluation` is `NOT_EVALUATED` for a null log/header or any typed header whose version
is not v3. In these cases `readiness` is a non-null empty placeholder, and `readiness.is_ready()`
is not evidence of composition readiness; the record/version failure is reported by
`error`/`replay_failure`, not as a build blocker. It is `PREFLIGHT_ONLY` for a null request or a
dependency-shareability preflight that returns before replay composition is built. The report may
then carry known blockers (including the generic `build(null)` missing-config diagnostic), but it
is incomplete and may omit other composition blockers. `PREFLIGHT_ONLY` remains incomplete even
when its report is empty or `is_ready()` returns true. It is `BUILDER_COMPLETE` only after
`MatchCompositionBuilder.build_replay(request)` returns; the result then preserves that builder's
complete readiness report through builder failure, later compatibility, reset, row, tick, success,
or fatal rollback outcomes. Callers must inspect `readiness_evaluation` before treating the report
as a complete readiness result.

`FATAL_ROLLBACK` is distinct from ordinary/retryable `TICK_FAILED`; direct replay returns
`sim == null`, non-OK `error`, this typed failure, a non-empty `fatal_reason`,
`readiness_evaluation == BUILDER_COMPLETE`, unchanged source log, and no publication. A
compatibility or row failure after composition returns `sim == null`, non-OK error, typed replay
failure, and the evaluated builder report. A successful replay returns its sim, `OK`,
`replay_failure == NONE`, `readiness_evaluation == BUILDER_COMPLETE`, and a ready builder report.
Direct replay and live runner startup use the same request and builder; replay uses the recorded
seed but never treats the header as current action-layout identity. It checks v3 format, mod hash,
explicit current action-layout hash, setup fingerprint, and tick rate before polling, owner capture,
tick, append, or publication. After composition evaluation, missing config, contact source/solver,
player/fatigue, ball/wind setup, unsafe hooks, or other required inputs remain typed readiness
blockers.

Direct replay validates `log` and `log.header` first; a null value returns `INVALID_RECORD`, and any
typed `format_version != 3` returns `INCOMPATIBLE_HEADER`, both before replay composition setup.
A null request may return the generic builder's missing-config diagnostic without completing the
replay build. The dependency-shareability preflight may accumulate known blockers and return
without building. These early paths have `readiness_evaluation == PREFLIGHT_ONLY` and a possibly
partial report. A null log/header or non-v3 typed header instead has
`readiness_evaluation == NOT_EVALUATED` and the empty placeholder. Only a valid v3 request that
passes preflight starts `build_replay(request)`. When it returns,
`readiness_evaluation == BUILDER_COMPLETE` and its builder report is complete. The direct path then
checks the header against that build and resets the fresh port exactly once before the first row.
Runner-driven replay follows the §3.4 order and checks the header after its composition build. A
false reset returns `PORT_RESET_FAILED` with no tick or publication. For each index, read exactly one
`ReplaySourceRow` snapshot and capability from the source log; decode its frame, commands, and
expected outputs from that object. Begin the row transaction before injecting any new recorded
commands. Call `begin_replay_row(source_row)` before sequence validation or injection to retain the
whole sim/owner checkpoint. Compare carried commands with prior committed survivors by sequence,
full canonical payload, and order; reject missing, changed, duplicated, or reordered entries and
never enqueue survivors again. New entries must be the next contiguous sequence suffix and are injected once with
their recorded sequences. Capture the canonical port readback once through the codec and require
its exact values and order to equal the row. Call `tick_replay_row` with the retained handle and
candidate; it runs checked phases without taking a second checkpoint. Compare generated outputs with
expected outputs, including command sequence/kind linkage, then let the codec validate the exact
row and readback and privately register a receipt. `finalize_replay_tick(prepared_tick, token)`
consumes that receipt once. Any validation, injection, tick, or receipt failure aborts the prepared
tick and restores the exact pre-row port queue and sequence; fatal restore failure yields
`FATAL_ROLLBACK`, distinct from `TICK_FAILED`. After successful finalization, publish and have the
shared coordinator read committed survivors for the next row. Rejected direct replay always has
`sim == null`; the source log is unchanged and never receives a second row. V3 command meanings
and wire layouts stay unchanged, and generic S1 adds no command schema. Fatigue snapshot fields
remain unchanged and are consumed once at their existing input phase; owner-derived fatigue must
not reapply them.

### 3.4 `MatchRunner` (`Node`)

```
signal ticked(tick: int)
signal input_ended
var sim: MatchSim            # null until start
var input_log: InputLog
func start(request: MatchCompositionRequest, source: InputSource) -> Error
func stop() -> void
func is_running() -> bool
func step_once() -> RunnerResult
func interpolation_fraction() -> float
```

- `start` accepts the typed composition request (config, ordered systems, current mod/action
  identities, extension points, and `S2RuntimePort`) and uses the same composition builder as
  direct replay. For `ReplayInputSource` it calls `build_replay(request)`; otherwise it calls
  `build(request)` and retains the supplied instances.
  Contact source/solver and all player/fatigue, ball, wind, and environment setup are supplied
  through that request's port. Missing setup dependencies remain typed readiness blockers.
  It returns `ERR_UNCONFIGURED` if `Engine.physics_ticks_per_second !=
  MatchSim.TICKS_PER_SECOND`, `ERR_INVALID_PARAMETER` if `config.validate()` is not empty, or the
  setup/registration error if any participant or provider is unsupported or ownership is
  ambiguous; otherwise builds the sim, adds systems, creates `input_log` with a header
  (`game_version` from `ProjectSettings` `application/config/version`, `seed`,
  `request.mod_set_hash`, `request.action_layout_hash` (current expected identity), shape from
  config, and deterministic
  setup fingerprint for versioned initial owner/system/provider setup), connects relays and returns
  `OK`. Live mode creates its own recording `InputLog`. Replay mode uses the `ReplayInputSource`
  backing log as read-only `input_log` and never appends a second recording. A live source may use
  the base empty action-layout identity. For a `ReplayInputSource`, the composition build
  completes before replay-header checks. An empty/missing `request.action_layout_hash` rejects
  before polling, capture, tick, log append, or publication. Otherwise it first checks that its
  header is format v3 and has a valid fingerprint, then compares mod hash, explicit current
  action-layout identity, freshly built setup fingerprint and tick rate. Any mismatch returns
  `ERR_INVALID_PARAMETER` before the runner can
  sample input or mutate/publish sim state. On a match, call the fresh replay port's
  `reset_runtime()` exactly once before frame 0; reset failure returns `PORT_RESET_FAILED`.
- `RunnerResult` is a record with `status`, `error`, and optional typed `replay_failure`; status is
  `COMMITTED`, `PREPARATION_FAILED`, `TICK_FAILED`, `REPLAY_FAILED`, `FATAL_ROLLBACK`,
  `SOURCE_EXHAUSTED`, `STOPPED`, or `FINISHED`. `REPLAY_FAILED` is terminal and reports
  `INVALID_RECORD`, `INVALID_LINKAGE`, `INCOMPATIBLE_HEADER`, `PORT_RESET_FAILED`, `TICK_FAILED`,
  `OUTPUT_MISMATCH`, or `FATAL_ROLLBACK`. Direct fatal replay has `sim == null`, non-OK error,
  non-empty `fatal_reason`, preserved readiness, unchanged source log and no publication.
  Source exhaustion, ordinary stop, sim finish, replay failure and fatal rollback are terminal
  runner states with distinct statuses; `input_ended` is emitted only for source exhaustion. Fatal
  rollback never offers retry. A recoverable tick/preparation failure waits for explicit retry.
- Live input treats records filled by `InputSource.fill_frame` as submissions. It validates and
  enqueues each exactly once through `request.s2.enqueue`. The port is the sole sequence authority:
  the codec's `capture_canonical_port_readback(port)` reads and decodes the authoritative queue once,
  returning its assigned sequences and canonical order as a distinct final candidate paired with
  the sampled frame. That exact pair is used for the v3 row and checked tick. Retain the exact
  frame/command candidate and port-assigned
  sequences across every
  preparation or retry failure; do not poll again, enqueue again, or assign replacement sequences.
  Port tick rollback restores the same pending commands and sequence state.
- Replay input obtains one `ReplaySourceRow` from `input_log.read_replay_row(tick)` and treats its
  command records as the full snapshot of the pending queue before that frame. Immediately after
  reading the row, call `sim.begin_replay_row(row)` so the whole checkpoint predates sequence
  validation and injection. After the exact canonical readback, call `sim.tick_replay_row` with its
  handle. After the prior committed frame, the port's outstanding pending snapshots must be the
  exact carried set in the next row. Compare carried commands by recorded sequence and full
  canonical payload; reject missing, changed, duplicated, or non-canonically reordered carried
  entries and never enqueue them again. Row entries absent from that set are newly introduced;
  require their sequences to form the exact next contiguous suffix and inject only those once with
  recorded values. Then require full canonical pending readback to equal the entire row, preserving
  port order and all payload fields. Validate outputs against commands in the full row, including
  carried commands that complete later. After each successful tick, the runner observes surviving
  pending commands through the existing public `queued_command_snapshots()` seam after commit; they
  seed the next comparison. The live
  builder is not used to inject replay rows. Reset the runtime port once at replay startup; replay
  is terminal and never records a second log. `input_log` refers to the source log during replay.
- In live mode, encode/validate commands before tick execution, then call `sim.tick_checked` with
  the candidate. A command-encoding failure occurs before tick execution and leaves sim state
  untouched. For `PREPARED`, encode/validate detached outputs and prepare/reserve the complete
  frame/commands/outputs row while rollback remains possible. On output codec or log preparation
  failure, abort the prepared tick, cancel any reservation, return `PREPARATION_FAILED`, and retain
  the exact candidate. The next explicit `step_once()` retries without polling or re-enqueueing. On
  `FAILED_RETRYABLE`, retain the candidate and return `TICK_FAILED`; the next explicit call retries
  the same candidate. `_physics_process` does not automatically retry. After both sides are
  prepared, finalize the sim then commit the prepared row, both infallible/allocation-free and with
  no callbacks between. Mark the result `COMMITTED`, then publish signals. Clear the candidate only
  after row commit and publication. If `fill_frame` returns false before a candidate exists, stop,
  emit `input_ended`, return `SOURCE_EXHAUSTED`, and never poll again.
- On `FATAL_ROLLBACK`, discard the candidate, mark the runner terminal/stopped, and return
  `FATAL_ROLLBACK` without append or publication. The sim remains latched stopped and non-retryable.
- In replay mode, invalid replay data or output mismatch aborts the prepared tick and returns
  terminal `REPLAY_FAILED` with a typed reason; no tick is finalized and no MatchSim signal,
  EventBus relay, or `ticked` is published. The source log is not modified. The runner exposes its
  terminal replay state through `RunnerResult.status/replay_failure` and refuses further steps.
- After live sim finalization and row commit, mark the tick `COMMITTED` and publish
  `TickResult.signal_batch` through the existing MatchSim signals in their existing order
  (connected handlers relay to EventBus), then emit `ticked`. Stop the runner once its sim finishes.
  A failed, fatal, or no-op tick does not emit `ticked` or relay events.
- `_physics_process` steps only while running and not waiting for an explicit retry. Nothing in
  the runner uses `_process` for sim work.
- Relays (connected in `start`): `state_changed` to `EventBus.match_state_changed(from, to,
  sim.tick_count)`, `period_started` to `EventBus.match_period_started`, `period_ended` to
  `EventBus.match_period_ended`, `finished` to `EventBus.match_finished(sim.tick_count)`.
  Relays occur only after append-before-relay commit; listeners must not mutate the sim (ADR-004).
- `interpolation_fraction()` returns `Engine.get_physics_interpolation_fraction()` for
  presenters that interpolate manually.

## 4. Pitch geometry

`PitchGeometry` (`Resource`), metres. Coordinates: origin at the centre of the halfway line,
+Y up, X along the length (try lines at x = ±L/2; `end` is `1` for +X and `-1` for -X),
Z across (touchlines at z = ±W/2).

| Field | Type | Default | Note |
|---|---|---|---|
| `field_length` | float | 100.0 | try line to try line, TBC-RE |
| `field_width` | float | 70.0 | touchline to touchline, TBC-RE |
| `in_goal_depth` | float | 10.0 | try line to dead-ball line (law range 6..22), TBC-RE |
| `line_22_from_try` | float | 22.0 | TBC-RE |
| `line_10_from_halfway` | float | 10.0 | TBC-RE |
| `line_5_from_try` | float | 5.0 | TBC-RE |
| `line_15_from_touch` | float | 15.0 | TBC-RE |
| `line_5_from_touch` | float | 5.0 | TBC-RE |
| `goal_post_gap` | float | 5.6 | inside edges, TBC-RE |
| `crossbar_height` | float | 3.0 | TBC-RE |
| `goal_post_height` | float | 16.0 | PROVISIONAL, visual only |

Methods: `half_length() -> float`, `half_width() -> float`, `try_line_x(end: int) -> float`
(`end * L/2`), `dead_ball_line_x(end: int) -> float` (`end * (L/2 + in_goal_depth)`),
`line_22_x(end: int) -> float` (`end * (L/2 - line_22_from_try)`),
`is_in_field_of_play(p: Vector3) -> bool` (`|x| < L/2` and `|z| < W/2`),
`is_in_goal(p: Vector3, end: int) -> bool` (`L/2 <= end*x < L/2 + in_goal_depth` and `|z| < W/2`),
`is_in_touch(p: Vector3) -> bool` (`|z| >= W/2` and `|x| < L/2`),
`is_beyond_dead_ball_line(p: Vector3) -> bool` (`|x| >= L/2 + in_goal_depth`),
`validate() -> PackedStringArray` (error per non-positive length/width/in-goal/post field, and
when `line_22_from_try >= L/2` or `2 * line_15_from_touch >= W`).
The line-ownership rules above (try line belongs to in-goal, touchline is in touch) are the law;
S3 confirms them against RE.

## 5. Data resources

Every class has `class_name`, `##` docs, typed `@export` fields with the defaults below, and a
`validate() -> PackedStringArray` that returns one message per problem (empty when valid).
Display names that the UI shows as labels are translation keys (`*_key`); proper nouns from the
game database (team and player names) are data, not keys.

**`PlayerAttributeSchema`**: `attribute_ids: Array[StringName]` (PROVISIONAL list),
`position_ids: Array[StringName]` (PROVISIONAL), `min_value: int = 0`, `max_value: int = 100`,
`default_value: int = 50`; `has_attribute(id: StringName) -> bool`,
`clamp_value(value: int) -> int`. validate: `min_value < max_value`, default inside range,
no duplicate ids. `default_attribute_schema.tres` lists attributes `speed`, `acceleration`,
`agility`, `strength`, `stamina`, `handling`, `passing`, `kicking_power`, `kicking_accuracy`,
`tackling`, `breaking_tackles`, `aggression`, `discipline`, `lineout`, `scrummaging` and positions
`loosehead_prop`, `hooker`, `tighthead_prop`, `lock`, `blindside_flanker`, `openside_flanker`,
`number_eight`, `scrum_half`, `fly_half`, `wing`, `inside_centre`, `outside_centre`, `full_back`
(all PROVISIONAL until p1-players-lead reports).

**`PlayerProfile`**: `enum Foot { RIGHT, LEFT }`; `id: StringName`, `first_name: String`,
`last_name: String`, `known_as: String = ""`, `nationality: StringName`, `birth_year: int = 1980`,
`height_cm: int = 185`, `weight_kg: int = 100`, `preferred_foot: Foot = RIGHT`,
`primary_position: StringName`, `secondary_positions: Array[StringName]`,
`attributes: Dictionary[StringName, int]` (PROVISIONAL keys from the schema);
`display_name() -> String` (`known_as` if set, else `first_name + " " + last_name`, trimmed);
`get_attribute(id: StringName, schema: PlayerAttributeSchema) -> int` (value, or
`schema.default_value` if absent). `validate(schema: PlayerAttributeSchema = null)`: empty id,
height/weight not positive; with a schema, attribute keys not in the schema and values out of range.

**`Kit`**: `id: StringName`, `primary_color: Color = Color.WHITE`,
`secondary_color: Color = Color.BLACK`, `shorts_color: Color = Color.WHITE`,
`socks_color: Color = Color.WHITE`, `number_color: Color = Color.BLACK`,
`pattern: StringName = &"plain"` (PROVISIONAL), `jersey_texture_path: String = ""` (asset path,
resolved through the mod runtime). validate: empty id.

**`Stadium`**: `id: StringName`, `name: String`, `city: String`, `country: StringName`,
`capacity: int = 0`, `pitch: PitchGeometry`, `scene_path: String = ""`,
`crowd_ambience_path: String = ""`, `has_roof: bool = false` (PROVISIONAL). validate: empty id,
negative capacity, null pitch, pitch errors.

**`Team`**: `id: StringName`, `name: String`, `short_name: String` (3 letters),
`nation: StringName`, `home_kit: Kit`, `away_kit: Kit`, `home_stadium: Stadium`,
`squad: Array[PlayerProfile]`, `default_lineup: Array[StringName]` (player ids, starters first),
`captain_id: StringName`, `goal_kicker_id: StringName`, `ratings: Dictionary[StringName, int]`
(PROVISIONAL); `find_player(id: StringName) -> PlayerProfile` (null if absent). validate: empty
id, duplicate player ids in squad, lineup id not in squad, duplicate lineup ids, captain or goal
kicker set but not in squad, null home kit.

**`RulesConfig`** (law parameters; S3 extends it):

| Field | Type | Default | Note |
|---|---|---|---|
| `period_count` | int | 2 | TBC-RE |
| `period_game_seconds` | int | 2400 | displayed length of one period (40 min) |
| `players_per_side` | int | 15 | |
| `replacements_allowed` | int | 7 | PROVISIONAL |
| `points_try` | int | 5 | TBC-RE |
| `points_conversion` | int | 2 | TBC-RE |
| `points_penalty_goal` | int | 3 | TBC-RE |
| `points_drop_goal` | int | 3 | TBC-RE |
| `points_penalty_try` | int | 5 | 2007 law: try plus conversion attempt; TBC-RE |
| `penalty_try_awards_conversion` | bool | true | 2007 law; modern law is false; TBC-RE |
| `sin_bin_game_seconds` | int | 600 | TBC-RE |
| `extra` | Dictionary[StringName, float] | {} | PROVISIONAL bag for RE law parameters until promoted to fields |

validate: `period_count >= 1`, `period_game_seconds >= 1`, `players_per_side >= 1`, all points >= 0.

**`DifficultyProfile`**: `id: StringName`, `display_name_key: String`, `level: int = 0`,
`tuning: Dictionary[StringName, float]` (PROVISIONAL keys until p1-ai-lead reports). The default
resource has `id = &"normal"`, `display_name_key = "DIFFICULTY_PLACEHOLDER"`, `level = 1`.
validate: empty id.

**`CameraPreset`**: `id: StringName`, `display_name_key: String`, `fov_degrees: float = 50.0`,
`distance: float = 25.0`, `height: float = 12.0`, `pitch_degrees: float = -25.0`,
`follow_smoothing: float = 0.15`, `look_ahead: float = 3.0` (all numeric fields PROVISIONAL). The
default resource has `id = &"broadcast"`, `display_name_key = "CAMERA_PRESET_PLACEHOLDER"`.
validate: empty id, `fov_degrees` outside (1, 179), negative distance.

**`MatchConfig`**: `seed: int = 0`, `rules: RulesConfig`, `flow: MatchFlowConfig`,
`pitch: PitchGeometry`, `home_team: Team`, `away_team: Team`, `stadium: Stadium`,
`difficulty: DifficultyProfile`, `period_real_seconds: int = 300` (PROVISIONAL, the match-length
option), `slot_count: int = 1`, `axes_per_slot: int = 2`;
`static create_default() -> MatchConfig` (loads the three default resources for rules, flow and
pitch; teams, stadium and difficulty stay null). validate: null rules, flow or pitch;
`period_real_seconds < 1`; `slot_count` outside 1..8; `axes_per_slot` outside 0..16; plus the
errors of `rules`, `flow` and `pitch` validation. Teams may be null in S1.

## 6. Acceptance criteria

Tests live in `tests/unit/match/`, `tests/unit/match/flow/`, `tests/unit/match/pitch/`,
`tests/unit/data/` and `tests/sim/`. "Default config" means `MatchConfig.create_default()`.
"Tick n" means the n-th call to `MatchSim.tick` (1-based); "after tick n" means after that call
returns. The purity scan (C-43) also reads comments, so sim files must not mention the banned
names even in comments.

**RNG**
- C-01 Two `SimRng` with the same seed produce identical sequences of 1000 `next_int()` values.
- C-02 Different seeds (1 and 2) produce different first-10 sequences.
- C-03 `get_state()` then 50 draws then `set_state(saved)` reproduces the same 50 draws.
- C-04 `range_int(3, 5)` only returns 3, 4 or 5 over 1000 draws; `next_float()` is in [0, 1).

**InputFrame**
- C-05 A new `InputFrame(2, 4)` has `buttons.size() == 2`, `axes.size() == 8`, all zero.
- C-06 `set_held(1, 5, true)` makes `is_held(1, 5)` true and `is_held(0, 5)` false.
- C-07 `set_axis(0, 1, 300)` stores 127; `set_axis(0, 1, -300)` stores -127.
- C-08 `copy_from` then `equals` is true; changing one bit makes `equals` false.

**Clock**
- C-09 `MatchClock.new(2, 60, 2400)`: after 30 `advance()` calls `game_time_seconds() == 1200`;
  after 60, `is_period_expired()` is true; `start_next_period()` gives period 2, elapsed 0,
  `game_time_seconds() == 2400`, `is_last_period()` true.

**Flow and sim**
- C-10 `default_match_flow.tres` loads as a `MatchFlowConfig` and `validate()` is empty; it has the
  six states of 2.8 with the flags of 2.8.
- C-11 `validate()` reports: an unknown `to`, a duplicate state id, a missing initial state, a
  transition with no trigger and no condition, and a flow with no terminal state (one test each).
- C-12 Direct standalone `MatchSim.tick(frame)` with default config and `period_real_seconds = 1`
  (P = 60): state after tick 1 is `kick_off`,
  after tick 2 `in_play`, after tick 61 still `in_play`, after tick 62 `half_time`, after tick 63
  `kick_off` with `clock.period == 2`, after tick 124 `full_time` and `is_finished()`; after
  tick 123 not finished.
- C-13 Direct standalone `MatchSim.tick(frame)` signals over that full run, published locally
  after each successful standalone finalization, in order: `state_changed` x6 with the from/to pairs of the
  trace; `period_started` with 1 then 2; `period_ended` with 1 then 2; `finished` exactly once.
- C-14 After finishing, further standalone `tick` calls leave `tick_count` and `state_hash()`
  unchanged and publish nothing.
- C-15 In `in_play`, `raise_trigger(MatchTriggers.WHISTLE_BLOWN)` then one tick moves to
  `stoppage`; then `raise_trigger(PLAY_RESUMED)` and a tick moves back to `in_play`.
- C-16 A trigger that matches no transition of the current state is consumed: raising
  `PLAY_RESUMED` in `in_play` then ticking twice leaves the state `in_play`.
- C-17 The clock does not advance in `pre_match`, `kick_off` or `half_time`, and advances in
  `in_play` and `stoppage` (check `elapsed_ticks` across states).
- C-18 A legacy-compatible `SimSystem` subclass that raises `WHISTLE_BLOWN` from `tick(sim)` when the state is
  `in_play` causes the transition to `stoppage` on that same tick.
- C-19 Systems tick in registration order (two systems appending ids to a shared array).
- C-20 `add_system` after the first tick is ignored (the system's `tick` is never called).
- C-21 Edge detection: frames with bit 3 held on ticks 2..4 give `just_pressed` true only after
  tick 2 and `just_released` true only after tick 5.
- C-22 An invalid config (null rules) gives `is_valid() == false`; standalone `tick` leaves
  `tick_count` at 0 and publishes nothing.
- C-23 `state_hash()` is a 64-character lowercase hex string and changes after a tick.

**Determinism (tests/sim/)**
- C-24 Same seed and the same scripted input log (at least 2 slots, 600 ticks, pseudo-random
  buttons and axes generated by a separate fixed-seed RNG, plus a `SimSystem` that consumes
  `sim.rng` and raises triggers from input) run twice give identical `state_hash()` after every
  tick.
- C-25 Changing only the seed gives a different `state_hash()` after tick 1.
- C-26 Recording with `MatchRunner`, serialising with
  `to_bytes`/`from_bytes`, then `MatchReplay.run` gives the same final `state_hash()` as the
  original run.
- C-27 A v3 mod-set mismatch returns `MatchReplayResult` with `sim == null`, non-OK error,
  `replay_failure == INCOMPATIBLE_HEADER`, `readiness_evaluation == BUILDER_COMPLETE`, and the complete
  current build readiness report; it is rejected before capture or tick. A matching replay returns
  a result with non-null sim, `OK`, `readiness_evaluation == BUILDER_COMPLETE`, and a ready report.

**Input log**
- C-28 `InputLog` round-trips through `to_bytes`/`from_bytes` and `save`/`load_file`
  (`user://`) with identical header fields and frames.
- C-29 `append_fixture_row` with a wrong-shaped frame returns a non-OK error and leaves
  `frame_count` unchanged. This raw fixture/import operation does not claim a simulation tick was
  committed and is never used by `MatchRunner`.
- C-30 `from_bytes` returns null for garbage bytes and for a header with
  `format_version = FORMAT_VERSION + 1`.

**Runner**
- C-31 `MatchRunner.start` with the default config, a base `InputSource`, and its current action
  layout identity returns `OK`;
  five committed `step_once()` results give `sim.tick_count == 5`,
  `input_log.frame_count() == 5`, and `ticked` emitted with 1..5.
- C-32 `start` with an invalid config returns `ERR_INVALID_PARAMETER`.
- C-33 With a `ReplayInputSource` of 3 frames whose v3 header matches current mod hash, current
  action-layout hash, freshly built setup fingerprint and tick rate, `start` returns `OK`; the 4th
  `step_once` returns source exhausted, emits `input_ended` and `is_running()` becomes false.
- C-34 During a runner-driven run, `EventBus.match_state_changed` is emitted with the same
  from/to pairs as the sim's `state_changed`.

**Pitch**
- C-35 `default_pitch.tres` has the defaults of section 4 and `validate()` is empty.
- C-36 With defaults: `try_line_x(1) == 50`, `dead_ball_line_x(-1) == -60`, `line_22_x(1) == 28`;
  `(0,0,0)` in field of play; `(50,0,0)` in goal for end 1, not in field of play; `(49.9,0,34.9)`
  in field of play; `(10,0,35)` in touch; `(60,0,0)` beyond dead-ball line and not in goal.
- C-37 `validate()` reports `field_length = 0` and `line_22_from_try = 60`.

**Data**
- C-38 Each data class instantiates with the defaults in section 5 (one test per class).
- C-39 `Team.validate()` reports a lineup id not in the squad and duplicate squad ids;
  `find_player` returns the profile or null.
- C-40 `PlayerProfile.display_name()` uses `known_as` when set; `get_attribute` falls back to the
  schema default; `validate(schema)` reports an unknown attribute key and an out-of-range value.
- C-41 The four default `.tres` files in `game/data/defaults/` load with the right class and
  `validate()` is empty.
- C-42 `MatchConfig.create_default().validate()` is empty; setting `slot_count = 0` reports an
  error.

**Purity and conventions**
- C-43 A test scans every `.gd` under `res://game/match/` (except `match_runner.gd`) for
  `EventBus`, `Input.`, `Time.`, `OS.get_ticks` and global random calls (regex
  `(?<![\w.])(randi|randf|randfn|randi_range|randf_range|randomize|seed)\s*\(`), and the same
  folders listed in 2.5 for everything but `EventBus`; no matches.
- C-44 Every data Resource field listed in section 5 is reported by `get_property_list()` with
  `PROPERTY_USAGE_STORAGE` and `PROPERTY_USAGE_EDITOR` (so the mod loader can patch it).

**Generic tick-owner lifecycle and publication**
- C-45 Registered owners, including the registered `S2RuntimePortOwner` adapter, capture exactly
  once in stable registry order before the first system tick. Systems retain existing registration
  order and observe captured pre-update owner values
  throughout the tick. Owner commits run in stable registry order after flow staging and receive
  the completed generic outcome. Invalid, finished, and stopped no-op ticks capture no owners.
- C-46 Injected failures during owner capture, system tick, checked flow staging, and owner commit restore
  the complete pre-tick state: tick count, current/previous input edges, RNG, clock/flow, triggers,
  every system, owner and owned stateful provider, S2 port pending commands/results/sequence, and
  staged events. Successful rollback returns
  `FAILED_RETRYABLE`; no failed phase returns a signal batch, appends a log entry, or publishes a
  sim, runner, or EventBus signal. Non-restorable stateful participants/providers and unsupported
  capabilities are rejected before tick 1. Flow failure is injected by enabling the documented
  test-owned `InjectableFailureCondition` fixture from the public test seam on an evaluated transition; its checked failure aborts
  and rolls back the transaction.
- C-47 After a recoverable runner tick failure, an explicit retry uses the exact sampled frame and
  detached command bundle without polling the source again. `_physics_process` does not retry it
  automatically. A successful retry matches a clean run and publishes each event once.
- C-48 The runner encodes/validates commands before tick execution. A command encoding failure
  does not tick or mutate sim state. After a `PREPARED` tick, it encodes/validates outputs and
  prepares/reserves the complete frame/commands/outputs row while rollback remains possible. An
  output/full-row preparation failure aborts/restores the tick, retains the exact sampled candidate,
  does not publish or expose a row, and explicit retry repeats preparation without polling or
  re-enqueueing. On success, sim finalization and row commit occur infallibly,
  allocation-free and with no callbacks between, before staged MatchSim signals/EventBus relays and
  `ticked` last. Invalid/stale tokens or candidate substitution cannot change the log.
- C-49 `fill_frame() == false` returns terminal `SOURCE_EXHAUSTED`, stops, emits `input_ended`,
  and the source is never polled again. Finished and stopped no-op tick statuses remain distinct
  from source exhaustion. Once the sim finishes the runner stops; later calls do not capture, log,
  or publish another tick.
- C-50 Replay compares the header's action-layout hash with the current expected hash from the
  configured action source/action set; `MatchRunner.start` receives that current hash explicitly
  and never derives it from `ReplayInputSource.layout_hash()`. It compares the header's setup
  fingerprint with the freshly derived current
  identity. The fingerprint covers effective config/resources, ordered participant identity/version
  and deterministic initial setup/state, plus provider identity/version/configuration/initial state
  owned by each participant. Any mismatch is rejected before capture or tick. Matching setup
  reproduces per-tick hashes. Records contain only external typed frame commands; no generic
  per-frame owner-capture command is added.
- C-51 The generic context/outcome provides copied immutable candidate/pre-tick data and generic
  clock/flow/transition information, including the exact deterministic advancing clock delta as a
  rational derived from actual advance. The test covers the advancing tick only; S1 exposes no
  pause API, and world-pause behavior remains unresolved. `TickResult` distinguishes
  prepared, committed, invalid/finished/stopped no-op, recoverable failure, and fatal rollback; its
  staged typed signal batch exists on prepared/committed results only. Extra-time behavior, world-pause behavior, and
  clock/replay migration policy remain unresolved; S1 adds no policy.
- C-52 Live `InputSource.fill_frame` receives a fresh mutable submission builder whose `seal()`
  detaches/copies existing concrete typed records into an immutable ordered bundle; a fresh empty
  builder seals to an immutable empty bundle. In live S2, the source bundle is validated/enqueued,
  `S2RuntimePort` assigns sequences, and canonical `queued_command_snapshots()` readback is decoded
  to a distinct final typed candidate bundle paired with the sampled frame. This exact pair is
  passed to `tick_checked`, retained by `PreparedTick`, encoded, and recorded. Non-S2 uses the
  sealed submission bundle as candidate; commandless input uses the empty bundle. The one codec
  converts existing command/result records to/from existing v3 rows; replay uses the same port
  route. Round-trip parity reproduces hashes without a second command schema.
- C-53 Setup explicitly declares each participant, including the S2 port owner adapter,
  `COMPLETE_TRANSACTIONAL`,
  `EXPLICITLY_STATELESS`, or `UNSUPPORTED`. Unsupported participants, a stateful participant with
  empty/default checkpoint, unowned stateful providers, or any repeated `ProviderClaim.provider`
  object reference in the effective ordered registry are rejected before tick 1, including
  stateless repeats and repeats by the same participant. The same per-registry uniqueness check
  applies to fresh replay factory claims. An explicitly stateless participant may be the same
  instance in the separate live and replay registries. A provider declared `EXPLICITLY_STATELESS`
  may use the same reference once in each separate registry, with one registered owner per registry
  emitting its unique claim. Neither case allows a repeated provider reference within either
  registry. Each stateful provider is
  checkpointed/restored and identified by exactly one owning registered system/owner; an explicit
  stateless declaration is
  required to use empty checkpoint/restore. Each typed provider claim has a referenced provider,
  stable id/version, transaction capability, configuration fingerprint and deterministic initial
  state fingerprint. Provider object identity is used for per-registry duplicate-ownership checks
  and exact binding/setup-claim matching; it is never serialized or fingerprinted as an object
  address. Stable claim fields feed setup fingerprinting.
- C-54 A restore failure returns `FATAL_ROLLBACK`, latches `MatchSim` stopped with a stable fatal
  reason, and makes both sim and runner non-retryable. Future checked ticks return `NO_OP_STOPPED`
  without capture or mutation; source exhaustion remains a separate terminal runner status.
- C-55 Replay v3 fatigue snapshot fields remain unchanged and are consumed as recorded at their
  existing input phase. An owner-derived fatigue state cannot apply those same recorded values a
  second time. Changing/removing those semantics requires a new format and a v3 adapter; v3
  fixtures preserve current payload values and timing.
- C-56 Existing successful signal order/payloads remain C-13; full-row-commit-before-relay is preserved.
  Preparation, tick, and fatal rollback failures publish no MatchSim signal, EventBus relay,
  `ticked`, or partial log entry. A prepared/committed tick result carries its staged batch, which may be empty
  when that tick emits no MatchSim signals. Failure and no-op results return no published signals
  and an empty batch.

- C-57 An invalidly constructed sim returns `NO_OP_INVALID` with `ERR_INVALID_PARAMETER`, null
  outcome and empty signal batch on `tick_checked`; no capture, tick, mutation or publication
  occurs. Its result is distinct from `NO_OP_STOPPED` and `NO_OP_FINISHED`.
- C-58 A flow transition whose test-owned `InjectableFailureCondition` fixture returns a checked error
  aborts flow staging. Successful rollback restores the full pre-tick state and returns
  `FAILED_RETRYABLE` with no outcome/batch, log append or publication; retrying after disabling
  the condition commits the exact candidate once.
- C-59 Fake participants can construct successful and failing `SystemTickResult`,
  `OwnerCaptureResult` (success includes a non-null immutable `OwnerCapture.payload`),
  `OwnerCommitResult`, and `CheckpointResult`; successful `CheckpointResult` carries a non-empty
  checkpoint value for stateful participants. Fake owners can construct `SimDependencyCheckpoint`
  values and include them in their own checkpoint, demonstrating owner-managed provider restore.
- C-60 An input source appends existing concrete typed command records to the submission builder; sealing
  preserves order and concrete type while detaching from later builder/source mutation. In live S2,
  the runner validates/enqueues submissions, decodes authoritative port snapshots into a distinct
  final typed candidate, and records and passes that exact frame/readback pair through abortable tick
  preparation and coordinated row commit. Non-S2 uses the sealed submission bundle; commandless
  input seals to an immutable empty bundle.
- C-61 Format v1 and v2 input/header records parse and round-trip with the same format version and
  all version-specific fields preserved; serialization does not inject newer-version fields into
  legacy records. A v1 header omits the setup fingerprint on parse input and `to_dict()` output,
  while its in-memory fingerprint is empty. Parsing rejects a missing, wrongly typed, or empty
  setup fingerprint for v3 at `ReplayHeader.from_dict` and `InputLog.from_bytes`; v2 requires a
  present String and preserves even `""` through parse/serialization. Playback through
  `ReplayHeader.is_compatible_with`, `MatchRunner.start`, and direct `MatchReplay.run` accepts
  exactly v3. Direct replay rejects a null log/header and every typed non-v3 version before replay
  composition setup; runner startup checks after its composition build and before source polling,
  capture, or tick. V3 requires a correctly typed non-empty setup fingerprint. Current v3 fatigue
  field names, values and timing retain C-55 semantics; no fieldless-v3 compatibility adapter is
  accepted or implied.
- C-62 `MatchRunner.start` with a matching ReplayInputSource header, current mod hash, explicit
  current action-layout identity, current setup fingerprint and tick rate succeeds. Independently
  mismatch each identity and verify start rejects before source polling, owner capture, sim tick,
  log append or signal publication. For a recorded/source layout A, explicit current layout B
  rejects; explicit current layout A succeeds. A missing or empty current layout identity also
  rejects before any source poll, capture, tick, append, or publication. Equality A/A is valid even
  when the expected A was obtained from the current action source/action set; the replay source's
  recorded `layout_hash()` is not itself evidence of the current identity.
- C-63 Runner results distinguish `SOURCE_EXHAUSTED`, `STOPPED`, `FINISHED`, and
  `FATAL_ROLLBACK`. Each path has its stated terminal behavior; `input_ended` is emitted only for
  source exhaustion, and fatal rollback is non-retryable.
- C-64 Provider setup claims expose stable provider id/version, transaction capability,
  configuration fingerprint and deterministic initial-state fingerprint. Reject every repeated
  `ProviderClaim.provider` object reference in one effective ordered registry, including stateless
  claims and repeats by one owner; this also applies to fresh replay factory claims. Distinct objects
  with equal stable claim fields are not considered duplicate owners solely by identity values.
  `provider` is used for per-registry duplicate ownership and exact S2 binding/setup-claim identity
  checks, never serialized or fingerprinted as an object address. Only stable claim values alter
  setup fingerprinting. An explicitly stateless participant may be the same instance in the
  separate live and replay registries. A provider declared `EXPLICITLY_STATELESS` may use the same
  reference once in each separate registry, with one registered owner per registry emitting its
  unique claim. Neither case permits repeated references within either registry.
- C-65 `SetupResult` can be constructed for success and failure. Its successful participant claim
  has non-empty stable participant id/version, configuration fingerprint and deterministic initial
  state fingerprint; each provider claim has non-empty stable id/version, configuration fingerprint
  and deterministic initial-state fingerprint plus an explicit capability. Missing/empty claim
  fields and duplicate participant identities reject setup before tick 1. The legacy
  `system_id() == &"system"` default is never used as the canonical participant identity. Setup
  fingerprint changes when any stable participant or provider claim value changes.
- C-66 Direct `MatchReplay.run` always returns a `MatchReplayResult` object. A null log/header
  returns `sim == null`, `replay_failure == INVALID_RECORD`, non-OK error,
  `readiness_evaluation == NOT_EVALUATED`, and an empty non-null report before setup/capture/tick/
  reset/publication. Any typed header with `format_version != 3` (including v1, v2, and future
  versions) returns `sim == null`, `replay_failure == INCOMPATIBLE_HEADER`, non-OK error,
  `readiness_evaluation == NOT_EVALUATED`, and an empty report before replay composition setup.
  Assert neither path invokes extension/provider/system factories or setup. A null request returns
  non-OK error with `readiness_evaluation == PREFLIGHT_ONLY`; its report may contain the generic
  missing-config diagnostic but is not complete replay readiness. Make a dependency non-shareable
  and assert the preflight returns with `replay_failure == NONE`, non-OK error,
  `readiness_evaluation == PREFLIGHT_ONLY`, its known blocker(s), and no replay composition build.
  `PREFLIGHT_ONLY` reports are incomplete even when `is_ready()` is true; only
  `BUILDER_COMPLETE` reports describe full replay readiness. For a v3 request that completes the
  replay composition build, an empty setup fingerprint, empty expected action-layout identity, or
  independently mismatched mod-set hash, current action-layout identity, setup fingerprint, or tick
  rate returns `sim == null`, `replay_failure == INCOMPATIBLE_HEADER`, non-OK error,
  `readiness_evaluation == BUILDER_COMPLETE`, and the complete builder report before capture, tick,
  reset, or publication. Builder failures after that build also retain its complete report. Parser
  rejection of missing or wrongly typed serialized fingerprint fields remains at
  `ReplayHeader.from_dict` and `InputLog.from_bytes` as specified by C-61; a typed empty v3 header is
  a post-build direct replay case. A matching v3 replay returns non-null sim, `OK`,
  `replay_failure == NONE`, `readiness_evaluation == BUILDER_COMPLETE`, a ready report, and preserves
  C-55 fatigue semantics.
- C-67 A v3 log round-trips per-frame `runtime.commands` and `runtime.outputs` with exact row,
  record, and sequence order. During live recording, observe the committed complete row from a
  signal relay and from `ticked`; both see the row before publication. Output encoding/validation
  and copying/building the full row happen while the tick remains abortable. Inject codec output
  encode/validation failure and a checked row-preparation validation failure before finalization: each
  aborts/restores the tick, cancels its row token, exposes no row/output/signal, and explicit retry
  uses the exact candidate without source repoll or duplicate enqueue/sequence assignment. Reject a
  token paired with another tick, an independently created output bundle, or a reused/cancelled
  token. A matching prepared tick/output bundle/row token commits successfully before relay. A
  malformed record, missing command/output linkage, duplicate/reordered sequence, or generated-output
  mismatch rejects replay before that tick is finalized or published. Verify port pending/results/
  sequence are present in runtime snapshots and hashes; owner/system/output-codec/log-row failure
  restores exact pre-tick port state; and successful live/replay finalization exposes no intermediate
  queue/result/sequence mutation before the full row commits; committed readback and hashes match
  the expected full row and generated results.
- C-68 Inject a retryable checked-tick failure: expose no row/output/signal and allow explicit
  retry with the exact frame/commands without source repoll. Inject a fatal rollback failure:
  expose no row/output/signal, latch sim and runner terminal, and prove every later step refuses
  retry. Fatal rollback is never treated as an explicit-retry case.
- C-69 Live `MatchRunner.start(request, source)` and direct `MatchReplay.run(request, log)` use the
  same `MatchCompositionRequest`, config, ordered systems, mod/action identities, and extension
  points. Replay source start explicitly uses `build_replay(request)` and live source start uses
  `build(request)`. The effective ordered registry contains the S2 port-state owner adapter once;
  replay preserves registry order and uses the same generic no-argument factory/result for every
  mutable registered participant. It separately uses the S2 typed port factory after validating
  fresh owner claims. Replay builds independent initial participant and S2 port/provider instances
  through `build_replay`; it leaves the entire original request graph untouched and never resets or
  ticks its original systems or port. Replay succeeds only when its header matches the current request; its action
  identity is never derived from the header. Missing contact geometry/solver or other required
  dependencies produce typed readiness blockers before polling, capture, tick, append, or
  publication. Runner-driven replay validates each recorded output before tick finalization,
  publishes nothing on invalid/mismatched rows, reports terminal `REPLAY_FAILED` with a typed
  reason, and never appends to or changes the source log.
- C-70 Before direct or runner-driven replay frame 0, fresh replay port `reset_runtime()` succeeds
  once and clears transient queues/results/consumed state, sequence position and failure metadata
  while retaining fresh contact providers, setup, initialization, wind/environment and injected
  dependencies. It does not rewind/replace providers or create the baseline. If reset returns false, replay returns the
  typed `PORT_RESET_FAILED` result before tick or publication. Both paths complete fresh build and
  header compatibility checks before this one reset; a mismatch does not reset the fresh port.
- C-71 Live submitted typed source commands are validated and enqueued exactly once through the
  request port; the runner decodes `queued_command_snapshots()` through the single codec into the
  distinct final typed candidate, and the v3 row records those port-assigned sequence values and
  canonical order. Preparation and retry failures preserve
  those exact commands/sequences without a second enqueue or new sequence assignment. Replay applies
  the full-queue carried/new rule in §3.3/§3.4, preserves recorded sequence values, validates full
  canonical readback, and compares generated outputs against commands in the full row. No second S1
  command schema is introduced.
- C-72 With tick N leaving command sequence 0 unconsumed, row N+1 repeats that exact command
  unchanged and introduces sequence 1. Replay preserves command 0 once (does not enqueue it twice),
  injects only sequence 1, and accepts its later output when command 0 is consumed. Reject a carried
  command that is missing, changed in any payload field, duplicated, or reordered against canonical
  port order. Verify port pending readback equals each complete row and the post-commit survivors
  seed the following comparison.
- C-73 Exercise append authorization: mutate the caller's original frame after tick preparation
  and attempt to pair another candidate's frame with the prepared tick; the committed row must use
  the immutable `PreparedTick` frame and `prepare_append` exposes no frame argument. Reject a
  different typed command candidate, an encoded command bundle from another source bundle or tick,
  an output bundle from another tick, a substituted row, and a token paired across ticks. Cancelled, consumed, stale,
  or reused tokens cannot publish. Ordinary codec/log preparation failures abort and remain
  explicitly retryable with the same candidate. A valid matching frame/commands/outputs candidate
  finalizes and commits exactly once before relay, with no callback between the two infallible
  steps. The contract concerns normal API execution and does not claim atomic recovery after
  arbitrary process termination.
- C-74 A preparation failure followed by exact explicit retry polls/enqueues once and commits one
  row; live retry preserves its already sampled/enqueued candidate and assigned sequences. Replay
  reset clears transient runtime state once while preserving injected dependencies; a
  fatal rollback latches sim and runner terminal and every later step refuses retry.
- C-75 `InputLog.read_replay_row(index)` issues a detached typed frame/command/output snapshot and
  opaque capability bound to that log object, index, stable row generation, and complete row;
  unchanged rereads share internal identity. The explicit caller-created-row case uses only the
  public `ReplaySourceRow.new()` no-argument constructor, which yields an inert row with null frame,
  empty command/output arrays, and no log-issued identity. `MatchSim.begin_replay_row` rejects it as
  `(false, null, ERR_INVALID_PARAMETER)` before checkpoint capture or port transaction, with no
  state change. Also reject out-of-range indexes, reassembled rows, changed/mutated source rows,
  and substitutions after source-log mutation. One build-owned `ReplayValidationAuthority` is shared
  by that build's sim and codec. Only the codec's private mint path registers a nonce and exact token
  object after all validation succeeds; failed checks return no usable token. Verify an inert
  public no-argument `ReplayValidationToken.new()` is rejected without finalization; do not test
  copying/reassembling token fields because no token fields or copy constructor are public. Bind the
  exact internally minted token against wrong sim/tick/log/index/row/readback/expected-output/
  generated-output identities and require rejection without consuming its valid binding; then the
  exact correct pairing consumes once. Abort invalidates a registered token. Force validation
  failure after new-command injection and assert abort restores the exact pre-row pending queue and
  next sequence. A valid matching token
  finalizes the active tick
  once. Force generated-output mismatch and assert rollback-capable abort with no publication,
  accepted result, or source-log mutation. Direct and runner replay publish only after
  receipt-backed finalization.
- C-76 Force a restore failure during a v3 direct replay and assert exact `MatchReplayResult`
  shape: `sim == null`, non-OK error, `replay_failure == FATAL_ROLLBACK` (distinct from
  `TICK_FAILED`), non-empty `fatal_reason`, `readiness_evaluation == BUILDER_COMPLETE`, complete preserved
  build readiness, unchanged source log, and no publication.
- C-77 Use a stateful fake owner/system and stateful fake injected provider. Advance live objects,
  then replay the same request/log; assert fresh independent objects begin in deterministic initial
  state, initial/per-tick hashes and outputs match, and original post-live objects remain unchanged.
  Force a failed replay tick and verify rollback restores each fresh object to exact immediately
  pre-tick state. Accept explicit stateless self-reuse; reject missing, failed, shared, or
  non-independent stateful factories. Assert `ReplayInstanceResult` success and failure shapes,
  detached immutable claim records with exact provider references and empty claims for a participant
  with no providers. In a separate stateless-provider fixture, assert that the owner explicitly
  declares `EXPLICITLY_STATELESS`, that repeated calls preserve deterministic outputs and leave no
  mutable state that can affect future ticks, and that the exact provider object can be reused once
  in the separate live and replay registries. Assert the owner emits its unique claim even when
  multiple consumers use that provider as a read-only dependency. This tests the declaration's
  behavior; it does not create a separate proof schema. Reject repeated claims/references within
  either effective registry, including repeated stateless claims and repeats by the same owner;
  provider
  state is owned by exactly one registered system/owner. Verify factory
  claims describe fresh initial providers without setting up or mutating the live source. Assert
  each mutable provider is constructed exactly once per replay build and separate replay runs share
  no mutable provider instances. Verify generic dispatch calls only
  `create_replay_instance() -> ReplayInstanceResult` on each mutable registry entry, while the
  builder calls `S2RuntimePort.create_replay_instance(bindings) -> S2ReplayInstanceResult` exactly
  once after collecting those factory claims. Confirm the registered adapter and fresh port
  reference each other by exact object identity, and every binding is the exact fresh provider
  claimed by its unique owner. Call `setup(sim)` once after fresh port/registry construction and
  reject owner setup claims that differ from factory claims in count, order, provider identity,
  stable strings, or transaction capability before fingerprint acceptance/capture/tick. Verify
  stale or unproved bindings reject before setup acceptance/capture/tick, port reset does not rewind
  providers, and each mutable injected provider has one owner.

### Implementation, test-author, and reviewer handoff

The implementation slice owns generic context/outcome, same-registry owner participation,
complete checkpoint/restore, checked tick and runner outcomes, staged notification publication,
and two-phase prepared append/replay receipt semantics. A separate test author derives lifecycle
tests from every criterion C-45–C-77, including C-67–C-77, with no omissions, plus unchanged
C-13/C-31–C-34 behavior without relying on implementation details. Two distinct independent
reviewers, neither the implementation author, review the architecture and code against all
C-45–C-77 criteria, with focused review of owner/port transaction coverage, exact row capabilities,
authority nonce/object identity, abort invalidation, cloning identity and counts, retry/sequence
restoration, compatibility-before-reset ordering, and direct and runner-driven publication.
Fallback review effort follows PLAN §2b, including its mandatory second independent luna-high pass
for Opus-level architectural work. This docs slice ran only `git diff --check`; no tests or Godot
commands were run.
