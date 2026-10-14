# OpenRugby — Rebuild Plan

Goal: a faithful, open-source, cross-platform (Linux / Windows / macOS) rebuild of
EA Rugby 08 in Godot 4.7, produced by a multi-agent pipeline. Gameplay first,
then new features. Naming and trademark cleanup happens later ("anon" pass).

Orchestrator for the whole programme: this session (Claude Fable 5.1). It never
writes gameplay code itself beyond scaffolding; it briefs, fans out, gates and
merges. Every other role below is a subagent.

---

## 0. Current state and hard prerequisites

| Item | Status | Needed for |
|---|---|---|
| `Rugby08.exe` (NoCD, 6.3 MB, 2007-07-26) | present in `~/Downloads/Rugby-08_NoCD_Win_EN.zip` | game-logic RE |
| Full game install (3.2 GB) | present at `/home/wernich/Code/games/rugby08/Rugby-08_Win_EN_Full-Rip/` (exe identical to NoCD) | data-format RE, asset pipeline, visual fidelity |
| Godot 4.7.2 (`/usr/bin/godot`, headless works) | installed; export templates to confirm | everything after Phase 1 |
| gdtoolkit (`gdlint`, `gdformat`) | not installed | lint gate |
| Python 3.14 | present | asset extraction tools |
| REA MCP server (170 tools) | connected | Phase 1 |

**Install inventory (2026-10-14):**

| File | Size | Container | Notes |
|---|---|---|---|
| `Data/data.gob` | 475 MB | `BIGF` | main asset archive: models, textures, DB, stadiums, kits. `Data/motion/data.gob` is a byte-identical copy |
| `Data/motion/script.big` | 133 MB | `BIGF` | animation / motion scripts |
| `Data/motion/moai.viv` | 3.3 MB | `BIGF` | small motion archive |
| `Audio/*.big` (8 files) | ~420 MB | `BIGF` | commentary (`dat_eng`, `hdr_eng`, `ref_eng`), chants, anthems, music, ambient (`aems`) |
| `Audio/nzh.dat` | 1.9 MB | `SCHl` | EA stream audio (haka) |
| `Audio/pbp.evt` | 78 KB | unknown | play-by-play commentary event table |
| `Data/*.vp6` (15) | — | VP6 | intro/licence videos; not needed |
| `Data/controltypes.csv` | 6 KB | CSV | gamepad button-map table, directly reusable |

Every archive uses EA's standard `BIGF` container (big-endian index, documented
publicly and supported by existing tools), and audio is EA's `SCHl`/`SCxl`
stream family. This means the data-format RE in Phase 1 can focus on the
*member* formats inside the archives (textures, models, DB, animation), not
the containers. The original directory is read-only to all agents; `tools/`
reads from it and writes to `extracted/`.

Assumptions until overridden:
- Licence: **GPL-3.0** (same family as OpenRCT2 / OpenMW; appropriate for a
  reimplementation derived from binary analysis).
- Language: **typed GDScript**, with GDExtension (C++) only if profiling
  demands it. No C# (export friction on macOS, extra runtime).
- Original binary and original assets are **never committed**. Decompiled
  pseudo-code is never committed. The repo holds behavioural specs, clean
  reimplementation, and extraction tools. Users supply their own copy of the
  game to the extractor (OpenMW model).

---

## 1. Repository layout (target)

Follows the official Godot "Project organization" guidance: organise by
feature, co-locate a scene with its script and feature-specific assets, keep
shared assets in one place, keep editor-generated files out of git.

