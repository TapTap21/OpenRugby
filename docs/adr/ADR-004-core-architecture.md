# ADR-004: Core architecture: pure match sim, data-driven flow, mod runtime, input frames

- Status: Accepted
- Date: 2026-10-14
- Slices: S1 (core, mod loader core), S9 (input)
- Specs: [S1-core](../specs/S1-core.md), [S1-modloader](../specs/S1-modloader.md),
  [S9-input](../specs/S9-input.md)

## Context

ADR-001 fixes a 60 Hz deterministic simulation separated from presentation. ADR-003 requires a
built-in mod loader where base data is "mod zero". Phase 1 reverse engineering runs in parallel,
so S1 and S9 must be built before Rugby 08's rules, attributes, controls and match flow are known.
Every value that RE will later supply has to land in a `Resource`, not in code. These choices are
expensive to reverse once replays, saves and mods exist, so they are recorded here.

## Decision

### 1. The match simulation is a pure object

- `MatchSim` is a `RefCounted` with no scene tree, rendering, physics server or autoload access.
  It advances through a checked tick transaction. Its required standalone `tick(frame) ->
  TickResult` wrapper supplies an empty typed command bundle, finalizes a successful prepared tick
  through `finalize_standalone_tick(prepared_tick)` without an append token, then publishes the
  staged MatchSim signals locally. Failures publish nothing. It never appends to a log or relays to
  EventBus. Runner-owned sims reject standalone finalization, and runner/replay paths never call
  this wrapper; live recording requires the exact append token and replay requires an opaque,
  single-use `ReplayValidationToken` before
  `finalize_replay_tick(prepared_tick, replay_validation_token)`. The receipt binds the active
  sim/tick, source log and full immutable row identities, frame index, canonical command readback,
  expected and generated output identities, and successful exact output comparison. Only the
  replay coordinator/codec mints it after source-row, sequence/linkage and generated-output
  validation. It cannot be caller-constructed or copied into a usable capability. Finalization
  rejects wrong, stale, mismatched or reused receipts; failed validation aborts while rollback is
  possible. Neither direct nor runner replay publishes MatchSim signals, EventBus relays, or
  `ticked` before receipt-backed finalization succeeds. Standalone finalization consumes only that sim's exact active prepared
  tick, once and without a token; if wrapper finalization rejects, it aborts the still-active tick
  and publishes nothing.
  Nothing else mutates it between ticks except `raise_trigger()` (queued until the next tick) and
  setup calls before the first tick.
- `MatchRunner` (a `Node`) owns the sim. `InputSource.fill_frame` fills a submission builder paired
  with the sampled frame. In live S2, the runner validates/enqueues submitted typed records, the
  `S2RuntimePort` assigns sequences, and its canonical `queued_command_snapshots()` readback is
  decoded into a distinct final typed candidate bundle. That authoritative readback bundle, paired
  with the sampled frame, is the exact candidate passed to `tick_checked`, retained by
  `PreparedTick`, encoded by the codec, and recorded. Non-S2 composition uses the sealed submission
  bundle as its candidate; commandless input uses the immutable empty bundle produced by sealing a
  fresh `DetachedCommandBundleBuilder`. Port-assigned sequence values are retained across retries.
  Before tick execution, the one composition `S2ReplayCodec` encodes the exact final typed
  candidate into an opaque
  `EncodedCommandBundle` carrying source-bundle identity and detached v3 command records. Its
  `PreparedTick` retains the exact normalized immutable frame, typed command copy and source
  identity. It executes a checked tick into an abortable prepared state, completes output codec and
  full-row preparation, then finalizes the sim and commits the
  already-built log row through infallible, allocation-free operations with no callbacks between.
  Only then does it publish staged sim signals, relay to `EventBus`, and emit `ticked` last. The
  complete row is observable before any signal relay. Runner-driven replay reads the existing
  source log and validates each generated output before finalization; it never records a second log.
- The sim owns its randomness: one `SimRng` (wrapping `RandomNumberGenerator`, PCG32) seeded from
  `MatchConfig.seed`. Global `randi`/`randf`/`randomize`, `Time`, `OS.get_ticks_*` and wall-clock
  values are banned in sim folders; a unit test scans for them.
