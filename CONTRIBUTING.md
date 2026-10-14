# Contributing to OpenRugby

Thanks for helping. Please read [docs/CONVENTIONS.md](docs/CONVENTIONS.md) first and follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Ground rules

- Never commit original game files, extracted assets or decompiled pseudo-code. `original/` and
  `extracted/` are gitignored; `scripts/hygiene.sh` enforces this in pre-commit and CI.
- Spec before code: implement against a spec in `docs/re/` or a slice spec with acceptance
  criteria. Behavioural specs describe behaviour; they do not paste decompiled code.
- Faithful by default, moddable by design: Classic behaviour is the baseline, and anything a
  modder might change is data (a `Resource`), not a literal.

## Setup

See the build section of the [README](README.md). Install pre-commit hooks with
`pre-commit install`.

## Workflow

1. Branch per slice or fix: `feat/<slice>-<topic>`, `fix/<topic>`.
2. Write tests from the spec's acceptance criteria (gdUnit4 in `tests/unit/`, headless match
   tests in `tests/sim/`).
3. Run `scripts/test.sh`, `gdlint`, `gdformat --check` and `scripts/hygiene.sh` locally.
4. Open a PR using the template. One PR per slice; CI must be green on all platforms.
5. Merge with a merge commit or rebase. Never squash: history carries the decision trailers.

## Commit messages

Conventional commit subject (`feat(ball): ...`, `fix(rules): ...`, `docs: ...`), optional body,
then git trailers where applicable (skip for trivial commits):

| Trailer | Meaning |
|---|---|
| `Constraint:` | active constraint that shaped the decision |
| `Rejected:` | alternative considered \| reason for rejection |
| `Directive:` | warning or instruction for future modifiers of this code |
| `Confidence:` | high \| medium \| low |
| `Scope-risk:` | narrow \| moderate \| broad |
| `Not-tested:` | edge case or scenario not covered by tests |

```
fix(rules): award penalty for offside at the ruck

Offside line was measured from the ball, not the hindmost foot.

Constraint: Must match the original's line placement (docs/re/rules.md)
Rejected: Per-frame recompute | breaks fixed-step determinism
Confidence: medium
Scope-risk: narrow
Not-tested: Overlapping rucks
```

## Slice PR process

Each slice goes: spec, implementation and tests (written independently from the spec), automated
checks, code review and fidelity review, bounded fix rounds (max three), then a gate review for
architecture and performance before merge.

## Reviewer rules

- The author never approves their own change.
- Check against `docs/CONVENTIONS.md`; reject on architecture violations (coupling, autoload
  sprawl, sim/presentation mixing, literals instead of Resources).
- Fidelity review: behaviour matches the spec with no mods enabled, and nothing a modder would
  want to change is hard-coded.
- Reach gate: no drop of the Low graphics preset below 60 fps on the benchmark, no broken aspect
  ratio, no unremappable input.
- Enabling then disabling the Modern pack must not change base-game test results.
- Reviewers cite the convention or spec line they rely on.

## Architecture decisions

Irreversible decisions get a numbered ADR in `docs/adr/` (Status, Context, Decision,
Consequences).
