# S1-modloader resume plan

State at handover (2026-10-14, s1-impl-modloader). Spec: `S1-modloader.md`.

## Done
- Every spec class lives in `game/mods/`: `ModIssue`, `ModVersion`, `VersionConstraint`,
  `ModDependency`, `ModManifest`, `ModLoadPlan`, `OverrideLedger`, `ResourcePatcher`,
  `ExtensionPoints`, `BaseExtensionPoints`, `ModEntry`, `ModApi`, `ModRuntime`, `ModLoader`.
- Internal helpers: `ModDiscovery` (scans roots, mounts packs, remembers mounted packs for the
  whole process), `ModResolver`, `ModApplier`, `PatchValues`.
- gdlint and gdformat are clean. `--import` gives no script errors.
- `scripts/test.sh res://tests/unit/mods`: 58 test cases, 0 errors, 0 failures.

## Failing
- Nothing known.

## Acceptance criteria
- M-01 to M-36 are all covered by passing tests in `tests/unit/mods/`. None are unverified.
- Not covered by tests: packed-array patches, `Vector2i`/`Vector4` patches, a manifest that
  depends on `base`, and a resource shadowed by `overrides/` that is also the target of a data patch.

## Spec ambiguities resolved (keep, or update the spec)
- Discovery issues go in `ModLoader.discovery_issues`. `load_mods` puts them at the front of the
  plan issues.
- An optional dependency that is enabled but rejected is ignored.
- A dependency on `base` checks the game version.
- `fill()` creates null nested resources; `apply()` reports `patch_type_mismatch` instead.
- Revert stores deep copies of dictionaries and arrays and restores them in place.
- Enum names match exactly first, then ignoring case, spaces and underscores (Godot
  capitalizes enum names in the export hint).
- Patches can never set `script` or `resource_path`.

## Next
1. Document for modders (S11 docs): the project's warnings-as-errors settings apply to mod
   entry scripts, so an ignored return value of `register_hook()` makes the script fail to load.
2. Security gap: a data-only or asset-only mod can still run code through a `.tres` with an
   attached script, or a `.gd` / scripted `.tres` in `overrides/`. Either block script-bearing
   resources for mods without capability `scripts`, or state the limitation in ADR-003.
3. Optionally add tests for the uncovered cases listed under "Acceptance criteria".
