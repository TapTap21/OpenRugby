# S1 / S9 resume plan (checkpoint, 2026-10-14)

Temporary handover note for the slice lead. Delete it before the slice is merged.

- Branch: `slice/s1-core-modloader-input` (from `main` at `e8de46a`)
- Worktree: `/home/wernich/.t3/projects/openrugby/.claude/worktrees/agent-a1714ed829cad0cda`
- Lead: S1/S9 architect (Opus 5.5)

## Done and committed

1. `docs/adr/ADR-004-core-architecture.md`, `docs/specs/S1-core.md`, `docs/specs/S1-modloader.md`,
   `docs/specs/S9-input.md` (acceptance criteria C-01..C-44, M-01..M-36, I-01..I-19).
2. Shared files edited once by the lead so implementers do not collide: `autoload/event_bus.gd`
   (typed S1/S9 signals), `project.godot` (`application/config/version="0.1.0"`),
   `localization/translations.csv` (INPUT_ACTION_* and preset keys).
3. CHANGELOG entry (this checkpoint commit).

## Sub-agents at checkpoint time (none had written files yet)

| Name | Model / effort | Owns | Status |
|---|---|---|---|
| `s1-impl-core` | Sonnet 5.5 / medium | `game/match/**`, `game/data/**` | reading specs, implementing S1-core |
| `s1-impl-modloader` | Opus 5.5 / high | `game/mods/**` | reading specs, implementing S1-modloader |
| `s9-impl-input` | Haiku 5.5 / medium | `game/platform/input/**`, `autoload/game_settings.gd` | reading specs, implementing S9 |
| `s1-tests` | Haiku 5.5 / medium | `tests/**` (unit, sim, fixtures) | NOT STARTED: launch hit the session's concurrent sub-agent cap |

Implementers do not commit; the lead commits. All Godot runs are wrapped in
`flock /tmp/openrugby-s1-godot.lock ...` because agents share one project dir.

## Next steps

1. If the implementers were stopped, resume them by name (SendMessage) or relaunch with the same
   briefs (spec path, owned files, typing/warnings-as-errors rules, flock rule, no commits).
2. Launch `s1-tests` as soon as a sub-agent slot is free: tests from the specs only (never read
   `game/`), every criterion id covered, fixtures in `tests/fixtures/mods` and
   `tests/fixtures/data`, `.pck` fixtures generated at test time, assertion chains assigned under
   `@warning_ignore("unused_variable")`.
3. Lead integration after implementers finish: wire `Main` to own a `ModLoader`/`ModRuntime`
   (enabled ids empty = Classic), check `GameSettings.input_bindings`, remove `.gitkeep` files in
   filled folders.
4. Verify in the worktree: `scripts/check-godot-safe.sh`, `godot --headless --path . --import`,
   `scripts/test.sh`, `gdlint game autoload tests mods`,
   `gdformat --check --line-length 100 game autoload tests mods`, `scripts/hygiene.sh`.
   Fix loop with implementers, max 3 rounds.
5. Commit per area (core, modloader, input, tests) with conventional commits and trailers, delete
   this file, report to the orchestrator. Do not merge to main.

## Open questions for RE leads (to include in the report)

- p1-frontend-lead: Rugby 08 control list and default bindings (`Data/controltypes.csv`); does any
  action need analog strength in the sim beyond the move stick (kick power, sprint)?
- p1-rules-lead: does the clock run during kick-off and stoppages; period count and length options;
  points table and penalty try handling in the 2007 build; sin-bin length.
- p1-players-lead: attribute list and ranges; position ids.
- p1-ai-lead: difficulty levels and tuning parameters.
- p1-gamedata-lead: pitch dimensions and in-goal depth per stadium; kit fields.
- p1-modes-lead: match-length options (real minutes per half).
