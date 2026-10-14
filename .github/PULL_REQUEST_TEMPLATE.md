## Summary

<!-- What changed and why. Link the slice/spec in docs/re or the issue. -->

## Conventions checklist

See [docs/CONVENTIONS.md](../docs/CONVENTIONS.md).

- [ ] `gdformat` and `gdlint` clean; static typing everywhere; strict warnings pass
- [ ] Naming and script member order follow CONVENTIONS.md; `##` docs on public API
- [ ] Composition, "call down, signal up"; no `get_parent()` chains; no new autoloads
- [ ] Tunable values live in `@export`ed Resources, not literals (mod loader can override)
- [ ] Sim code is fixed-step and deterministic; sim and presentation are separate
- [ ] All input via `InputMap`; all user-facing strings via `tr()`
- [ ] Tests added or updated (gdUnit4 / sim); `scripts/test.sh` passes
- [ ] No original game files, extracted assets or decompiled code (`scripts/hygiene.sh` passes)
- [ ] Commits use conventional format with decision trailers (see CONTRIBUTING.md)
- [ ] CHANGELOG.md updated under Unreleased, ADR added if the decision is irreversible
