# S2 contact LCP resume note

## Current slice result

This slice does not implement a production contact solver. `BallContactSolver` is still an
unavailable injection point. RE 06 §2.4 confirms the contact response family, restitution formula,
Coulomb friction bound, the three row categories, deterministic contact order, and abort on
oscillation. It does not recover LCP matrix assembly, pivot ordering, convergence/oscillation
detector, iteration cap, or numeric tolerance. The rolling/twist torque form is explicitly unknown.
Choosing these values would invent behavior, so Classic contact solving remains unavailable.

`docs/specs/S2-physics.md` now states the boundary and requirements for a later solver. The new
`test_contact_lcp_contract.gd` locks condition-2 side-on/end-on restitution, interpolation, the
compiled-out `f2` randomness, and the base solver's unavailable, non-mutating behavior.

## Gates

- Focused contact contract suite: 3/3 passed.
- Full `scripts/test.sh` with fresh writable `XDG_DATA_HOME=/tmp/openrugby-contact-lcp-xdg`:
  **178/178 passed across 34 suites**. The first run using the default shared Godot user directory
  had 12 failures in input-log, mod-discovery, and input-binding suites; the isolated rerun passed,
  confirming those failures were caused by shared `user://` state across worktrees. The isolated
  run still prints the repository's known `127.0.0.1:0` remote-debug warning and ObjectDB/resource
  shutdown counts; it exits 0.
- UID snapshot before and after the isolated full run was identical.
- `gdlint game autoload tests`: passed.
- `gdformat --check --line-length 100 game autoload tests`: passed (156 files checked).
- `scripts/hygiene.sh`: passed.
- Whole-project lint/format remain to run before finalizing this branch.

## Resume plan

1. Run whole-project `gdlint game autoload tests` and
   `gdformat --check --line-length 100 game autoload tests`.
2. Keep this solver unavailable until an implementation can test, against production code, the
   normal restitution row, Coulomb bound, stable row/constraint order, deterministic successful
   solve, transactional abort on oscillation, and repeatable results. Do not synthesize a fake LCP
   only for tests.
3. Resume production LCP work only when evidence or an explicitly accepted documented solver
   policy supplies the missing pivot/convergence/oscillation details. Resolve the rolling/twist row
   separately before claiming complete Classic contact response.
