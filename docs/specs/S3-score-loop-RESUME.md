# S3 score/referee bridge — resume note

Branch: `slice/s3-score-loop`
Contract: `docs/specs/S3-rules-bridge.md` from `docs/s3-rules-bridge` commit
`7fbbb25`; evidence contract: `docs/re/05-rules.md` §§2.1–2.3, 2.8.

## Implemented

- Added typed score counters, stable-team score storage, typed referee reports,
  completed conversion results, restart assignments, and the time-up whitelist.
- An injected eligible try report awards one try and requests a conversion
  restart without inventing the conversion position.
- Conversion outcomes validate the pending team and monotonic attempt ID. A
  successful result adds one conversion, and both outcomes assign the kickoff
  to the opponent. The missed-conversion team policy is separately switchable
  because RE05 identifies it as an inference.
- A time-up try still creates its conversion. A first-period conversion result
  ends the period without a kickoff. A second-period transition stays explicitly
  unresolved; the completed conversion is retained and no extra-time/full-time
  result is guessed.
- Period indices follow RE05's stored zero-based convention: 0 first half,
  1 second half, 2–4 extra time 1–3. The unresolved additional gate applies only
  to period 1. A non-ending report returns `PASSTHROUGH` with the stamped report
  retained for the S1/full referee owner; this slice does not claim to apply its
  ordinary scrum, penalty or free-kick restart.
- `is_production_available()` remains false. The bridge lists the missing S1
  committed event/transition owner, S2 grounding and completed goal-kick facts,
  and S4 completed conversion provider. It is not wired into the live runner.

## Fidelity boundary

The bridge consumes an already-eligible try report and an already-completed S4
conversion result. It does not implement grounding, offside/advantage, kick
physics, conversion setup, score animations, extra time or kickoff positioning.
Those owners/contracts are absent; no physical event is synthesized. The
second-half period-end gate is unresolved in RE05 §7.6.

## Verification and next steps

- `XDG_DATA_HOME=/tmp/openrugby-s3-score-loop-user scripts/test.sh`: 185/185
  cases across 34 suites. The focused bridge suite has 9 passing cases.
- `gdlint game tests`, `gdformat --check --line-length 100 game tests`
  (161 files), `scripts/hygiene.sh`, and `git diff --check`: pass.
- The normal Godot port-0 remote-debugger warning and 476 ObjectDB / 55
  resource teardown warnings remain; Godot exited 0.
- Focused bridge tests cover score arithmetic/snapshots, try-to-conversion,
  conversion idempotency, wrong-team rejection, inferred miss policy, the
  time-up report whitelist, ordinary knock-on/forward-pass/penalty passthrough,
  first-half time-up conversion, unresolved second-half handling, and normal
  extra-time period-end handling.
- Run `scripts/check-godot-safe.sh` immediately before each Godot test command.
- Run `scripts/test.sh` with a temporary `XDG_DATA_HOME` to avoid the sandbox's
  unwritable default user-data path, then run `gdlint`, `gdformat --check`, and
  `scripts/hygiene.sh`.
- Request independent code/fidelity review before integration. Do not merge
  this slice into the live runner until the listed S1/S2/S4 provider contracts
  exist and an integration owner can stage all effects atomically.