```
openrugby/
  project.godot
  export_presets.cfg        # committed; signing secrets injected by CI, never stored here
  .godot-version            # pinned engine version read by CI and tooling
  LICENSE                   # GPL-3.0
  README.md  CONTRIBUTING.md  CODE_OF_CONDUCT.md  CHANGELOG.md
  .editorconfig  .gitattributes  .gitignore  .pre-commit-config.yaml  gdlintrc
  .github/
    workflows/              # lint, unit tests, headless sim tests, export matrix
    ISSUE_TEMPLATE/  PULL_REQUEST_TEMPLATE.md
  addons/                   # vendored, committed: gdUnit4 only (no editor-only clutter)
  autoload/                 # the few true singletons: event_bus.gd, game_settings.gd
  game/                     # feature folders, scene + script + local assets together
    main/                   # main.tscn, scene router
    match/                  # match.tscn, match_controller.gd, pitch/
    ball/                   # ball.tscn, ball.gd, ball_physics.gd
    player/                 # player.tscn, locomotion.gd, animation_controller.gd
    rules/                  # referee.gd, infringement_*.gd (logic only, no scenes)
    mods/                   # loader: manifest.gd, override_layers.gd, hooks.gd, mod_manager.tscn
    setpiece/               # scrum/, lineout/, ruck/, maul/, kick/
    ai/                     # team_brain.gd, behaviours/
    camera/                 # match_camera.tscn
    hud/                    # hud.tscn, scoreboard.tscn
    ui/                     # menus/, team_select/, competition/, settings/
    competition/            # fixtures, tables, bonus points (logic + resources)
    data/                   # custom Resource classes: player_profile.gd, team.gd, kit.gd, stadium.gd
    save/                   # ConfigFile/Resource-based save and settings persistence
    platform/               # input map helpers, per-OS paths, gamepad quirks
  assets/                   # shared, freely-licensed: fonts/, themes/, placeholder/, sfx/
  mods/                     # built-in first-party mods, each with mod.json (Modern pack), off by default
  localization/             # translations.csv -> generated .translation files
  tools/                    # Python extractors (stdlib + pytest), run outside Godot
  tests/
    unit/                   # gdUnit4, mirrors game/ layout
    sim/                    # headless scripted matches, determinism and replay checks
    fixtures/               # tiny hand-written JSON/.tres for tests
  docs/
    PLAN.md  CONVENTIONS.md
    modding/                # mod SDK: manifest schema, extension points, template mod
    re/                     # behavioural specs per subsystem (no decompiled code)
    re/ledger.md            # reconstruction obligation ledger (REA-generated)
    adr/                    # architecture decision records, numbered
  extracted/                # gitignored: output of tools/ (glTF, PNG, OGG, JSON, .tres)
  original/                 # gitignored: user-supplied game files
```

What is committed and what is not, per the Godot version-control docs:
`.import` sidecar files and `project.godot` are committed; `.godot/` is not.
Binary assets go through Git LFS via `.gitattributes`. If LFS storage or bandwidth outgrows the Git host's quota, move the LFS backend to Cloudflare R2 through an LFS server/proxy; the `.gitattributes` rules stay the same. Android keystores,
macOS notarization credentials and Windows signing certs never enter the repo.

---

## 1b. Conventions enforced from commit one (`docs/CONVENTIONS.md`)

These are the Godot 4 official style guide and best-practice docs distilled
into a checklist. gdlint/gdformat enforce the mechanical ones in pre-commit
and CI; the code reviewer and gate reviewer enforce the rest and may reject a
slice for violations.

**GDScript style**
- `gdformat` formatting, `gdlint` clean, tabs for indentation, 100-column lines.
- Static typing everywhere: typed vars, typed params, explicit return types.
  Project settings turn `untyped_declaration`, `unsafe_*` and `return_value_discarded`
  warnings into errors.
- Naming: `snake_case` files, folders, functions, variables and signals;
  `PascalCase` for `class_name` and node names; `CONSTANT_CASE` constants;
  leading underscore for private members; signals named in past tense
  (`try_scored`, `tackle_completed`).
- Script order: `class_name`, `extends`, doc comment, signals, enums, consts,
  `@export` vars, public vars, private vars, `@onready` vars, built-in
  callbacks, public methods, private methods.
- `##` doc comments on every `class_name` script and public method.
- `class_name` for every reusable type; no stringly-typed lookups.

**Scene and node architecture**
- Composition over inheritance; small single-purpose scenes.
- "Call down, signal up": parents call children directly, children emit
  signals, siblings never reach into each other. No `get_parent()` chains,
  no `get_node("../..")`. Use `%UniqueName` and `@onready`.
- Autoloads are limited to a global event bus and settings. Everything else
  is injected or owned by a scene. No god singletons.
- Custom `Resource` classes with `@export` fields hold all data (player
  attributes, teams, kits, stadiums, rule parameters, difficulty tables).
  JSON is only the extraction interchange; a loader fills Resources.
- Tunable gameplay constants live in `@export`ed Resources, not literals.

**Simulation discipline**
- Fixed-step deterministic simulation in `_physics_process` with a pinned
  tick rate (ADR-001), separated from presentation (`_process`). The match
  must replay from a seed and an input log with identical results. This is
  what makes headless tests, replays and later multiplayer possible.
