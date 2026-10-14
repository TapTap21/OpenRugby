#!/usr/bin/env bash
# Runs the gdUnit4 suites headless. Exits non-zero on any failure.
# Usage: scripts/test.sh [test path, default res://tests]
# Env:   GODOT_BIN overrides the engine binary (default: godot).
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
TARGET="${1:-res://tests}"

# Make sure class_name cache and imports exist (fresh CI checkouts have no .godot/).
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

# gdUnit4 exits 100 on test failures, 101 on warnings-only; treat only 0 as success.
"$GODOT_BIN" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	--ignoreHeadlessMode -a "$TARGET" -c </dev/null