- Determinism contract: same `MatchConfig` + same mod set + same input log gives the same
  `state_hash()` after every tick. `state_hash()` is SHA-256 over `var_to_bytes(snapshot())`,
  where `snapshot()` is a deterministically ordered `Dictionary` that includes the RNG state.
- Tick rate is the constant `MatchSim.TICKS_PER_SECOND = 60` (ADR-001). The runner checks that
  `Engine.physics_ticks_per_second` matches and refuses to run otherwise. Time inside the sim is
  counted in integer ticks; seconds are derived for display only.
- Presentation reads sim state. Node3D presenters copy transforms from sim state in
  `_physics_process` after the tick, and Godot physics interpolation (already enabled) smooths them
  between ticks. Non-transform presentation (HUD) runs in `_process`. Presentation never writes to
  the sim.
- Subsystems that later slices add implement `SimSystem` and are registered on the sim in a fixed
  order. The order is part of the determinism contract. An opt-in `SimTickOwner extends
  SimSystem` participates in that same ordered registry; it does not create a second registry.

### 2. Event bus usage

`EventBus` (autoload) carries typed, past-tense signals for events that cross feature folders,
e.g. sim to HUD, mod loader to UI. Intra-feature communication uses local signals ("call down,
signal up"). The sim never touches `EventBus`. It stages its successful signal batch, and the
runner relays only after committing the prepared input-log row including that tick's outputs, so
listeners (HUD, audio, mod hooks) cannot run in the middle of a tick. Replay publishes after its
source-row outputs validate and its sim tick finalizes. Listeners must not mutate sim state; mods that need to
change sim behaviour use declared extension points, which the sim calls deterministically. Each
signal documents its owning slice; adding one is a spec change.

Direct standalone `MatchSim` signals publish locally only after that standalone tick finalizes.
Runner-driven `MatchSim` signals and `EventBus` relays publish only after the complete recorded row
commits. `SimSystem.tick(sim) -> void` remains compatible for existing subclasses; the core calls
only `tick_checked(sim, context) -> SystemTickResult`, whose default calls `tick(sim)` and reports
success. A system that can fail overrides the checked entry point. Systems publish no external
signals during ticking.

Scripts launched with Godot's `-s` entry point may not have compile-time access to autoload names.
Scene-tree components resolve the bus at runtime from `/root/EventBus`; headless helpers use a
passed bus when the scene tree does not install autoloads. A missing bus skips cross-feature
emission safely instead of trying to emit on an unavailable singleton.

### 3. Match flow is a data-driven state machine

Match states (`pre_match`, `kick_off`, `in_play`, `stoppage`, `half_time`, `full_time`) are
`MatchStateDef` resources inside a `MatchFlowConfig` resource. Each state carries flags
(`clock_runs`, `ends_period`, `terminal`) and an ordered list of `MatchTransitionDef`s. A transition
fires on a named trigger, on a `MatchCondition` resource, or both, and may start or advance a period.
S1 ships placeholder conditions so the skeleton runs end to end; the rules slice (S3) replaces
triggers and conditions with real law logic by editing data and adding `MatchCondition` scripts,
not by changing the state machine. At most one transition fires per tick, first match in list
order, which keeps the flow deterministic.

### 4. Data model

All tunable or moddable data are custom `Resource` classes with `class_name` and typed `@export`
fields: `PitchGeometry`, `PlayerProfile`, `PlayerAttributeSchema`, `Team`, `Kit`, `Stadium`,
`RulesConfig`, `DifficultyProfile`, `CameraPreset`, `MatchConfig`, `MatchFlowConfig`. Where Phase 1
has not yet fixed the schema (player attributes, difficulty tuning), the field is a typed
`Dictionary[StringName, int|float]` whose keys are listed by a schema resource, so RE fills data,
not code. Provisional fields are marked `## PROVISIONAL` in their doc comments. Real-world World
Rugby values are defaults and are marked "to be confirmed by RE". JSON is only an interchange
format; the mod loader's `ResourcePatcher` fills Resources from dictionaries.

### 5. Mod runtime

- `ModLoader` (a `RefCounted`, owned by `Main`, not an autoload) discovers `mod.json` manifests in
  `res://mods/` and `user://mods/`, mounts `user://mods/*.pck` with
  `ProjectSettings.load_resource_pack(path, false)` (never replacing base files), resolves
  dependencies and version constraints, and computes a deterministic load order: base ("mod zero")
  first, then a topological order with ties broken by `(load_priority, id)`.
- Layer 1, data: JSON patch files set fields on Resources by resource path and field path.
  Patches mutate the cached Resource in place and the runtime keeps strong references, so every
  `load()` of that path, including `ext_resource` references in other resources, sees the patched
  instance. Scalars replace, dictionaries merge by key, arrays replace unless `$append` is used,
  nested resources merge field by field. First-touch values are recorded so `revert()` restores
  the base game exactly.
- Layer 2, assets: a mod's `overrides/` tree shadows `res://` paths. Godot cannot globally
  redirect `load()`, so moddable asset loads go through `ModRuntime.resolve_asset_path()` /
  `load_resource()`. `.tres` files that reference other files by `ext_resource` are not shadowed;
  mods retarget those with a data patch. This limitation is documented, not hidden.
- Layer 3, scripts: a mod's entry script extends `ModEntry` and receives a `ModApi`. It may only
  register callables on declared `ExtensionPoints` and connect to `EventBus` signals. Script mods
  run arbitrary GDScript; there is no sandbox and the docs say so.
- An `OverrideLedger` records, per resource field and per asset path, every mod that touched it in
  order; `last_writer()` answers "which mod last touched this field" and `conflicts()` lists every
  field or asset touched by more than one non-base mod.
- `mod_set_hash` is SHA-256 over `id@version` lines of the applied load order, base included.
  Replay headers store it and a replay refuses to run against a different hash.
- Mods are applied once at boot; changing the enabled set requires a restart in the shipped game
  (mounted packs and run scripts cannot be unloaded). `revert()` exists for tests and for the
  "Modern on then off changes nothing" check.

### 6. Input

- Actions are data: `InputActionDef` resources in an `InputActionSet` resource, named by intent
  (`pass_left`, `kick`, `tackle`, ...). `InputBindings` writes them into `InputMap`, applies
  gamepad-first defaults plus keyboard defaults (physical keycodes), remaps at runtime and
  persists to `user://input_bindings.cfg` via `ConfigFile` with a schema version.
- The sim never reads `Input`. Once per tick an `InputSampler` (an `InputSource`) converts device
  state into an `InputFrame`: a held-button bitmask and quantised axes (integers in [-127, 127]) per
  controller slot. Button edges are derived by the sim from consecutive frames. Quantisation makes
  replays exact and compact. Bit order comes from the action set; its `layout_hash()` is part of
  the replay header.
- Dependencies point one way: `game/platform/input` depends on `game/match` (`InputFrame`,
  `InputSource`), never the reverse.

### 7. Tick-owner lifecycle, rollback, and publication

Stateful tick participants need one generic transaction boundary so captures and updates remain
deterministic and recoverable. `SimTickOwner` is an opt-in `SimSystem` in the existing ordered
registry; ordinary systems do not receive lifecycle no-op hooks, and no second owner registry is
introduced. Owners capture immutable copied pre-tick context in registry order before systems tick.
Systems run in their existing order. Clock and flow changes are staged, then owners commit against
the completed generic outcome. This keeps owner capture pre-update and makes committed owner state
available to the next tick without embedding later-slice rules in S1.

Every participant explicitly declares itself complete-transactional, explicitly stateless, or
unsupported during setup. Unsupported participants are rejected. A default empty checkpoint is
accepted only for an explicitly stateless participant. Every injected stateful provider has exactly
one owning registered system or owner, which checkpoints/restores it and includes its deterministic
initial identity in setup fingerprinting. Each effective ordered registry rejects every repeated
`ProviderClaim.provider` object reference, including stateless claims and repeats by one owner;
this applies separately to live setup claims and fresh replay factory claims. An explicitly
`EXPLICITLY_STATELESS` participant may be the same instance in the separate live and replay
registries. A provider declared `EXPLICITLY_STATELESS` may be referenced once in each separate
live and replay registry; if multiple consumers use it as a read-only dependency, one registered
owner per registry emits its unique claim. Neither exception permits a repeated claim/reference
within either registry, including repeats by the same owner. Provider state remains owned by exactly
one registered system/owner; there is no second provider registry.

The S2 runtime port queue, results, consumed-sequence state, next sequence, and failure metadata
are mutable tick state. A required `S2RuntimePortOwner extends SimTickOwner` adapter, never the
port itself, is registered exactly once in the existing ordered registry and is shared with the
port by composed systems and the replay coordinator. The adapter alone checkpoints, restores, and
snapshots/hashes those runtime values; claimed providers remain owned by their existing owners.
The port's internal tick commit
may stage pruning but retains its rollback snapshot until sim finalization. A failed tick is
returned through a checked owner failure. The sim checkpoint remains active through output and
log-row preparation, and `abort_prepared_tick` restores the port with all other participants.
Successful finalization only consumes the exact append token or replay receipt and discards the
retained checkpoint; no fallible port commit, callback, allocation, or extra mutation occurs then.
Replay starts its row transaction before recorded command injection and keeps it through sequence
validation, canonical readback, tick, output validation, and receipt finalization. Failed rows
restore the exact pre-row queue and sequence; successful rows feed committed survivors to the next
row through the shared replay coordinator. `MatchSim.begin_replay_row(source_row)` captures the
whole sim/owner checkpoint and returns the active `PreparedTick` before sequence checks or
injection while opening the port owner's internal row transaction; `tick_replay_row(prepared_tick,
frame, commands)` runs tick phases using that same transaction and checkpoint. Any pre-tick row
failure uses `abort_prepared_tick` on that handle.

The checked tick API returns a typed `TickResult`. Statuses are `PREPARED`, `COMMITTED`,
`NO_OP_INVALID`, `NO_OP_FINISHED`, `NO_OP_STOPPED`, `FAILED_RETRYABLE`, and `FATAL_ROLLBACK`.
`PREPARED` means every fallible simulation phase succeeded while the full rollback checkpoint is
still retained. It exposes detached validated typed outputs and staged signals, but the tick is
abortable and not externally finalized. For live recording, `COMMITTED` is assigned only after
both the sim and complete frame/command/output row cross the coordinated boundary. Replay uses its
already complete read-only source row and accepts the tick after output validation and sim
finalization. Successful abort restores exact
pre-tick state; failed rollback latches terminal `FATAL_ROLLBACK`, and neither sim nor runner can
retry. Fatal rollback is distinct from the retryable rollback path. `MatchSim` does not emit during
tick phases. Standalone `MatchSim.tick` publishes locally after standalone finalization;
runner/EventBus relays publish after the complete recorded row commits.

The runner uses this two-phase contract for live input. Its one composition-provided
`S2ReplayCodec` encodes and validates the exact final typed command candidate before tick
execution. The opaque encoded bundle carries source-bundle identity and cannot be substituted from
another candidate. It can create a
`PreparedOutputBundle` only from the exact `PreparedTick`'s validated detached `TickResult.outputs`;
callers cannot encode an arbitrary output array. `InputLog.prepare_append(prepared_tick,
encoded_command_bundle, output_bundle)` obtains the normalized frame and retained typed command
candidate from `PreparedTick`, verifies source-bundle identity and output tick identity, and builds
the exact v3 row while rollback remains possible. It accepts no caller-supplied frame or typed
command values. The log alone mints an opaque, single-use `PreparedAppendToken`, bound to the
prepared-tick, source/encoded-command, candidate-frame, output-bundle, log, exact row, and reserved
index/generation identities. The token carries an internal registered nonce and exact object identity; caller-created token
objects or copied fields do not reproduce it. The log verifies each binding and active reservation. `MatchSim.finalize_prepared_tick(prepared_tick, append_token)`
requires the exact active tick and matching row token, then marks that token finalized. The
immediate `InputLog.commit_append(append_token)` requires the same token and that finalization mark.
Cross-tick, cross-log, independently-created-output, substituted-row, stale, cancelled, or reused
tokens are rejected. A command codec failure before execution leaves sim state untouched; output
codec or log preparation failure aborts the prepared tick, cancels/releases its reservation, and
retains the exact frame/typed command candidate for explicit retry without source polling or
duplicate port enqueue/sequence assignment. All fallible work and allocations finish before
finalization. Finalize and commit are infallible, allocation-free and callback-free, with no callback
between them. This API pairing is the normal-execution contract; it does not promise atomic recovery
from arbitrary process termination. The row is observable before staged sim signals, EventBus
relays, or `ticked`.

`InputLog.append_fixture_row(frame, command_records, output_records)` is reserved for raw fixture
construction and imports. It rejects a wrong-shaped frame without adding a row, is never called by
`MatchRunner`, and does not claim that a simulation tick was committed.

Replay accepts the same `MatchCompositionRequest` as live startup. Every mutable registered
participant, including `S2RuntimePortOwner`, has exactly one generic factory signature:
`create_replay_instance() -> ReplayInstanceResult`, whose value fields are
`ok: bool`, `instance: SimSystem | null`, `error: Error`, and
`owned_provider_claims: Array[ProviderClaim]`. Success is `(true, new_instance, OK, claims)`;
failure is `(false, null, non-OK, empty claims)`. Claims are detached immutable records, while
their `provider` fields intentionally retain exact provider object references for per-registry
duplicate-ownership checks and exact identity checks when constructing/validating
`S2ProviderBindings` and matching setup claims to factory claims. The provider reference is never
serialized or included in the setup fingerprint as an object address; only stable claim values
feed fingerprinting.
The factory constructs the fresh initial participant and every stateful provider it uniquely owns,
then returns claims for those exact fresh provider objects; a participant with no providers returns
empty claims. `EXPLICITLY_STATELESS` is the provider owner's explicit declarative assertion that
the provider has no mutable state and no calls can change behavior that affects current or future
deterministic ticks. This is the normative claim checked by setup/factory comparison; S1 has no
second proof object or runtime reflection. A false declaration violates the contract and is caught
through tests and review, not dynamic introspection. The exact provider object may be referenced
once in each separate live and replay registry, with one registered owner per registry emitting its
unique claim even when multiple consumers use it as a read-only dependency. This never permits a
repeated claim/reference within either registry. These claims describe the fresh
initial instance and are
not copied from the live advanced source. The factory must not mutate or set up the original
participant or source sim. There is no overload or generic dispatch by type/arity. The port is not
registered and does not implement that interface; the S2 owner adapter is registered once and uses
the generic signature. The builder constructs the effective ordered registry once, clones each
mutable participant exactly once through its generic factory, replaces entries in place, and
collects each result's claims; it appends/clones the adapter once as the final registry entry in
both live and replay builds.

Replay construction order is strict. First validate factory-result claim shape and capabilities,
reject every repeated provider object reference in the effective ordered registry, including
stateless repeats and repeats by one owner, and require unique ownership. Then build
`S2ProviderBindings` only from those fresh result claims. The S2 composition builder alone invokes
the separately typed factory
`S2RuntimePort.create_replay_instance(bindings: S2ProviderBindings) -> S2ReplayInstanceResult`,
whose result is `{ok: bool, port: S2RuntimePort | null, error: Error}`; success is
`(true, fresh_port, OK)` and failure is `(false, null, non-OK)`. The port copies stable
configuration and transient runtime setup but never clones providers. Attach that exact returned
port once to the fresh unbound adapter and verify adapter-to-port and binding-to-claim provider
identity. Construct the fresh sim with the ordered fresh registry and port, then call normal
`setup(sim)` exactly once. Each owner's `SetupResult.owned_provider_claims` must match its factory
result claims in count, order, exact provider object identity, stable strings, and transaction
capability. Any mismatch rejects before fingerprint acceptance, capture, or tick. Setup confirms
factory-result claims; it is not their pre-port source. Only after setup and claim agreement does
the builder compute/accept the fresh setup fingerprint and start capture. No provider is cloned a
second time, no second registry is introduced, and the original request graph is never mutated,
reset, set up, or ticked. A repeated provider reference within a registry, stale binding, missing
identity proof, failed attachment, or missing/failed generic or S2-specific factory rejects before
capture or tick.
`reset_runtime()` is only a transient reset, not provider rewind or a replay baseline.
Replay fingerprints stable initial config/identity, includes advanced owner/port runtime snapshots
in deterministic sim hashes, and restores fresh objects to their exact immediate pre-tick state on
rollback. No second provider registry is introduced. `ReplayInputSource` reads only frames for
sampling; each replay path obtains exactly one `ReplaySourceRow` from `InputLog.read_replay_row`
per index, carrying detached frame/command/output values and an opaque identity issued by that log
for its object, index, row generation, and full row. Legacy defensive-copy accessors are not token
authority. The one codec decodes existing v3 records to concrete `S2RuntimeCommand` and
`S2RuntimeResult` values; S1 adds no command payload schema. Live detached typed action commands
are validated and enqueued once; port readback remains authoritative. Replay checks the carried set,
injects only the next contiguous new sequence suffix, verifies canonical readback, and compares
generated outputs with expected records including linkage.

One build-owned `ReplayValidationAuthority` is shared by that build's `MatchSim` and single codec.
Only the codec private mint path registers a nonce and exact `ReplayValidationToken` object after
validating the exact source row, sequences, readback, linkage, and generated outputs. The token
binds authority, sim, prepared tick, row capability, readback identity, expected/generated output
identities, and exact comparison success. Finalization asks the authority to validate and consume
that registered object once; abort invalidates outstanding receipts. Forged/copy/reassembled,
cross-paired, stale, aborted, or reused tokens fail, and failed validation returns no usable token.

For a `ReplayInputSource`, `MatchRunner.start` names `build_replay(request)`; other sources use
`build(request)`. Both runner and direct replay complete `build_replay(request)` and check header
compatibility against the fresh build before calling the fresh port's `reset_runtime()` exactly
once. It clears transient pending commands, results, consumed-sequence state, next sequence, and
failure metadata; it preserves fresh provider references, setup and initialization, wind/environment,
and all other injected dependencies. It never clears or replaces provider injection. A false reset
return is a typed terminal replay error before polling, tick, or publication. Runner replay exposes a
terminal typed mismatch/error status and does not mutate or append to its source log. Direct replay
compares every frame's generated output and rejects invalid/mismatched rows without accepting or
publishing that tick. Direct `ReplayFailure` includes `FATAL_ROLLBACK`, distinct from
ordinary/retryable `TICK_FAILED`: its `MatchReplayResult` has `sim == null`, non-OK error,
`fatal_reason: StringName` (non-empty only for `FATAL_ROLLBACK`), preserved build readiness,
unchanged source log, and no publication. A restore failure remains terminal `FATAL_ROLLBACK`, never
an invitation to retry.

Replay compatibility compares the header with current expected identities: explicit current
`action_layout_hash` from `MatchCompositionRequest`, mod-set hash, tick rate, and freshly derived
setup fingerprint. Runner replay requires a non-empty current action-layout identity; the recorded
source `layout_hash()` is never used as proof. Both paths reject a mismatch before source polling,
owner capture, tick, append, or publication. Replay seed comes from the recorded header. The
fingerprint covers effective config/resources, ordered participant identity/version, deterministic
initial setup/state, and each provider's stable identity/version/configuration/initial state as
reported by its unique owner. Live runner startup and direct replay use the same request and
builder, including extension points and one S2 runtime port; missing contact/setup inputs remain
typed readiness blockers. Replay v1/v2 remain parseable and round-trip compatible, while playback
accepts exactly v3 with its existing wire layout and record fields unchanged. Fatigue snapshot fields
retain their v3 timing and are consumed once at their existing phase.

Each setup result is a constructible success/failure record carrying capability, one canonical
participant claim, and owned provider claims. Its provider claims must agree with the replay
factory-result claims after fresh construction. The participant claim carries non-empty stable
participant id/version, configuration fingerprint, and deterministic initial-state fingerprint;
those fields are consumed by setup fingerprinting. The legacy `system_id() == &"system"` default is
not an identity. Each typed setup provider claim carries the provider reference (for per-registry
duplicate-ownership and exact S2 binding/setup-claim identity checks), non-empty stable provider
id/version, transaction capability, configuration fingerprint, and deterministic initial-state
fingerprint. The reference is never serialized or included in setup fingerprinting as an object
address; stable claim values alone feed the fingerprint. Repeated provider references are rejected
within each effective ordered registry, including stateless repeats and repeats by one owner.
An explicitly stateless participant may be the same instance in the separate live and replay
registries. A provider declared `EXPLICITLY_STATELESS` may use the same reference once in each
separate registry, with one registered owner per registry emitting its unique claim. Neither case
permits repeated references within either registry.
Owners retain checkpoint/restore responsibility for their providers, with no second registry.

Replay migration keeps v1 and v2 header/input structures parseable and round-trip compatible,
preserving their format version and version-specific fields. A v1 header omits the setup fingerprint
on wire, parses to an empty in-memory fingerprint, and serializes without adding the field. A v2
header requires the field to exist and be a String but preserves its value, including the empty
string, on parse/round-trip. A v3 header requires a present, correctly typed, non-empty fingerprint;
parsing rejects a missing, wrongly typed, or empty v3 value. Playback
accepts exactly v3:
`ReplayHeader.is_compatible_with`, `MatchRunner.start`, and direct `MatchReplay.run` reject formats
below v3 before setup capture or tick. Direct `MatchReplay.run` also independently validates mod,
current action-layout, a constructible non-empty setup fingerprint, and tick-rate identities before
capture or tick. Its typed `InputLog`/`ReplayHeader` inputs cannot carry a wrongly typed fingerprint;
parser rejection of that malformed input belongs to `ReplayHeader.from_dict` and
`InputLog.from_bytes`. There is no supported v3 variant without the fingerprint. Format v3 keeps
its current per-frame `runtime.commands` and `runtime.outputs` wire rows and existing record field
layouts unchanged.

Current replay-v3 fatigue snapshot fields and meanings remain unchanged. The v3 adapter consumes
them as recorded at the existing input phase; any owner-maintained derived state must not apply the
same payload a second time. A future semantic or schema change requires a new format and explicit
v3 adapter. Extra time, world-pause behavior, and clock/replay migration policy remain open and are
not inferred by this generic lifecycle decision.

## Consequences

- Headless tests can build and tick a `MatchSim` without a scene tree. Determinism tests compare
  hashes per tick.
- Every later slice extends the sim with `SimSystem`s, opt-in generic tick owners,
  `MatchCondition`s, Resource fields and data. The core lifecycle remains shared; participant
  behavior stays outside S1-specific rules.
- Moddable asset loads must go through `ModRuntime`. Code that calls `load()` directly on a
  moddable asset path is a review finding.
- Floating-point results across operating systems are not proven identical yet. Sim code should
  prefer integer or quantised state for outcome-deciding values and avoid transcendental functions
  in those paths; Phase 4 runs cross-OS determinism checks.
- Local multiplayer device-to-slot assignment is not designed beyond the multi-slot frame format;
  v1 samples all devices into slot 0.
- Changing the tick rate, the `InputFrame` byte layout or the mod set hash formula invalidates
  replays and needs a new ADR.
- Versioned owner setup/state contributes to replay identity; a different setup fingerprint is
  incompatible with the recorded match.
- Stateful participants must declare complete transactional checkpoint/restore before they can
  be registered; empty checkpoints are reserved for explicitly stateless participants. Runner
  callers handle recoverable tick/preparation failures separately from fatal rollback, source
  exhaustion, stopped, and finished results. Checked flow failures participate in rollback.
  Replay callers provide current expected action/setup identities. V1 headers preserve their
  fingerprint-free wire layout with an empty in-memory fingerprint; v2 requires a present String
  and preserves even an empty fingerprint, while v3 requires a non-empty typed fingerprint and
  playback stays v3-only. V1/v2 round trips and v3 fingerprint and fatigue semantics remain stable. Direct replay calls enforce the same v3 gate and
  constructible identity checks as runner-based playback; malformed serialized fingerprints are
  rejected by the parsers.
