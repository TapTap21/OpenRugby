# AGENTS.md

Instructions for any AI coding agent working on OpenRugby, whatever the provider
(Claude Code, Codex, other harnesses). Tool-specific files may add detail but must not
contradict this file.

## What this project is

An open-source Godot 4.7.2 rebuild of EA Rugby 08 for Linux, Windows and macOS.
Classic Rugby 08 behaviour by default; modernisation ships as mods on a built-in loader.
The full plan, phases, agent roles and rules are in `docs/PLAN.md`. Read it first.

## Must read before working

- `docs/PLAN.md`: section 4 (rules), section 2 and 2b (roles and provider fallback).
- `docs/CONVENTIONS.md`: Godot and GDScript conventions, enforced in review.
- `.omc/research/PHASE1_BRIEF.md` (local, gitignored): reverse-engineering rules, if you do RE.
- `.omc/HANDOFF.md` (local, if present): what was running and what to do next.

## Hard rules

- Never write to the user's game install or `original/`. Never commit original game files,
  extracted assets, dumps or decompiled code (`scripts/hygiene.sh` checks this).
- Run `scripts/check-godot-safe.sh` before any Godot command or opening the editor.
  Godot follows symlinks and would otherwise write into the game install.
- Fidelity is behavioural and numeric only. Rename and rearchitect freely; never mirror the
  original's names, class hierarchy or data layout.
- Author is never the reviewer. Every change passes: `scripts/test.sh`, `gdlint`,
  `gdformat --check --line-length 100`, `scripts/hygiene.sh`, and for tools/
  `ruff check`, `ruff format --check` and `pytest` (see README).
- Conventional commits with the decision trailers described in `CONTRIBUTING.md`, plus an
  attribution trailer naming the model that wrote the change.

## Reverse engineering

- REA MCP server with `REA_GHIDRA_STARTUP_TIMEOUT_MS=1800000`. One shared target only:
  `.omc/research/unpacked/Rugby08_unpacked.exe` (SecuROM-repaired). Use REA only when
  `.omc/research/REA_READY` exists and `REA_SWITCHING` does not. Never close the session,
  never open other files with REA, never use the REA CLI on the exe.
- Specs go to `docs/re/NN-*.md` as behaviour, constants, mod hooks and acceptance tests.

## State lives on disk

Write progress continuously to your files (specs, `.omc/research/functions/*.tsv`,
`.omc/research/<subsystem>/` notes with a resume plan, `docs/specs/*-RESUME.md` for slices)
and commit slice work on its branch at each consistent point, so any agent on any provider
can resume after an interruption.