- No per-frame allocations in the sim loop; `PackedArray`s and preallocated
  pools. Crowds and far players via `MultiMeshInstance3D` / server APIs.
- Jolt physics (already set) for ball and collision shapes; gameplay outcomes
  (tackle result, ruck win) resolved by the rules/sim code, not by physics.

**Input, UI, i18n, persistence**
- All input through `InputMap` actions; no raw keycodes. Gamepad first.
- UI built from `Control` containers with anchors and a single committed
  `Theme` resource; no hard-coded pixel positions.
- Every user-facing string goes through `tr()` with keys in
  `localization/translations.csv` from day one.
- Saves and settings under `user://` via `ConfigFile` or Resources with a
  versioned schema. Nothing writes to `res://` at runtime.

**Repository and process**
- Conventional commits with the decision trailers from the commit protocol.
- Semver tags; CHANGELOG kept per release. Branch per slice, PR per slice,
  squash never (history carries the trailers).
- Pre-commit: gdformat, gdlint, ruff for `tools/`, hygiene scan.
- CI on every PR: lint, gdUnit4 unit tests headless, sim tests headless,
  then an export smoke build on Linux, Windows and macOS runners using the
  pinned engine version. Release workflow on tag produces artifacts for all
  three platforms.
- One ADR per irreversible decision, numbered, in `docs/adr/`.
- `.editorconfig` (already present), `.gitattributes` with `text=auto eol=lf`
  (already present) plus LFS rules, `.gitignore` per the Godot docs
  (already partially present).

---

## 1c. Presentation and hardware targets

Fidelity to the original is about gameplay. Presentation is modern, clean and
broad-reach. These are gate criteria, not aspirations.

**Display**
- Native support for 16:9, 16:10, 21:9, 32:9 and 4:3. Viewport stretch mode
  `canvas_items` with aspect `expand` (already set) so wide screens see more
  pitch, never black bars or stretched pixels. HUD anchored to safe margins.
- Resolution independent UI with a UI-scale setting. Windowed, borderless
  and exclusive fullscreen. High-DPI aware on macOS and Windows.
- Frame rate uncapped with VSync option; sim stays fixed-step regardless.

**Art direction**
- Stylised, clean and readable: flat-ish lighting, simple materials, strong
  silhouettes, bold kit colours, legible numbers at camera distance. No
  photorealism, no PBR-heavy materials, no expensive post-processing.
- Smoothness over detail: animation blending, camera easing, consistent
  frame pacing matter more than polygon count.
- Original 2007 assets, once extracted, are low-poly anyway and serve as
  placeholders. The "anon" pass later replaces kits, likenesses and names
  with original stylised equivalents.

**Minimum spec and renderer**
- Target: 60 fps at 1080p on integrated graphics (Intel UHD 620 class),
  Steam Deck, and 2015-era laptops. Must run on Linux without Vulkan.
- Renderer: **Compatibility (OpenGL 3.3 / ES 3.0)** as the project default,
  recorded in ADR-002. The stylised art direction needs nothing Forward+
  offers, and Compatibility runs on far more hardware, including old Intel
  Macs and VMs. Switching to Forward+ later is a settings change, not a
  rewrite, as long as materials stay simple.
- Performance budget enforced by a headless benchmark scene in `tests/sim/`
  (30 players, crowd, full pitch) with frame-time assertions in CI.
- Graphics presets: Low / Medium / High that only change shadow quality,
  crowd density, MSAA and draw distance. Low must hit the target above.

**Accessibility (everyone should be able to play)**
- Fully remappable keyboard and gamepad, with keyboard-only play viable.
- Colour-blind safe kit clash detection and alternative kit selection.
- UI text scale, high-contrast HUD option, subtitles for commentary lines.
- Difficulty and match-length options exposed from the first playable build.
- Small download: no bundled original assets, compressed textures, OGG audio.

---

## 1d. Base game and mod loader

The default experience is the standard Rugby 08: original rules, rosters,
competitions, pacing and feel as recovered in Phase 1. Everything that
modernises it ships as mods on a built-in loader, so the faithful game and
the modern game are the same executable with different mods enabled. The
same loader serves community mods later. Recorded in ADR-003.

**Design rules**
- The base game never hard-codes what a mod might want to change. Rules
  parameters, competition formats, rosters, kits, stadiums, difficulty
  curves, camera presets, HUD layouts and commentary tables are all data
  (custom `Resource`s) that the loader can override. This is why section 1b
  insists on Resources over literals.
