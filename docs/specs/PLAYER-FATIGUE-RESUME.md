# Player fatigue owner — resume note

The assigned `docs/re/09-physics.md` path does not exist. The applicable source is
`docs/re/09-players-teams-db.md` §2.3 and §3, which specifies per-team/per-shirt
match-time fatigue, the on-pitch frame accrual boundary, halftime recovery, energy
curve, integer energy percent, and fatigue penalties.

`PlayerFatigueModel` is a deterministic owner independent of presentation. Callers
must inject `dt_match`, on-pitch status, player attributes, initial fatigue time,
and initial sprint energy. This slice does not derive the match clock scale or
sprint-energy initialization. Initial sprint energy remains match-start data in
[-1, 100] and is not revalidated against later fatigue caps; S2 limits its live
sprint pool to the current cap as it advances. `fatigue_snapshot()` produces the
typed pre-advance `PlayerFatigueSnapshot` consumed by S2. Passing uses S2's
required `max(0, base -
fatigue_penalty)` rule; Tackling preserves RE09's raw subtraction, which can reach
−45 for a zero Tackling stat at the 9 percent floor. Replay state is versioned and ordered by
team then shirt; callers can checkpoint with `snapshot()` and restore atomically.

The model accepts only shirt numbers 1..22, matching the observed matchday squad.
Only shirts 1..15 accrue per-frame fatigue under RE09 §2.3, even if a caller marks
shirt 16..22 as on-pitch; those entries remain available for queries and halftime
recovery. The slice does not infer substitutions, bench policy, or the owner that
changes pitch presence. Halftime recovery updates all registered shirts, whether
on-pitch or not. MatchRunner has no existing fatigue-owner lifecycle or match-clock
delta injection seam, so this component is not silently wired into live composition.

Acceptance coverage: observed curve endpoints and midpoint, integer percent / skill
penalty truncation, deterministic entry ordering, on-pitch accrual with injected
delta, halftime recovery and floor, initial sprint energy pass-through, and exact
snapshot rollback with atomic malformed-snapshot rejection.

## Verification status

- Focused fatigue tests: 6/6 passing, including a zero-Tackling / full-fatigue
  case and configuration-bound snapshot restoration.
- Full suite with `XDG_DATA_HOME=/tmp/openrugby-fatigue-user`: 170/170 passed
  across 32 suites after adding boundary tests. Godot printed the existing shutdown ObjectDB/resource leak
  diagnostics after a successful exit; no fatigue test failed.
- `gdlint game tests`: pass.
- `gdformat --check --line-length 100 game tests`: pass (152 files).
- `scripts/hygiene.sh`: pass.
- `git diff --check`: pass.
