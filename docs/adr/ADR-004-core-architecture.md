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
  It advances only through `tick(frame: InputFrame)`. Nothing else mutates it between ticks except
  `raise_trigger()` (queued until the next tick) and setup calls before the first tick.
- `MatchRunner` (a `Node`) owns the sim. In `_physics_process` it fills one `InputFrame` from an
  `InputSource` (live devices or a replay log), calls `tick`, appends the frame to the `InputLog`,
  then relays sim signals to `EventBus`. It is the only bridge between sim and scene tree.
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
- Subsystems that later slices add (ball, players, rules, AI) implement `SimSystem` and are
  registered on the sim in a fixed order. The order is part of the determinism contract.

### 2. Event bus usage

`EventBus` (autoload) carries typed, past-tense signals for events that cross feature folders,
e.g. sim to HUD, mod loader to UI. Intra-feature communication uses local signals ("call down,
signal up"). The sim never touches `EventBus`; the runner relays after each tick, so listeners
(HUD, audio, mod hooks) can never run in the middle of a tick. Listeners must not mutate sim state;
mods that need to change sim behaviour use declared extension points, which the sim calls
deterministically. Each signal documents its owning slice; adding one is a spec change.

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

## Consequences

- Headless tests can build and tick a `MatchSim` without a scene tree. Determinism tests compare
  hashes per tick.
- Every later slice extends the sim by adding `SimSystem`s, `MatchCondition`s, Resource fields
  and data, not by editing the core loop.
- Moddable asset loads must go through `ModRuntime`. Code that calls `load()` directly on a
  moddable asset path is a review finding.
- Floating-point results across operating systems are not proven identical yet. Sim code should
  prefer integer or quantised state for outcome-deciding values and avoid transcendental functions
  in those paths; Phase 4 runs cross-OS determinism checks.
- Local multiplayer device-to-slot assignment is not designed beyond the multi-slot frame format;
  v1 samples all devices into slot 0.
- Changing the tick rate, the `InputFrame` byte layout or the mod set hash formula invalidates
  replays and needs a new ADR.