- Base game data is itself "mod zero": the loader applies the base pack
  first, then enabled mods in load order. No special cases for base content.
- Deterministic sim must stay deterministic with mods enabled; a mod is part
  of the replay header, and a replay refuses to run with a different mod set.

**Loader architecture (`game/mods/`)**
- `mod.json` manifest per mod: id, name, version, author, description,
  `game_version` compatibility, dependencies, load priority, and a list of
  capabilities it uses (`data`, `assets`, `rules`, `scripts`, `ui`).
- Three override layers, applied in order:
  1. **Data overrides**: Resource patches by path and field (merge, not
     replace), e.g. change one law parameter or one player's stats.
  2. **Asset overrides**: a mod's `res://`-relative tree shadows base assets
     (kits, models, audio, translations) by path.
  3. **Script hooks**: GDScript entry point that subscribes to the event bus
     and registered extension points (rule hooks, AI behaviour registration,
     menu injection). Hooks are the only way a mod runs code; they cannot
     reach into scene internals.
- Built-in mods live in `mods/` in the repo and ship inside the build.
  External mods are Godot `.pck` files loaded from `user://mods/` via
  `ProjectSettings.load_resource_pack`, same manifest, same layers.
- In-game mod manager UI: enable/disable, reorder, show conflicts, show
  which mod last touched a given field. Profiles: "Classic" (no mods) and
  "Modern" (first-party pack) as one-click presets, Classic by default.
- Script-capable mods run arbitrary GDScript. The loader marks them clearly
  and the UI warns on enabling one from `user://`; data/asset-only mods are
  flagged safe. Document this honestly rather than pretending to sandbox.
- Mod SDK docs in `docs/modding/` with a template mod and a validator in
  `tools/modcheck.py` run in CI against every built-in mod.

**First-party "Modern" pack (built-in, off by default)**
Split into small independent mods so players pick what they want:
- `modern-laws`: current World Rugby laws as parameter deltas (50:22,
  goal-line drop-out, 20-minute red card, TMO/bunker flow, etc.).
- `modern-competitions`: current formats and bonus-point rules.
- `modern-presentation`: widescreen HUD layout, broadcast camera, replay
  wipes, scoreboard styles.
- `modern-qol`: quick restarts, skip animations, match-length presets,
  auto-save, controller glyphs.
- `modern-ai`: tuned defensive line, kicking game and tempo (keeps the base
  decision engine, changes weights).
- Rosters and likenesses are explicitly *not* part of the first-party pack;
  that is community territory and the later "anon" pass governs the base.

**Features policy after the base game ships**
New features and improvements are built as mods first, using only the
public extension points. If an extension point is missing, the base gains
the extension point, not the feature. A mod graduates into the first-party
pack once it has specs, tests and a fidelity check; it is only promoted
into the base game if it is a pure bug fix or a cross-cutting platform
capability (input, rendering, save format). This keeps "Classic" faithful
forever while the modern game keeps improving.

**Impact on the pipeline**
- S1 gains the loader core (manifest parsing, override layers, load order)
  because every later slice must be built against it.
- New slice S11 builds the mod manager UI, `.pck` loading, validator and the
  first-party Modern pack. Each Modern mod has its own spec, tests and
  fidelity check that the base game is unchanged with the mod disabled.
- Fidelity reviewers verify two things per slice: faithful behaviour with no
  mods, and that nothing a modder would want to change is hard-coded.

---

## 2. Agent roster, models and effort

Principle: Haiku 5.5 is the default worker. Sonnet 5.5 where the task needs
judgement across several files or a state machine. Opus 5.5 only for the
rules/physics/AI core, architecture, and gate reviews. Author and reviewer are
never the same agent, and a reviewer is never a smaller model than the author.

