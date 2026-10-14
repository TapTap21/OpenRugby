# S1-modloader: mod loader core

- Slice: S1 (mod loader core). Architecture: [ADR-003](../adr/ADR-003-mod-loader.md),
  [ADR-004](../adr/ADR-004-core-architecture.md) section 5, PLAN section 1d.
- Reimplementation, not a port (PLAN section 4 rule 0, CONVENTIONS "Reimplementation, not a
  port"): only Rugby 08's observable behaviour and numeric constants are carried over, always
  into named Resource fields with units. Names, structure, update order and data layouts are
  ours; when RE findings land they fill data, never reshape these classes after the original.
- Out of scope (S11): mod manager UI, profiles UI, `tools/modcheck.py`, modding docs, the
  first-party Modern pack. S1 delivers the runtime those build on.

## 1. Files and classes

All under `game/mods/`, typed GDScript with `class_name`, per `docs/CONVENTIONS.md`.

| File | `class_name` | Base | Role |
|---|---|---|---|
| `mod_issue.gd` | `ModIssue` | `RefCounted` | one error or warning |
| `mod_version.gd` | `ModVersion` | `RefCounted` | semver value |
| `version_constraint.gd` | `VersionConstraint` | `RefCounted` | version range |
| `mod_dependency.gd` | `ModDependency` | `RefCounted` | one dependency |
| `mod_manifest.gd` | `ModManifest` | `RefCounted` | parsed `mod.json` |
| `mod_load_plan.gd` | `ModLoadPlan` | `RefCounted` | resolved order + issues |
| `override_ledger.gd` | `OverrideLedger` | `RefCounted` | provenance and conflicts |
| `resource_patcher.gd` | `ResourcePatcher` | `RefCounted` | layer 1 engine, JSON fill |
| `extension_points.gd` | `ExtensionPoints` | `RefCounted` | layer 3 registry |
| `base_extension_points.gd` | `BaseExtensionPoints` | `RefCounted` | points the base declares |
| `mod_entry.gd` | `ModEntry` | `RefCounted` | base for mod entry scripts |
| `mod_api.gd` | `ModApi` | `RefCounted` | what an entry script gets |
| `mod_runtime.gd` | `ModRuntime` | `RefCounted` | applied state |
| `mod_loader.gd` | `ModLoader` | `RefCounted` | discover, resolve, apply |

Internal helpers may be added (private classes or extra files) as long as the public API below
is unchanged. `ModLoader` is not an autoload: `Main` owns it and passes the `ModRuntime` down.

## 2. Mod layout and manifest

```
<root>/<id>/mod.json          manifest (required)
<root>/<id>/data/*.json       data patch files (layer 1), needs capability "data"
<root>/<id>/overrides/**      asset shadow tree (layer 2), needs capability "assets"
<root>/<id>/<entry_script>    entry script (layer 3), needs capability "scripts"
```

`mod.json`, schema version 1:

```json
{
  "schema_version": 1,
  "id": "example-mod",
  "name": "Example Mod",
  "version": "1.2.0",
  "author": "Someone",
  "description": "What it changes.",
  "game_version": ">=0.1.0 <0.2.0",
  "dependencies": [{ "id": "other-mod", "version": "^1.0.0", "optional": false }],
  "load_priority": 0,
  "capabilities": ["data", "assets", "rules", "scripts", "ui"],
  "entry_script": "main.gd"
}
```

| Key | Required | Type / rule | Default |
|---|---|---|---|
| `schema_version` | yes | integer; `> 1` is `manifest_unsupported_schema` | |
| `id` | yes | `^[a-z0-9][a-z0-9_-]{1,63}$`, not `base`, equals the folder name | |
| `name` | yes | non-empty string | |
| `version` | yes | semver (section 3) | |
| `author` | no | string | `""` |
| `description` | no | string | `""` |
| `game_version` | yes | version constraint (section 3) | |
| `dependencies` | no | array of `{id, version?, optional?}`; `version` defaults to `*`, `optional` to false; no self-dependency, no duplicate ids | `[]` |
| `load_priority` | no | integer in [-1000, 1000] (JSON numbers must be integral) | `0` |
| `capabilities` | yes | array of `data`, `assets`, `rules`, `scripts`, `ui`; no unknown values | |
| `entry_script` | iff `scripts` | relative path to a `.gd` inside the mod folder, no `..` | `""` |

Unknown top-level keys produce a `manifest_unknown_key` warning (forward compatibility).
Capability meanings: `data`, `assets`, `scripts` gate the three layers; `rules` declares that the
mod changes gameplay rules; `ui` is reserved for S11 menu injection (no S1 behaviour).
Mod entry scripts should not declare `class_name` (global class collisions between mods).

Security, stated plainly in docs and UI later: script mods run arbitrary GDScript. There is no
sandbox. Data- and asset-only mods cannot run code.

## 3. Versions

`ModVersion`: `static parse(text: String) -> ModVersion` (null when invalid) for
`MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]` (numeric parts without leading zeros except `0`;
build metadata accepted and ignored). Vars `major`, `minor`, `patch: int`,
`prerelease: PackedStringArray`. `compare(other: ModVersion) -> int` (-1, 0, 1) follows SemVer 2.0
precedence: numeric parts, then a version with a prerelease is lower than without, prerelease
identifiers compared left to right (numeric < alphanumeric, numerics numerically, others by ASCII,
a shorter list is lower when all shared identifiers are equal). `_to_string()` gives the canonical
text without build metadata.

`VersionConstraint`: `static parse(text: String) -> VersionConstraint` (null when invalid),
`matches(version: ModVersion) -> bool`. Grammar: alternatives separated by `||`; each alternative
is one or more whitespace-separated comparators that must all match. Comparators: `*` (any),
`X` or `=X` (equal), `>X`, `>=X`, `<X`, `<=X`, `^X` (`>=X` and below the next major; when major is
0, below the next minor), `~X` (`>=X` and below the next minor). `X` is always a full version.
Comparison is plain SemVer precedence (no special prerelease rules).

## 4. Discovery

`ModLoader._init(p_game_version: String = "", p_search_roots: PackedStringArray =
["res://mods", "user://mods"])`. Empty game version means
`ProjectSettings.get_setting("application/config/version")`.

`discover() -> Array[ModManifest]`:

1. For each search root, in order, that starts with `user://` and exists: mount every `*.pck`
   directly inside it, sorted by file name, with `ProjectSettings.load_resource_pack(path, false)`
   (never replaces existing files). A pack must contain its mod at `res://mods/<id>/`. Before and
   after each mount, list the directories of `res://mods`; each new directory is a mod from that
   pack (source `USER_PCK`, `pck_path` set). Mount failure gives `pck_mount_failed`; no new
   directory gives `pck_no_mod` (duplicate id or wrong layout).
2. For each search root in order, each subdirectory sorted by name: if it has `mod.json`, parse it
   (source `BUILTIN` under `res://`, `USER_FOLDER` under `user://`); else issue `manifest_missing`
   (warning). Then the pack mods from step 1, in mount order.
3. The first manifest with a given id wins; later ones get a `duplicate_id` error.

Missing roots are skipped silently. Discovery returns every manifest found, valid or not, so the
UI can show why a mod cannot load. Base is not included.

`ModManifest`:
`enum Source { BASE, BUILTIN, USER_FOLDER, USER_PCK }`; vars `id: StringName`, `name`, `author`,
`description`, `version_text`, `game_version_text`, `entry_script`, `root_path`, `pck_path: String`,
`version: ModVersion`, `game_version: VersionConstraint`, `dependencies: Array[ModDependency]`,
`load_priority: int`, `capabilities: PackedStringArray`, `source: Source`,
`issues: Array[ModIssue]`.
`static parse(data: Dictionary, root_path: String, source: Source) -> ModManifest` (never null;
problems become issues; the folder-name rule uses the last path segment of `root_path`),
`static load_file(root_path: String, source: Source) -> ModManifest` (reads
`root_path/mod.json`; unreadable or invalid JSON gives `manifest_parse_error`),
`static make_base(game_version: String) -> ModManifest` (id `base`, version = game version,
source `BASE`, root `res://`, all capabilities), `is_valid() -> bool` (no error issues),
`has_capability(capability: StringName) -> bool`, `is_script_mod() -> bool`.

`ModDependency`: `id: StringName`, `constraint: VersionConstraint`, `constraint_text: String`,
`optional: bool`.

`ModIssue`: `enum Severity { WARNING, ERROR }`; vars `code: StringName`, `mod_id: StringName`,
`message: String` (English developer text; S11 maps `code` to a translation key),
`severity: Severity`; `static error(code, mod_id, message) -> ModIssue`,
`static warning(code, mod_id, message) -> ModIssue`, `is_error() -> bool`.

## 5. Resolution and load order

`resolve(manifests: Array[ModManifest], enabled_ids: PackedStringArray) -> ModLoadPlan`:

1. Base is always first in the order.
2. Each enabled id is rejected with: `not_found` (not discovered), `invalid_manifest` (manifest
   has errors, including duplicates), or `game_version_mismatch` (constraint does not match the
   game version).
3. Dependencies are never enabled automatically. A required dependency that is not enabled or was
   rejected gives `missing_dependency`; one whose version does not match gives
   `dependency_version_mismatch`. An optional dependency that is enabled and accepted is treated as
   required (ordering and version check); one that is not enabled is ignored. Repeat until no new
   rejection (rejections propagate to dependents).
4. Remaining mods in a dependency cycle are rejected with `dependency_cycle`, then step 3 runs again.
5. Order: Kahn's topological sort, every dependency before its dependents; among ready mods pick
   the smallest `(load_priority, id)` (id compared as String).
6. Each rejection adds an error issue for the rejected mod; the enabled list order has no effect.

`ModLoadPlan`: `game_version: String`, `order: Array[ModManifest]` (base first),
`rejected: Dictionary[StringName, ModIssue]` (first reason per id), `issues: Array[ModIssue]`,
`load_order_ids() -> PackedStringArray`, `mod_set_hash() -> String`.

Mod set hash: lines `"<id>@<version_text>"` for each mod in `order` (base as
`base@<game_version>`), joined with `"\n"` (no trailing newline), UTF-8, SHA-256, lowercase hex.
Replay headers store it (S1-core `ReplayHeader.mod_set_hash`).

## 6. Applying (the three layers)

`apply(plan: ModLoadPlan) -> ModRuntime`. In this order:

1. **Asset map (layer 2 bookkeeping).** For each mod after base in order with an `overrides/`
   folder: without capability `assets` add `capability_missing` (warning) and skip. Otherwise walk
   it recursively; each file `overrides/<rel>` maps `res://<rel>` to `<root>/overrides/<rel>`.
   Files ending `.import` or `.remap` map the path without that suffix (exported packs keep only
   these); `.uid` files are ignored. Later mods replace earlier entries. Every mapping is recorded
   in the ledger with `record_asset`. The map is built before data patches so that resource paths
   inside patches resolve through it.
2. **Data patches (layer 1).** For each mod after base in order with a `data/` folder: without
   capability `data` add `capability_missing` (warning) and skip. Otherwise apply every
   `data/*.json` sorted by file name (format in section 7).
3. **Script hooks (layer 3).** For each mod after base in order with capability `scripts`: load
   `<root>/<entry_script>`; if it does not load, cannot be instantiated, or the instance is not a
   `ModEntry`, add `entry_script_invalid` (error; the mod's other layers stay applied). Otherwise
   call `_mod_init(api)` with a `ModApi` for that mod.
4. Emit `EventBus.mods_loaded(runtime.mod_set_hash)`.

The runtime's issues are the plan issues followed by the apply issues.

## 7. Data patches (layer 1) and `ResourcePatcher`

Patch file:

```json
{
  "patches": [
    {
      "target": "res://game/data/defaults/default_rules.tres",
      "fields": {
        "points_penalty_try": 7,
        "penalty_try_awards_conversion": false,
        "extra": { "fifty_22": 1.0, "old_key": null },
        "home_kit/primary_color": "#c8102e",
        "squad": { "$append": ["res://mods/example-mod/data/new_player.tres"] },
        "preferred_foot": "LEFT"
      }
    }
  ]
}
```

- `target` is a resource path loaded through `ModRuntime.load_resource` (so asset overrides
  apply). Missing: `patch_target_missing` (error), the entry is skipped.
- Field paths are `/`-separated. Each segment resolves against the current value: on a `Resource`
  an exported property (`PROPERTY_USAGE_STORAGE`) name, on a `Dictionary` a key (converted to the
  dictionary's typed key type, e.g. `StringName`), on an `Array` a 0-based existing index.
  Anything else is `patch_unknown_field` (error, that field only).
- Value rules by the declared type of the final target:
  - `bool`: JSON bool. `int`: integral JSON number. `float`: any number. `String`, `StringName`:
    string. Int property with an enum hint: integral number or the enum key name as a string.
  - `Color`: `"#rrggbb"`, `"#rrggbbaa"`, or `[r, g, b]` / `[r, g, b, a]` in 0..1.
    `Vector2` / `Vector3`: `[x, y]` / `[x, y, z]`.
  - `Resource`-typed: a string is a resource path loaded through the runtime and must be an
    instance of the declared class; a JSON object is merged field by field into the existing
    nested resource (null existing: `patch_type_mismatch`); JSON null sets null.
  - `Dictionary`: a JSON object merges key by key (null value erases the key, an object value
    merges recursively into an existing dictionary value, anything else replaces); typed key and
    value types are enforced. `{"$replace": {...}}` replaces the whole dictionary.
  - `Array`: a JSON array replaces the whole array; `{"$append": [...]}` appends;
    `{"$replace": [...]}` replaces. Elements are converted to the array's typed element type
    (strings become resources for resource arrays). Any other `$` key is `patch_unknown_op`.
  - Anything else, or a failed conversion: `patch_type_mismatch` (error, that field only).
- Patches mutate the loaded resource in place, so every `load()` of that path and every resource
  referencing it sees the change. The runtime keeps strong references to every patched resource
  for its lifetime (Godot's cache is weak).
- Before the first change to a given `(object, property)` the patcher stores its old value
  (dictionaries and arrays duplicated, shallow). `revert()` restores all of them in reverse order.
- Every applied leaf is recorded with `ledger.record_field(target, field_path, mod_id)`; a
  dictionary merge records one leaf per key (`extra/fifty_22`), a nested object merge one per
  nested field (`home_kit/primary_color`).
- If the target's script global class is `RulesConfig` or `MatchFlowConfig` and the mod lacks
  capability `rules`, add `capability_undeclared_rules` (warning; the patch still applies).
- Unreadable or invalid JSON, or no `patches` array: `patch_parse_error` (error, file skipped).

`ResourcePatcher`:
`_init(p_ledger: OverrideLedger = null, p_load_resource: Callable = Callable())` (a null callable
means plain `load()`), `apply(target: Resource, target_path: String, fields: Dictionary,
mod_id: StringName) -> Array[ModIssue]`, `revert() -> void`,
`static fill(resource: Resource, data: Dictionary) -> Array[ModIssue]` (same rules, no ledger,
mod id `base`; this is the JSON-to-Resource loader for extracted data).

## 8. Override ledger and conflicts

`OverrideLedger`: `record_field(resource_path: String, field_path: String, mod_id: StringName)`,
`record_asset(res_path: String, mod_id: StringName)`,
`last_writer(resource_path: String, field_path: String) -> StringName` (`&"base"` if never
patched), `field_writers(resource_path, field_path) -> Array[StringName]` (in write order, repeats
kept), `asset_owner(res_path: String) -> StringName` (`&"base"` if not shadowed),
`asset_writers(res_path) -> Array[StringName]`, `conflicts() -> Array[Dictionary]`, `clear()`.

A conflict is a field or asset touched by two or more distinct mods. Each entry:
`{"kind": &"field" or &"asset", "target": String, "field": String ("" for assets),
"mods": Array[StringName] (distinct, in first-write order), "winner": StringName}`; sorted by
kind (`asset` before `field`), then target, then field. One mod writing a field twice is not a
conflict.

## 9. Extension points and script hooks (layer 3)

`ExtensionPoints`: `enum Kind { OBSERVER, FILTER, PROVIDER }`;
`declare(point: StringName, kind: Kind, description: String = "") -> Error`
(`ERR_ALREADY_EXISTS` on redeclare), `is_declared(point) -> bool`, `kind_of(point) -> Kind`,
`register(point: StringName, mod_id: StringName, callable: Callable, priority: int = 0) -> Error`
(`ERR_DOES_NOT_EXIST` for an undeclared point, `ERR_INVALID_PARAMETER` for an invalid callable),
`unregister_mod(mod_id: StringName) -> void`, `hooks(point) -> Array[Callable]` (call order),
`notify(point, args: Array = []) -> void` (OBSERVER: each hook `callv(args)`),
`filter(point, value: Variant, args: Array = []) -> Variant` (FILTER: each hook receives
`[value] + args` and returns the new value), `collect(point, args: Array = []) -> Array`
(PROVIDER: each hook's non-null return value appended), `declared_points() -> PackedStringArray`
(sorted). Calling the wrong method for a point's kind `push_error`s and returns the input value
(filter) or empty (collect). Call order: ascending priority, ties in registration order (mods
register in load order, so ties follow load order).

`BaseExtensionPoints`: `static declare_into(points: ExtensionPoints) -> void` declares the base
points. S1 declares:

| Point | Kind | Contract |
|---|---|---|
| `match.sim_systems` | PROVIDER | args `[config: MatchConfig]`; return a `SimSystem` (or null); the runner adds them after base systems, in hook order |
| `match.flow_config` | FILTER | value `MatchFlowConfig`, args `[config: MatchConfig]`; return the flow to use |

Later slices add points here (rule hooks in S3, AI behaviours in S5, menu injection in S11).

`ModEntry` (entry scripts extend it): virtual `_mod_init(api: ModApi) -> void` and
`_mod_shutdown() -> void`, both empty by default.

`ModApi`: read-only `mod_id: StringName`;
`register_hook(point: StringName, callable: Callable, priority: int = 0) -> Error` (an undeclared
point also adds a `hook_undeclared_point` error issue to the runtime);
`connect_event(signal_name: StringName, callable: Callable) -> Error` (connects to an `EventBus`
signal, `ERR_DOES_NOT_EXIST` if the bus has no such signal; tracked so `revert` disconnects it);
`load_resource(path: String) -> Resource`; `resolve_asset_path(path: String) -> String`.
The API exposes no scene tree access. Mods are trusted code, so this is a convention, not a
sandbox.

## 10. Runtime

`ModRuntime`: vars `game_version: String`, `mod_set_hash: String`,
`load_order: PackedStringArray`, `manifests: Array[ModManifest]` (applied, base first),
`issues: Array[ModIssue]`, `extension_points: ExtensionPoints` (created with base points
declared), `ledger: OverrideLedger`;
`resolve_asset_path(path: String) -> String` (shadow path or `path` unchanged),
`load_resource(path: String) -> Resource` (`ResourceLoader.load(resolve_asset_path(path))`, kept
strongly referenced), `has_errors() -> bool`, `is_active() -> bool`,
`revert() -> void`: call `_mod_shutdown()` on entries in reverse load order, unregister their
hooks, disconnect their events, undo every data patch, clear the asset map and the ledger, and
become inactive. Mounted packs stay mounted (Godot cannot unmount). The shipped game applies mods
once at boot and asks for a restart when the enabled set changes; `revert` exists for tests and
for the "Modern on, then off, changes nothing" check.

`ModLoader.load_mods(enabled_ids: PackedStringArray) -> ModRuntime` is
`apply(resolve(discover(), enabled_ids))`. With no enabled mods (the Classic profile) the runtime
has only base, an empty asset map, no patches and the hash of `base@<game_version>`.

## 11. Acceptance criteria

Tests in `tests/unit/mods/`, fixtures in `tests/fixtures/mods/` (search root
`res://tests/fixtures/mods`) and `tests/fixtures/data/`. Fixture mods must be valid per this spec
unless they exist to test a failure; `.pck` fixtures are generated at test time with `PCKPacker`
into `user://`, never committed. Every test that applies patches calls `revert()` afterwards.

**Versions**
- M-01 `ModVersion.parse` accepts `1.2.3`, `0.1.0-beta.2`, `1.0.0+build.5`; rejects `1.2`,
  `01.2.3`, `a.b.c`, `""`.
- M-02 Precedence: `1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-rc.1 < 1.0.0
  < 1.0.1 < 1.1.0 < 2.0.0`.
- M-03 Constraints: `^1.2.0` matches 1.9.9 not 2.0.0; `^0.2.0` matches 0.2.5 not 0.3.0; `~1.2.0`
  matches 1.2.9 not 1.3.0; `>=1.0.0 <2.0.0` matches 1.5.0 not 2.0.0; `1.0.0 || 3.0.0` matches 3.0.0
  not 2.0.0; `*` matches anything; `>=x` is invalid (parse returns null).

**Manifest**
- M-04 A complete valid manifest parses with every field as given and `is_valid()` true;
  optional keys absent give the defaults of section 2.
- M-05 One test per rule, each giving an error issue with the code shown: missing required key
  (`manifest_invalid_field`), bad id pattern (`manifest_invalid_field`), id `base`
  (`manifest_reserved_id`), id not equal to folder name (`manifest_id_mismatch`), bad version or
  constraint (`manifest_invalid_field`), unknown capability (`manifest_invalid_field`), `scripts`
  without `entry_script` and `entry_script` without `scripts` (`manifest_invalid_field`),
  `schema_version` 2 (`manifest_unsupported_schema`), invalid JSON file (`manifest_parse_error`).
- M-06 An unknown top-level key gives a `manifest_unknown_key` warning and `is_valid()` stays true.

**Discovery**
- M-07 Discovering `res://tests/fixtures/mods` returns one manifest per fixture folder with
  `mod.json`, sorted by folder name, source `BUILTIN`, `root_path` set.
- M-08 Two roots containing the same id: the first root's manifest is valid, the second has
  `duplicate_id`.
- M-09 A `.pck` generated at test time into a fresh `user://` folder (containing
  `res://mods/<unique-id>/mod.json`) is mounted and discovered with source `USER_PCK` and
  `pck_path` set.
- M-10 A missing search root is skipped with no issues.

**Resolution**
- M-11 With no enabled ids, the order is `[base]` and the hash equals SHA-256 of
  `base@<game_version>`.
- M-12 Dependencies load before dependents regardless of `load_priority` and enabled-list order.
- M-13 Independent mods order by `(load_priority, id)`: priorities `-5`, `0`, `0`, `10` with ids
  chosen to show the id tie-break.
- M-14 Rejections with codes: unknown enabled id (`not_found`), dependency not enabled
  (`missing_dependency`), dependency version mismatch (`dependency_version_mismatch`), game version
  mismatch (`game_version_mismatch`), two-mod cycle (both `dependency_cycle`), and a mod depending on
  a rejected mod is also rejected.
- M-15 An optional dependency that is not enabled is ignored; when enabled it loads first.
- M-16 The mod set hash changes when a mod's version or the order changes, and is identical for
  two resolutions of the same input.

**Data layer**
- M-17 Patching an int, float, bool, String, StringName, enum (by name), Color (hex and array)
  and Vector3 field sets the value; a second `load()` of the target path returns the same patched
  instance.
- M-18 Dictionary merge: patching `{"a": 1, "b": null}` onto `{"b": 2, "c": 3}` gives
  `{"c": 3, "a": 1}`; `$replace` replaces.
- M-19 Arrays: plain array replaces, `$append` appends, a resource array accepts resource paths.
- M-20 Nested path `kit/primary_color` and nested object merge `{"kit": {"primary_color": ...}}`
  both change the nested resource.
- M-21 Unknown field, wrong type, non-integral number for an int, missing target and invalid JSON
  give `patch_unknown_field`, `patch_type_mismatch`, `patch_type_mismatch`, `patch_target_missing`
  and `patch_parse_error`; the other fields in the same patch still apply.
- M-22 Two mods patch the same field: the later in load order wins; `last_writer` is the later
  mod; `field_writers` lists both; `conflicts()` has one `field` entry with both mods and that
  winner. An untouched field's `last_writer` is `base`.
- M-23 `revert()` restores every patched value, including dictionary and array contents, to its
  exact original value.
- M-24 A data patch in a mod without capability `data` is not applied and gives a
  `capability_missing` warning; a `RulesConfig` patch without `rules` gives
  `capability_undeclared_rules` and still applies.
- M-25 `ResourcePatcher.fill` builds a fixture `Team` with a nested kit and an attribute
  dictionary from a JSON object.

**Asset layer**
- M-26 A mod with `overrides/<rel>` makes `resolve_asset_path("res://<rel>")` return the mod's
  file; an unshadowed path is returned unchanged; `load_resource` loads the shadow.
- M-27 Two mods shadowing one path: the later wins, `asset_owner` is the later mod, and
  `conflicts()` has an `asset` entry.
- M-28 An `overrides/` folder without capability `assets` is ignored with `capability_missing`.

**Script layer**
- M-29 A fixture script mod registers a FILTER hook on `match.flow_config` and an OBSERVER on a
  test-declared point; `filter` returns the hook's value and `notify` reaches it; its
  `_mod_init` ran once.
- M-30 Hooks run in ascending priority, ties in load order.
- M-31 `register_hook` on an undeclared point returns `ERR_DOES_NOT_EXIST` and adds
  `hook_undeclared_point`.
- M-32 An entry script that does not extend `ModEntry` gives `entry_script_invalid`.
- M-33 `connect_event(&"match_finished", cb)` receives the signal when `EventBus` emits it;
  after `revert()` it no longer does, `_mod_shutdown` ran, and the point has no hooks.
- M-34 `BaseExtensionPoints.declare_into` declares `match.sim_systems` (PROVIDER) and
  `match.flow_config` (FILTER).

**End to end**
- M-35 `load_mods([])` on the fixture root has `load_order == ["base"]`, no errors, and emits
  `EventBus.mods_loaded` with its hash.
- M-36 Classic invariance: snapshot every field of the patched fixture resources, `load_mods` with
  all valid fixture mods enabled, `revert()`, and the snapshot is identical.
