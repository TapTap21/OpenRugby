<img src="icon.svg" width="64" height="64" alt="">

# OpenRugby

An open-source, cross-platform rebuild of EA Rugby 08 in [Godot](https://godotengine.org) 4.7,
written in typed GDScript. Gameplay fidelity comes first; new features come later, as mods.

## Classic by default, mods for the modern game

The default profile, **Classic**, aims to reproduce the original rules, pacing and feel as
recovered from behavioural analysis. Everything that modernises the game (current World Rugby
laws, widescreen HUD, quality-of-life options, tuned AI) ships as optional mods on a built-in mod
loader. The "Modern" profile is a one-click preset of the first-party mods. See
[docs/PLAN.md](docs/PLAN.md) section 1d and [ADR-003](docs/adr/ADR-003-mod-loader.md).

## Platforms

Linux, Windows and macOS (universal). The Compatibility renderer (OpenGL) is the default so the
game runs on integrated graphics, the Steam Deck and older machines, including Linux without Vulkan.

## A self-contained project

OpenRugby runs from the files in this repository. It does not need a Rugby 08 installation,
`original/`, extracted game data, or external game assets. The runtime uses project-owned,
editable content. The current interactive sandbox draws generated primitive visuals, so its art
is provisional; it is not yet a complete Rugby match or a finished set of replacement assets.
Future replacement assets will live in the project and remain editable. Original game files,
extracted assets and decompiled code are not part of this project.

## Build and test

To run the project, install Godot 4.7.2 (see `.godot-version`). Matching export templates are
needed to make release builds. Python 3.12+, `uv`, and
[gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) 4.x are contributor tools for the
checks and Python tooling, not runtime dependencies.

```bash
scripts/check-godot-safe.sh
godot --headless --path . --import      # first-time import
scripts/check-godot-safe.sh
godot --path .                          # run the game
scripts/test.sh                         # gdUnit4 tests, headless, non-zero exit on failure
gdlint game autoload tests              # lint
gdformat --check --line-length 100 game autoload tests
scripts/hygiene.sh                      # no original assets / decompiled code in git
scripts/check-godot-safe.sh
godot --headless --export-release Linux build/openrugby.x86_64   # export (also Windows, macOS)
```

### Run the provisional sandbox

The default project scene remains the title screen, and `godot --path .` still opens it. This
explicit scene is a provisional generated-primitive sandbox with a limited movement, ball recovery,
contact, kick and scoring loop: a quick way to run a small interactive scene, not a complete Rugby
match or Classic gameplay.

```bash
scripts/check-godot-safe.sh
godot --headless --path . --import

scripts/check-godot-safe.sh
godot --path . res://game/prototype/prototype_sandbox.tscn
```

Controls: arrow keys move, Space sprints, and S kicks while the player carries the ball.

Optional: `uv tool install pre-commit && pre-commit install` to run the checks on every commit.

The optional Python asset-pipeline utilities are for contributor research and tooling only; they
are not part of startup, gameplay, or export. You can run and edit the current sandbox without
linking or extracting a game installation. `scripts/test.sh` runs
`scripts/check-godot-safe.sh` before tests to guard against accidental symlinks into protected
local folders.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/CONVENTIONS.md](docs/CONVENTIONS.md). Participation
is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[GPL-3.0](LICENSE). Rugby 08 and related names belong to their respective owners; this project is
not affiliated with or endorsed by them.
