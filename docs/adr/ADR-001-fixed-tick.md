# ADR-001: Fixed 60 Hz simulation tick, simulation separate from presentation

- Status: Accepted
- Date: 2026-10-14

## Context

The match must be deterministic: replayable from a seed and an input log, testable headless, and
suitable for future multiplayer. Variable frame rates and mixing gameplay with rendering make
that impossible. The original game also ran a fixed-step simulation.

## Decision

- The simulation advances in fixed steps of 1/60 s in `_physics_process`
  (`physics/common/physics_ticks_per_second=60`).
- Presentation (animation blending, camera, HUD, interpolation) runs in `_process` and only reads
  sim state; it never mutates it.
- The sim uses a seeded `RandomNumberGenerator` owned by the match, never global RNG or wall-clock
  time. Inputs are sampled once per tick into an input log.
- Frame rate stays uncapped; rendering interpolates between ticks.

## Consequences

- Replays, headless sim tests and determinism checks across OS runners are possible.
- Sim code must avoid frame-dependent logic, per-frame allocations and engine nondeterminism
  (e.g. rely on rules code, not Jolt, for outcomes).
- The tick rate is irreversible once replays and saves exist; changing it needs a new ADR.
- Mods are part of the replay header; a replay refuses to run with a different mod set.