| Role | Model | Effort | Used for |
|---|---|---|---|
| RE lead (per subsystem) | Opus 5.5 | high; **xhigh** for rules engine and ball/tackle physics | Driving REA `trace_feature`, `analyze_function`, `batch_decompile`, writing the behavioural spec |
| RE sweep worker | Sonnet 5.5 | medium | Breadth passes: menus, game modes, input, save format, audio hooks |
| RE inventory worker | Haiku 5.5 | low | `list_strings`, `list_segments`, imports, xref tables, string-to-feature maps |
| RE verifier | Sonnet 5.5 | medium | `verify_reconstruction`, `evaluate_reconstruction_coverage`, ledger reconciliation |
| Architect | Opus 5.5 | high | One-shot Godot architecture + data model + ADRs after Phase 1 |
| Spec writer | Sonnet 5.5 | medium | Turn RE findings into implementable per-slice specs with acceptance tests |
| Implementer (routine) | Haiku 5.5 | medium | Well-specified GDScript: data loaders, UI, HUD, input, save/load, tools/ |
| Implementer (sim) | Sonnet 5.5 | medium | Locomotion, passing/catching, set-piece state machines, camera |
| Implementer (core) | Opus 5.5 | high | Rules engine, advantage logic, AI decision core, tackle resolution |
| Test engineer | Haiku 5.5 | medium | gdUnit4 unit tests from spec acceptance criteria |
| Sim test engineer | Sonnet 5.5 | medium | Headless scripted-match integration tests, determinism/replay tests |
| Code reviewer | Sonnet 5.5 | medium | Correctness review of every slice PR |
| Fidelity reviewer | Sonnet 5.5 | medium | Diff implementation against `docs/re/<subsystem>.md`; flags deviations |
| Gate reviewer | Opus 5.5 | high | End-of-slice architecture/performance review; may reject the slice |
| Verifier | Haiku 5.5 | low | Runs lint, tests, headless export; reports raw output only |
| Asset-pipeline engineer | Sonnet 5.5 | medium | Python extractors, format edge cases |
| CI / packaging engineer | Sonnet 5.5 | medium | GitHub Actions matrix, export presets, macOS bundle, Linux AppImage/tar, Windows zip |
| Docs writer | Haiku 5.5 | low | README, CONTRIBUTING, per-subsystem docs |
| Hygiene auditor | Haiku 5.5 | low | Pre-merge scan: no original assets, no decompiled code, no trademark strings in src (later) |

### Recommendation for the REA step (user asked specifically)

Run the REA campaign with **Opus 5.5 at high effort** as the per-subsystem RE
lead, **xhigh** for the two subsystems where numeric fidelity matters most
(rules engine; ball flight / kick / tackle physics). Fan each lead out with
Sonnet 5.5 medium sweepers for breadth and Haiku 5.5 low for inventories.
The orchestrator does the first 30-minute orientation pass itself
(`open_binary`, `binary_overview`, `list_segments`, `list_strings`) so every
RE lead gets a concrete brief (compiler, RTTI presence, string clusters,
candidate function ranges) instead of rediscovering it.

Why not Sonnet for the leads: a 2007 MSVC x86 C++ binary with no symbols, EA's
shared sports-engine codebase, and deeply nested state machines is exactly the
work where a weaker model confidently returns a plausible but wrong spec, and
every downstream slice inherits that error.

---

## 2b. Provider fallback: GPT luna-high when Claude credits run out

The programme must keep moving if Claude credits are exhausted. The fallback is
**GPT luna-high** (as named by the project owner; accessed through an agent
harness that supports it, e.g. Codex CLI or a T3 Code provider). The process is
provider-neutral by design: all state lives in the repo and `.omc/`, never only
in a chat transcript.

**Trigger.** Switch when a Claude session reports credit or quota exhaustion, or
when the owner says so. Switch back when credits return; work continues from disk.

**Role mapping.** One model replaces the Claude tiers, so effort carries the tiering:

| Claude role | Fallback |
|---|---|
| Haiku 5.5 low/medium (inventory, tests from spec, verifier, docs) | luna at its lowest effort that passes the gate |
| Sonnet 5.5 medium (implementer, reviewer, asset tools) | luna-high |
| Opus 5.5 high/xhigh (RE leads, rules/physics/AI core, gate review) | luna-high, plus a mandatory second luna-high review pass |

**Hand-off protocol (what makes a switch lossless).**
- Every agent writes progress to its files continuously: specs in `docs/re/`,
  function indices in `.omc/research/functions/*.tsv`, notes and resume plans in
  `.omc/research/<subsystem>/`, slice resume notes in `docs/specs/*-RESUME.md`.
- Slice work is committed to its branch at each consistent point (WIP commits are fine).
- `AGENTS.md` at the repo root is the single entry point for any agent tool and
  points at this plan, `docs/CONVENTIONS.md`, `.omc/research/PHASE1_BRIEF.md` and the
  safety scripts. Tool-specific files (`CLAUDE.md`, etc.) may add to it, never contradict it.
- Before switching, the orchestrator writes `.omc/HANDOFF.md`: running work, branches,
  pending reviews and merges, open questions, and the next three actions.

