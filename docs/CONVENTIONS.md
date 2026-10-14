# OpenRugby Conventions

Checklist distilled from the Godot 4 style guide and best-practice docs. `gdlint` and `gdformat`
enforce the mechanical items in pre-commit and CI; reviewers enforce the rest and may reject a
slice for violations. Source: `docs/PLAN.md` section 1b.

## GDScript style

- [ ] `gdformat` formatting, `gdlint` clean, tabs for indentation, 100-column lines.
- [ ] Static typing everywhere: typed vars, typed params, explicit return types. Project settings
      turn `untyped_declaration`, `unsafe_*` and `return_value_discarded`
      warnings into errors.
      `:=` inference is allowed when the type is obvious (Godot style guide); an untyped
      `var x = ...` is an error.
- [ ] Naming: `snake_case` for files, folders, functions, variables and signals; `PascalCase` for
      `class_name` and node names; `CONSTANT_CASE` for constants; leading underscore for private
      members; signals in past tense.
- [ ] Script member order (below).
- [ ] `##` doc comments on every `class_name` script and public method.
- [ ] `class_name` for every reusable type; no stringly-typed lookups.

### Script member order

1. `class_name`
2. `extends`
3. `##` doc comment
4. signals
5. enums
6. constants
7. `@export` vars
8. public vars
9. private vars (`_name`)
10. `@onready` vars
11. built-in callbacks (`_init`, `_ready`, `_process`, `_physics_process`, ...)
12. public methods
13. private methods

```gdscript
class_name TackleResolver
extends Node
## Resolves the outcome of a tackle attempt from attacker and defender attributes.

signal tackle_completed(result: TackleResult)

enum Outcome { MADE, MISSED, FENDED }

const MAX_REACH: float = 2.5

@export var params: TackleParams

var last_outcome: Outcome = Outcome.MISSED

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _hit_area: Area3D = %HitArea


func _ready() -> void:
	_rng.seed = 0


## Resolves one tackle and emits [signal tackle_completed].
func resolve(attacker: PlayerProfile, defender: PlayerProfile) -> TackleResult:
	var result: TackleResult = _compute(attacker, defender)
	tackle_completed.emit(result)
	return result


func _compute(attacker: PlayerProfile, defender: PlayerProfile) -> TackleResult:
	return TackleResult.new()
```

### Signal naming

Past tense, snake_case, describing something that already happened. Never imperative.

| Good | Bad |
|---|---|
| `try_scored` | `score_try`, `on_try` |
| `tackle_completed` | `tackle`, `tackling` |
| `possession_changed` | `change_possession` |
| `whistle_blown` | `blow_whistle` |

Handlers connected in code are named `_on_<source>_<signal>`, e.g. `_on_ball_possession_changed`.

## Scene and node architecture

- [ ] Composition over inheritance; small single-purpose scenes.
- [ ] "Call down, signal up": parents call children, children emit signals, siblings never reach
      into each other. No `get_parent()` chains, no `get_node("../..")`. Use `%UniqueName` and
      `@onready`.
- [ ] Autoloads are limited to the global event bus and settings. Everything else is injected or
      owned by a scene. No god singletons.
- [ ] Custom `Resource` classes with `@export` fields hold all data (player attributes, teams,
      kits, stadiums, rule parameters, difficulty tables). JSON is only the extraction
      interchange; a loader fills Resources.
- [ ] Tunable gameplay constants live in `@export`ed Resources, not literals.

## Simulation discipline

- [ ] Fixed-step deterministic simulation in `_physics_process` at the pinned tick rate
      (ADR-001), separated from presentation (`_process`). A match replays from a seed and an
      input log with identical results.
- [ ] No per-frame allocations in the sim loop; use `PackedArray`s and preallocated pools. Crowds
      and far players via `MultiMeshInstance3D` or server APIs.
- [ ] Jolt physics for ball and collision shapes; gameplay outcomes (tackle result, ruck win) are
      resolved by rules/sim code, not by physics.

## Input, UI, i18n, persistence

- [ ] All input through `InputMap` actions; no raw keycodes. Gamepad first.
- [ ] UI built from `Control` containers with anchors and a single committed `Theme`; no
      hard-coded pixel positions.
- [ ] Every user-facing string goes through `tr()` with keys in `localization/translations.csv`.
- [ ] Saves and settings under `user://` via `ConfigFile` or Resources with a versioned schema.
      Nothing writes to `res://` at runtime.

## Repository and process

- [ ] Conventional commits with decision trailers (see CONTRIBUTING.md).
- [ ] Semver tags; CHANGELOG updated per release. Branch per slice, PR per slice, never squash.
- [ ] Pre-commit: gdformat, gdlint, ruff for `tools/`, hygiene scan.
- [ ] CI on every PR: lint, gdUnit4 tests headless, sim tests headless, export smoke builds on
      Linux, Windows and macOS with the pinned engine version.
- [ ] One ADR per irreversible decision in `docs/adr/`.
- [ ] No original assets, binaries or decompiled code in git.

## Reimplementation, not a port

- [ ] Names describe intent in this codebase (`TackleResolver`, `AdvantageTracker`),
      never the original's (`Hbs::Rugby::...`, RTTI or symbol names from `docs/re/`).
- [ ] Structure follows Godot best practice and these conventions, not the original's
      class hierarchy, globals, update order or memory layout. Rearchitect freely.
- [ ] Only observable behaviour and numeric constants are carried over from `docs/re/`,
      and every carried constant lives in a Resource with a clear name and unit.
- [ ] Reviewers reject code that transliterates decompiler output or mirrors original structure.

