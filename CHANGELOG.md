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