**Tooling parity the fallback harness needs.**
- The REA MCP server, configured with `REA_GHIDRA_STARTUP_TIMEOUT_MS=1800000`, plus the same
  single-shared-target rules (one target, readiness markers, never close the session).
- Godot 4.7.2, gdtoolkit, the tools venv, ffmpeg and vgmstream (as already installed).
- The same safety rules: `scripts/check-godot-safe.sh` before any Godot run, never write
  to the game install, never commit originals or decompiled code.

**Quality rules do not relax.** Author is never the reviewer; reviewer effort is never
below author effort; behavioural fidelity only (section 4 rule 0); every merge passes
the same gates. Commits made on the fallback carry an attribution trailer naming the
model that wrote them, so history shows which provider produced what.

**Cost tracking.** `tools/ops/token_ledger.py` reads Claude transcripts only. Fallback
usage is recorded from the provider's own usage report into `.omc/ledger/fallback.md`
(date, phase, role, tokens, cost) and summed with the Claude ledger in milestone reports.

## 3. Phases

### Phase 0 — Environment and scaffolding (orchestrator + 3 agents, ~1 hour)

1. Godot 4.7.2 is installed. Confirm export templates for 4.7.2 are present,
   install gdtoolkit via `uv`.  *(Haiku, low — verifier role)*
2. Repo scaffold exactly as section 1, `docs/CONVENTIONS.md` as section 1b,
   `LICENSE` (GPL-3.0), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, gdUnit4
   vendored in `addons/`, `.pre-commit-config.yaml`, `gdlintrc`,
   `.godot-version`, strict GDScript warning settings and the Compatibility renderer in
   `project.godot`, ADR-001 (tick rate), ADR-002 (renderer) and ADR-003 (mod loader) drafted,
   `export_presets.cfg` for the three platforms, GitHub Actions for lint,
   tests and the export matrix.
   *(Sonnet, medium — CI engineer; Haiku, low — docs writer)*
   Then an Opus high review of the scaffold against the Godot docs before
   any gameplay code is written.
3. Symlink `original/` → `/home/wernich/Code/games/rugby08/Rugby-08_Win_EN_Full-Rip`
   (gitignored). Agents treat it as read-only.

Gate: gdUnit4 runs headless with an empty suite and exits 0; gdlint clean;
export smoke build succeeds on all three OS runners in CI.

### Phase 1 — Reverse engineering campaign (REA)

**Mandatory for every agent in this phase:** invoke the installed
`reverse-engineer-anything` skill (via the Skill tool) before touching the
binary, and follow its routing: `open_binary` on `original/Rugby08.exe`,
then the focused REA MCP tools (`mcp__rea__*`). The skill is already
installed and the REA server is connected; do not run setup, readiness or
provider diagnostics first. Keep complete inline Evidence in every finding,
record unresolved items with `record_unknown`, and export each subsystem's
evidence bundle with `export_evidence_bundle` to `.omc/research/` (gitignored).
Every subagent brief in this phase must state this explicitly.

Deliverable per subsystem: `docs/re/<subsystem>.md` containing behaviour,
constants, state diagrams, data layouts and open questions, plus ledger
entries. No decompiled code in the repo; evidence bundles go to
`.omc/research/` (gitignored).

1a-0. **Unpack first.** The shipped exe is wrapped in the ViTALiTY
    release-group packer (sections `.ROT`/`.IN`/`.HEAVEN`, stub entry in
    `.HEAVEN`, real code decompressed into `.ROT` at runtime). Ghidra sees
    11 functions and 37 strings in the packed file. An Opus agent dumps the
    unpacked image from a Wine process (`tools/re/dump_wine_process.py`),
    rebuilds the PE with resolved imports into `.omc/research/unpacked/`
    (gitignored) and verifies it with REA. All later RE runs against the
    unpacked image. Fallback if Wine fails: static reversal of the stub.

1a. **Orientation** (orchestrator, direct, REA skill loaded): open binary, overview, segments,
    imports, strings dump, RTTI/class-name harvest, function count. Produce
    the brief for all leads.

1b. **Parallel subsystem leads** (each Opus high unless noted, each with
    1 Sonnet sweeper + 1 Haiku inventory worker):

