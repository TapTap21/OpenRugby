#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

if [[ -n "${GODOT_BIN:-}" ]]; then
	if [[ ! -x "$godot_bin" ]]; then
		echo "error: GODOT_BIN is not an executable path: $godot_bin" >&2
		exit 127
	fi
elif ! command -v "$godot_bin" >/dev/null 2>&1; then
	echo "error: godot was not found on PATH; install Godot 4.7.2 or set GODOT_BIN" >&2
	exit 127
fi

if ! "$repo_root/scripts/check-godot-safe.sh"; then
	echo "error: refusing to import with Godot because the safety check failed" >&2
	exit 1
fi
"$godot_bin" --headless --path "$repo_root" --import

if ! "$repo_root/scripts/check-godot-safe.sh"; then
	echo "error: refusing to launch Godot because the safety check failed" >&2
	exit 1
fi
exec "$godot_bin" --path "$repo_root" res://game/prototype/prototype_sandbox.tscn
