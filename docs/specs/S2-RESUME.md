# S2 implementation resume

## Current contract decisions

- **Fatigue snapshot timing:** S2 consumes the owning player/match layer's immutable fatigue snapshot captured at the beginning of the 60 Hz tick, before that owner advances its fatigue time for the tick. This follows RE 09 §2.3's per-frame `fatigue += dt_match` and the S2 ordered tick contract's “capture” before movement; the owner must publish the next value only after S2 has consumed the current one. S2 never advances or stores fatigue time.
- **Initial sprint energy:** no standalone numeric Classic default is assigned. The owner must inject an initial fatigue snapshot before locomotion is usable, including energy cap and starting energy. RE 06 §2.9 clamps the pool to `[−1, E_max]`; RE 09 §2.3 supplies `E_max` as a function of Stamina and fatigue time. At a new match, the owning layer must initialize fatigue time to its observed new-player value and calculate the corresponding energy; without that injection, S2 reports the player state as unresolved and does not fabricate a value.
- **Clock boundary:** locomotion integrates at S1's 60 Hz (`dt=1/60`) using per-second rates derived from RE 06's 50 Hz actor model. The separate set-piece 50 Hz / 60 Hz motion playback question remains open (RE review C11); S2 does not convert it.
- **Ball solver:** integer accumulator adds 200 against threshold 60 only when the post-action ball is free-flight/rolling and match lifecycle is active. Held/attached/frozen paths leave ball state and accumulator unchanged. This is the explicit provisional S2 policy from S2 spec §3–4, not recovered Classic gating.
- **Mod composition:** Classic defaults and modded matches instantiate the same S2 system set. S2 data is supplied through typed Resource references; no alternate Classic/mod implementation path.

## Progress

- Read root `AGENTS.md`, PLAN §§2b/4, conventions, ADR-001/004, S2 spec, RE 06, and RE 09.
- Confirmed S1 provides ordered `SimSystem` registration, deterministic per-system snapshots, `MatchRunner` composition hooks, and typed extension point registry. S1 has no player fatigue snapshot service yet.
- Next: add typed S2 runtime values, parameter Resources and deterministic systems; wire extension points and the mandatory S2 system bundle into MatchRunner; then run format/lint/hygiene gates (never Godot without safety script).

## Unresolved implementation gaps to track

- S1 has no player/team roster match-state or fatigue owner yet. S2 inputs must remain typed/injected; no profiles or fatigue values are fabricated.
- PID gains, pass/catch candidate policy and mappings, wind policy, several tackle action bindings, place-kick meter, and contact geometry provider remain unresolved per S2 spec §8. Dependent paths must report unavailable until injected.
- Deterministic geometry input is synthetic/injected; stadium collision mesh integration is outside this slice's available S1 state.