| Subsystem | Lead effort | Key REA tools |
|---|---|---|
| Rules engine (scoring, knock-on, forward pass, offside, advantage, penalties, cards, restarts) | xhigh | `trace_feature`, `analyze_function`, `trace_native_values` |
| Ball & contact physics (kick power/angle curves, bounce, tackle resolution, fend, sidestep) | xhigh | `analyze_function`, `trace_native_values`, `compare_functions` |
| Set pieces (scrum, lineout, ruck, maul, conversions, penalty/drop kicks, kick-off) | high | `trace_feature`, `build_call_path` |
| AI (defensive line, support running, kicking decisions, difficulty scaling) | high | `get_call_graph`, `trace_feature` |
| Player model & attributes (stat schema, fatigue, injuries, form) | high | `inspect_native_data_type`, `list_names` |
| Game modes & competition logic (World League, tournaments, fixtures, tables, bonus points) | medium (Sonnet) | `trace_feature`, `search_strings` |
| Data formats (archive container, DB/roster, textures, models, animations, audio) | high | `inspect_binary_layout`, `inspect_signature`, `analyze_function` |
| Input, camera, HUD, menu flow, settings, save format | medium (Sonnet) | `search_strings`, `find_xrefs_to_name` |

1c. **Ledger and verification**: `build_reconstruction_obligation_ledger`,
    then an RE verifier (Sonnet) runs `evaluate_reconstruction_coverage` and
    reconciles each lead's spec against the ledger. Unresolved items become
    `record_unknown` entries and open issues.

Gate: every subsystem spec reviewed by a second Opus agent (not its author)
for internal consistency; ledger coverage reported.

Estimated agents: 8 leads + 8 sweepers + 8 inventory + 8 reviewers + 1 verifier
= ~33 agent runs.

### Phase 2 — Asset pipeline (requires full install)

Python tools in `tools/`, each with a Haiku-written pytest suite against
sample files, converting to Godot-native inputs:

- `BIGF` unpacker (covers `.gob`, `.big`, `.viv`) → raw members with a manifest;
  first tool to build, since every other tool depends on it and the format is known
- texture decoder (FSH family) → PNG
- model + skeleton + animation decoder → glTF 2.0
- audio decoder (EA ADPCM / ASF / SBR) → OGG/WAV
- database/roster decoder → JSON (teams, players, kits, stadiums, competitions)

Agents: 5 Sonnet implementers, 5 Haiku testers, 5 Sonnet reviewers, 1 Haiku
verifier. Runs in parallel with Phase 3 slices S1–S3, which use placeholder
assets and hand-written JSON.

Gate: a full extraction run on the user's install completes with zero
unhandled files; `extracted/` loads in Godot without import errors.

### Phase 3 — Implementation in vertical slices

Each slice runs the same pipeline:

```
spec writer (Sonnet) → implementer (per table) ∥ test engineer (Haiku, from spec)
  → verifier (Haiku: lint, tests, headless run)
  → code reviewer (Sonnet) ∥ fidelity reviewer (Sonnet)
  → fix loop (implementer, max 3 rounds; escalate to Opus on round 3)
  → gate reviewer (Opus, high) → merge
```

Slices run in isolated git worktrees. Independent slices run concurrently
(up to 3 at once to keep merge conflicts manageable).

| # | Slice | Implementer | Depends on |
|---|---|---|---|
| S1 | Core: match state machine, clock/halves, pitch geometry, event bus, deterministic tick, team/player data model from JSON, **mod loader core** (manifests, override layers, load order) | Sonnet (core), Opus (loader design) | Phase 1 specs |
| S2 | Ball physics + player locomotion + pass/catch/kick primitives | Sonnet (physics), Opus (tackle resolution) | S1 |
| S3 | Rules engine + referee + restarts + scoring | Opus | S1, S2 |
| S4 | Set pieces | Sonnet | S2, S3 |
| S5 | AI: positioning, defence, attack patterns, kicking decisions, difficulty | Opus (core), Sonnet (behaviours) | S2–S4 |
| S6 | Presentation: camera system, animation controllers, HUD, replay, aspect-ratio and UI-scale handling, graphics presets | Sonnet | S2 |
| S7 | Asset integration: models, kits, stadiums, crowd audio, commentary hooks | Haiku | Phase 2, S6 |
| S8 | Front end: menus, team select, game modes, competitions, settings, save/load | Haiku (UI), Sonnet (competition logic) | S3, Phase 1 modes spec |
| S9 | Input: keyboard, gamepad, remapping, per-OS quirks | Haiku | S1 |
| S10 | Packaging: export presets, CI release matrix, macOS bundle, Linux AppImage, Windows zip, first-run extractor UI | Sonnet | all |
| S11 | Mod manager UI, `.pck` mod loading, `tools/modcheck.py`, modding docs, first-party Modern pack (laws, competitions, presentation, QoL, AI) | Haiku (UI, docs), Sonnet (loader, pack), Opus (laws deltas review) | S3, S5, S6, S8 |

