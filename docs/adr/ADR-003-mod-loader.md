# ADR-003: Built-in mod loader; Classic base game, modern features as mods

- Status: Accepted
- Date: 2026-10-14

## Context

The default experience must stay faithful to Rugby 08, while modernisation (current laws,
widescreen HUD, QoL, AI tuning) and community content should be possible without forking.

## Decision

Build a mod loader in `game/mods/`. Base game data is "mod zero"; enabled mods apply after it in
load order.

- `mod.json` manifest: id, name, version, author, description, `game_version` compatibility,
  dependencies, load priority, capabilities (`data`, `assets`, `rules`, `scripts`, `ui`).
- Three override layers in order: (1) data overrides, Resource patches by path and field
  (merge, not replace); (2) asset overrides, a mod's `res://`-relative tree shadows base assets;
  (3) script hooks, GDScript subscribing to the event bus and registered extension points. Hooks
  are the only way a mod runs code.
- Built-in mods live in `mods/` and ship in the build. External mods are `.pck` files loaded from
  `user://mods/` via `ProjectSettings.load_resource_pack`.
- Profiles: "Classic" (no mods, default) and "Modern" (first-party pack).
- Script-capable mods run arbitrary GDScript; they are flagged and the UI warns on enabling one
  from `user://`. There is no sandbox, and docs say so.
- The sim stays deterministic with mods enabled; the mod set is part of the replay header.
- New features are built as mods first; the base gains extension points, not features, unless
  the change is a pure bug fix or a cross-cutting platform capability.

## Consequences

- Nothing a modder might change may be hard-coded; data lives in `Resource`s (see CONVENTIONS).
- Loader core ships in slice S1; the manager UI, `.pck` loading and `tools/modcheck.py` in S11.
- Enabling then disabling the Modern pack must not change base-game test results.
