<img src="assets/icon.svg" width="64" height="64" alt="">

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

## You need your own copy of Rugby 08

OpenRugby contains no original game assets, binaries or decompiled code. Art, audio and data are
extracted from **your own legally obtained copy of Rugby 08** by the tools in `tools/`, the same
model OpenMW uses. Until the extractors land, the game runs on placeholder content.

## Build and test

Requirements: Godot 4.7.2 (see `.godot-version`) with matching export templates,
[gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) 4.x, Python 3.12+ and `uv`.

```bash
godot --headless --path . --import      # first-time import
godot --path .                          # run the game
scripts/test.sh                         # gdUnit4 tests, headless, non-zero exit on failure
gdlint game autoload tests              # lint
gdformat --check --line-length 100 game autoload tests
scripts/hygiene.sh                      # no original assets / decompiled code in git
godot --headless --export-release Linux build/openrugby.x86_64   # export (also Windows, macOS)
```

Optional: `uv tool install pre-commit && pre-commit install` to run the checks on every commit.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/CONVENTIONS.md](docs/CONVENTIONS.md). Participation
is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[GPL-3.0](LICENSE). Rugby 08 and related names belong to their respective owners; this project is
not affiliated with or endorsed by them.