Per slice: 1 spec writer, 1–2 implementers, 1 test engineer, 1 verifier,
2 reviewers, 1 gate reviewer, up to 3 fix rounds ≈ 8–12 agent runs.
Eleven slices ≈ 110 agent runs. With Phase 1 and 2, the programme is roughly
150–170 agent runs, the large majority Haiku/Sonnet.

Playable milestone: after S5 a full 80-minute match, human vs AI, with
placeholder capsules and a flat pitch. Visual milestone: after S7.

### Phase 4 — Hardening and release

- Determinism and replay tests across all three OS runners (same inputs,
  same match log). *(Sonnet sim tester)*
- Performance pass: profile at 30 players + crowd; GDExtension only if a
  hotspot proves it. *(Opus gate reviewer decides)*
- Hygiene audit before first public tag. *(Haiku)*
- Trademark / naming "anon" pass as a dedicated later slice.

---

## 4. Rules the pipeline enforces

0. **Fidelity is behavioural, never structural.** The reimplementation must play
   like Rugby 08 (rules, timings, constants, outcomes), but its code owes the
   original nothing: no mirroring of HB Studios class names, call graphs, data
   layouts, globals or update order. Rename, split, merge and rearchitect freely
   whenever it gives clearer, idiomatic, testable Godot code. RE specs describe
   *what happens and with which numbers*; the architect decides *how* it is built.
   If a spec reads like a port of the original code, rewrite the design, not the code.

1. **Spec before code.** No implementer starts without a `docs/re/` or slice
   spec with acceptance criteria.
2. **Tests from spec, not from code.** Test engineer reads the spec, never the
   implementation, and runs in parallel with the implementer.
3. **Author ≠ reviewer, reviewer ≥ author's model.**
4. **Verifier reports raw output.** It does not interpret, fix or re-run.
5. **Fix loop bounded.** Three rounds, then escalate the implementer to Opus;
   if still failing, slice goes back to the spec writer.
6. **No original material in git.** Hygiene auditor runs on every merge.
7. **One ADR per irreversible choice** (physics tick rate, data schema,
   save format, networking stance).
8. **Cross-platform is a gate, not a phase.** CI matrix runs from Phase 0.
9. **Conventions are a review criterion.** Every reviewer checks the slice
   against `docs/CONVENTIONS.md`; the gate reviewer rejects on architecture
   violations (coupling, autoload sprawl, sim/presentation mixing, literals
   instead of Resources).
10. **Reach is a gate.** A slice that drops the Low preset below 60 fps on
    the benchmark scene, breaks a supported aspect ratio, or adds an
    unremappable input does not merge.
11. **Faithful by default, moddable by design.** No slice merges if it
    hard-codes a value the mod loader is meant to override, or if enabling
    the Modern pack and disabling it again changes base-game test results.

---

## 4b. Token and cost tracking

`tools/ops/token_ledger.py` reads this project's Claude Code transcripts and
writes `.omc/ledger/REPORT.md` (gitignored): tokens and API list-price cost by
model and effort, by phase, by agent and by session. The orchestrator reruns
it after every milestone and reports the running total. Every spawned agent
gets a phase-prefixed name (`p1-rules-lead`, `s3-impl`) so the ledger groups
it automatically. Input and cache counts are exact; output for unfinished
requests is estimated, so totals are a lower bound.

## 5. What happens on "go"

1. Orchestrator: install Godot/gdtoolkit, scaffold repo, commit Phase 0.
2. Orchestrator: REA orientation pass on `Rugby08.exe`, write the brief.
3. Fan out Phase 1 leads as a Workflow (8 pipelines: lead → sweeper/inventory
   → reviewer), collect specs, run ledger + verifier.
4. Architect pass, ADRs, slice specs for S1 and S9 (no asset dependency).
5. Start S1 and S9 concurrently; start Phase 2 immediately with the BIGF
   unpacker, then the member-format tools as the Phase 1 data-format spec lands.

Open items the user should answer (non-blocking):
- Licence (assumed GPL-3.0).
- Language (assumed GDScript).
- Target Godot version pinned at 4.7 (matches `project.godot`).
