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

## Run the prototype

The sandbox is self-contained: it needs no Rugby 08 install or extracted data. It is a limited
movement, ball-recovery, contact, kick and scoring prototype, not a complete Rugby match or the
finished Classic game. The project's default scene remains unchanged; this launcher explicitly
opens the sandbox scene.

Install Godot 4.7.2 (see `.godot-version`), then run:

On Windows, run this `.sh` launcher from Git Bash or WSL. Godot 4.7.2 must be available in that
same shell on `PATH` or via `GODOT_BIN`. Command Prompt and PowerShell do not run this Bash script
directly.

```bash
scripts/run-sandbox.sh
```

The launcher imports project resources on each launch, checks `scripts/check-godot-safe.sh`
immediately before both Godot processes, then opens
`res://game/prototype/prototype_sandbox.tscn`. It resolves the project path from its own location,
so it can be run from any working directory. If Godot is not on `PATH`, set `GODOT_BIN` to an
executable path. Controls: arrow keys move, Space sprints, and S kicks while the player carries
the ball.

The launcher runs these Godot commands using the absolute repository path in place of
`/absolute/path/to/openrugby`; each safety check is immediately before its Godot process:

```bash
scripts/check-godot-safe.sh
godot --headless --path /absolute/path/to/openrugby --import

scripts/check-godot-safe.sh
godot --path /absolute/path/to/openrugby res://game/prototype/prototype_sandbox.tscn
```

## Build and test

Godot 4.7.2 is the only requirement to run the prototype. Matching export templates are needed to
export builds. Install [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) 4.x for lint
and formatting checks. Python 3.12+ and `uv` are only needed for optional research tooling.

```bash
scripts/test.sh                         # gdUnit4 tests, headless, non-zero exit on failure
gdlint game autoload tests              # lint
gdformat --check --line-length 100 game autoload tests
scripts/hygiene.sh                      # no original assets / decompiled code in git
scripts/check-godot-safe.sh
godot --headless --path . --export-release Linux build/openrugby.x86_64   # also Windows, macOS
```

The export command has the safety guard immediately before its Godot process. Optional:
`uv tool install pre-commit && pre-commit install` to run checks on every commit.

## Optional reverse-engineering tools

These local tools are only for behavioral and format research; they are not needed to clone, build,
or run the prototype. Replacement runtime assets require no game copy. Access to a legally obtained
Rugby 08 install is optional and is only used as research input by the local tools. Original files
and extracted research data must remain local, gitignored, and outside runtime dependencies; never
bundle or commit them.

Godot follows symlinks and may write `.import` sidecars beside recognized files. The optional
linking helper therefore creates a real `original/` folder with `.gdignore` and links each install
entry inside it; it also marks `extracted/` with `.gdignore`. The safety check refuses to run Godot
if either directory is a symlink or lacks its ignore marker.

```bash
scripts/link-original.sh /path/to/Rugby08    # or set OPENRUGBY_GAME_DIR
PYTHONPATH=tools python -m openrugby_tools.pipeline --game-dir original --out extracted
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/CONVENTIONS.md](docs/CONVENTIONS.md). Participation
is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[GPL-3.0](LICENSE). Rugby 08 and related names belong to their respective owners; this project is
not affiliated with or endorsed by them.
