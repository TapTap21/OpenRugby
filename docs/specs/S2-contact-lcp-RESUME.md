# S2 contact LCP resume note

## Current slice result

This slice does not implement a production contact solver. `BallContactSolver` is still an
unavailable injection point. The evidence establishes partial solver mechanics: 0x4ba850 zeros an
N×N matrix and constructs/scales six-component row data and symmetric pair products; 0x4b6920
performs pivot/state processing and has oscillation/abort paths; 0x4bacf0 applies solved rows.
Helpers 0x4baa80 and 0x4babd0 are also in the recovered path. Evidence IDs: 0x4b6920
`ev_e4d8b68a`, 0x4ba850 `ev_a00c3f28`, 0x4baa80 `ev_27be19a8`, 0x4babd0 `ev_1e9bd7f5`,
0x4bacf0 `ev_6eac0abb`, basis helper 0x4b3ff0 `ev_794be3ab`.

RE 06 §2.4 also supports the restitution formula, Coulomb friction bound, normal/friction/rolling
row categories, contact geometry sort key, and abort-on-oscillation behavior. It does not resolve
exact Jacobians or RHS, units of the six components, pivot choices/tie-breaks, outer tolerance,
iteration cap, oscillation detector details, a numeric reference case, or rolling angular response.
Contact ordering does not establish LCP row ordering. Deterministic output is an OpenRugby rebuild
requirement, not a recovered claim about Classic. Without the unknown mechanics and a known numeric
reference, implementing a supposedly exact solver would overstate the evidence.

`docs/specs/S2-physics.md` now states the boundary and requirements for a later solver. The new
`test_contact_lcp_contract.gd` locks condition-2 side-on/end-on restitution, interpolation, that
changing the stored `f2` value does not alter the restitution formula, and the base solver's
unavailable, non-mutating behavior. This test does not exercise random-stream consumption.

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

## Resume plan

1. Keep this solver unavailable until an implementation can test, against production code, the
   normal restitution row, Coulomb bound, contact-to-row mapping/order, deterministic successful
   solve as a rebuild property, transactional abort on oscillation, and repeatable results. Do not
   synthesize a fake LCP only for tests.
2. Resume production LCP work only when evidence or an explicitly accepted documented solver
   policy supplies a numeric reference, Jacobian/RHS interpretation, component units, and pivot,
   convergence, and oscillation behavior. Resolve rolling angular response separately before
   claiming complete Classic contact response.
