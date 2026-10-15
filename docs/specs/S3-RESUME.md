# S3 rules slice resume

## Current checkpoint

- Worktree/branch: `.claude/worktrees/s3-rules-spec-inventory`, `slice/s3-rules-spec-inventory`.
- Scope: documentation only; no implementation code, Godot or gameplay tests.
- Drafts: [S3-rules-referee.md](S3-rules-referee.md) and [S3-test-inventory.md](S3-test-inventory.md).
- Evidence audited: PLAN §§2, 2b, 3, 4; CONVENTIONS; RE 05; RE 07; S1-core/S1-test-api; S2-physics; S2 public test API candidate on `slice/s2-output-contract-fix`.

## Resume plan

1. Independent reviewer checks the facts and the boundary between S3 decisions and S4 mechanics.
2. Resolve S1/S2 API mismatch for `SystemTickResult` outputs and freeze S2's law-observation
   record before an S3 implementer starts.
3. Agree restart-award and formation-result records with S4, using only the RE 05/07 evidence.
4. Resolve or explicitly defer the variable-period clock and the open extra-time/shoot-out facts.
5. Split an implementation brief from the reviewed spec, then run S3 implementation and the
   independent test author concurrently in separate worktrees as PLAN §3 requires.

## Acceptance status

- Rules and test cases are mapped to RE 05 §§2–7. Full mapping is in the inventory's source
  coverage table.
- S3 cannot honestly be called implementation-ready until resume steps 2–3 are completed. The
  draft identifies those contract gaps instead of giving S3 a private view of mutable S2 state.
- No Godot command, implementation test, or new RE pass was run in this documentation slice.
