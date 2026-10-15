# S3 rules bridge — resume note

Branch: `docs/s3-rules-bridge`
Scope: docs-only contract for the try → conversion result → opponent kickoff
loop and the time-up report whitelist. See `S3-rules-bridge.md`.

## State

- Authored only the proposed S3 contract; no production code, REA calls, Godot
  behavior was added. No REA call was made.
- Independent read-only RE05 review by `/root/fatigue_system` passed after
  correcting the public identity types and documenting missed-conversion
  kickoff as an inference.
- Commit `7fbbb25` (`docs(rules): specify scoring and period end bridge`) is
  pushed to `origin/docs/s3-rules-bridge`.
- Primary evidence is already documented in `docs/re/05-rules.md` §§2.1–2.3,
  2.8, 6, and 7. No new binary-derived claim was introduced.
- Independent read-only review by `/root/fatigue_system` found two contract
  fixes: use existing `StringName` team/player identities instead of `int`, and
  mark the missed-conversion kickoff team as inferred. Both are now corrected;
  reviewer recheck is pending.
- This worktree's `.omc/` directory and `.omc/HANDOFF.md` are absent. The root
  handoff was read, but this branch must not modify the root main worktree.
  Parent orchestrator should append the commit/status to root `.omc/HANDOFF.md`
  after push.
- The branch initially reports modified gdUnit4 PNG files because Git LFS
  metadata is read-only in the shared checkout. Those files were not edited or
  staged. Stage only the two new Markdown files by explicit path.
- `scripts/hygiene.sh`: pass. `gdlint .`: pass. `git diff --check`: pass.
- `gdlint game tests` and `gdformat --check --line-length 100 game tests`:
  pass (148 files unchanged). A whole-repository `gdformat --check` visits
  vendored gdUnit4 code and fails there (210 vendor files reported; one parser
  error); no GDScript changed in this slice.
- `scripts/check-godot-safe.sh`: pass immediately before each test run.
- First `scripts/test.sh` invocation used the default user data path and
  reported 12 failures in input-log (2), mod-discovery (1), and input-bindings
  (9), alongside failures to create `user://logs/`. On rerun with
  `XDG_DATA_HOME=/tmp/openrugby-s3-spec-user`, all 164 tests in 31 suites pass.
  Godot still prints a remote-debugger port-0 warning and ObjectDB/resource
  teardown warnings; process exit is 0. No test or implementation file was
  changed for this docs slice.

## Before implementation

1. Resolve the S1 typed staged-event adapter and tick owner ordering.
2. Add an S2 committed grounding fact and a completed kick-result contract, or
   mark S3 Classic scoring unavailable.
3. Define S4's typed conversion-attempt and completed-result adapter, including
   the restart setup owner.
4. Resolve the extra second-half period-end gate from RE evidence before
   enabling that transition. Keep cut-scene pause behavior and advantage
   unknowns configurable/explicit.
5. Have an independent test author derive tests from acceptance cases §5 before
   implementation. The code author must not approve the same slice.

## Verification and git

The slice changes Markdown only. `scripts/hygiene.sh`, `gdlint game tests`,
`gdformat --check --line-length 100 game tests`, and the safety-gated test run
with `XDG_DATA_HOME=/tmp/openrugby-s3-spec-user` passed; the suite reports
164/164. Whole-repository `gdformat --check` only fails in vendored gdUnit4 as
recorded above. The two-file commit is pushed. Do not stage or clean the
pre-existing LFS PNG status. Root `.omc/HANDOFF.md` remains for the parent
orchestrator to update because this slice was explicitly confined to its
isolated worktree.
