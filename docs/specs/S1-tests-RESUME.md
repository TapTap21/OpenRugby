# S1/S9 test suite resume plan (WIP, s1-tests)

Temporary handover note. Delete before the slice is merged.

## Status (last full run, all under flock)

| Suite | Files | Result |
|---|---|---|
| tests/unit/match | 9 | pass (all test cases, 0 failures) |
| tests/unit/mods | 9 | pass (after fx-beta fixture fix for M-22) |
| tests/unit/data | 3 | pass (after `int(prop["usage"])` fix) |
| tests/unit/platform | 5 | pass (after `connect()` assignment fix) |
| tests/sim | 1 | pass |

Parse errors: none remaining at the last run. Lint and format were clean (`gdlint tests`,
`gdformat --check --line-length 100 tests`).

## Known observations

- Implementation log line: `ERROR: cannot emit mods_loaded: Unavailable` from
  `game/mods/mod_applier.gd:37` during apply. Tests pass, but it looks like a push_error to check.
- M-29 OBSERVER leg is tested against ExtensionPoints directly (no base OBSERVER point exists).
  Spec note needed.
- C-17 cannot observe the clock in half_time; the clock_runs flag is covered in the C-10 flow test.

## Next steps

1. Re-run every suite (`scripts/test.sh res://tests/unit/<dir>` and `res://tests/sim`) under
   `flock /tmp/openrugby-s1-godot.lock` after any implementation change.
2. Check the mods_loaded `Unavailable` log line against the implementation.
3. Re-run `gdlint tests` and `gdformat --check --line-length 100 tests`.
4. Delete this file before the slice merges.
