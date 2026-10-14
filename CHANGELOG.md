# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Project scaffold: Godot 4.7.2 project (Compatibility renderer, Jolt, 60 Hz physics tick),
  strict typed-GDScript warnings, `autoload/` event bus and settings stubs.
- gdUnit4 6.2.2 vendored in `addons/` with a headless runner (`scripts/test.sh`).
- Export presets for Linux, Windows and macOS.
- Lint and hygiene tooling: gdlint, gdformat, ruff, pre-commit, `scripts/hygiene.sh`.
- GitHub Actions for lint, tests, export smoke builds and tagged releases.
- Documentation: conventions, ADR-001 to ADR-003, contributing guide, code of conduct.
- ADR-004 (core architecture) and slice specs S1-core, S1-modloader, S9-input in `docs/specs/`.
- S1 core: deterministic `MatchSim` advanced by per-tick `InputFrame`s with an owned seeded RNG,
  `MatchRunner`, input log and replay, data-driven match flow (pre-match to full-time) with a
  period clock, `PitchGeometry` and the data Resources (players, teams, kits, stadiums, rules,
  difficulty, camera presets).
- S1 mod loader core: `mod.json` manifests, discovery (built-in folders, `user://` folders and
  `.pck` packs), dependency and version resolution, deterministic load order, data patches, asset
  shadowing, script hooks on declared extension points, override ledger and mod set hash.
- S9 input: data-defined input actions with gamepad-first defaults, remapping with conflict
  detection, `user://` persistence with a schema version, and sampling into replayable frames.
