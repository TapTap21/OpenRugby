#!/usr/bin/env bash
# Link a user-supplied Rugby 08 install into original/ without exposing it to Godot.
#
# Godot follows symlinks while scanning a project and writes .import/.translation
# files next to anything it recognises. original/ is therefore a real directory
# containing a .gdignore plus one symlink per top-level entry of the install, so
# Godot skips it entirely while tools can still use original/Data/... paths.
#
# Usage: scripts/link-original.sh [GAME_DIR]   (or set OPENRUGBY_GAME_DIR)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
game_dir="${1:-${OPENRUGBY_GAME_DIR:-}}"

if [[ -z "$game_dir" ]]; then
	echo "usage: $0 GAME_DIR (or set OPENRUGBY_GAME_DIR)" >&2
	exit 2
fi
if [[ ! -f "$game_dir/Rugby08.exe" || ! -d "$game_dir/Data" ]]; then
	echo "error: $game_dir does not look like a Rugby 08 install (Rugby08.exe, Data/)" >&2
	exit 1
fi
game_dir="$(cd "$game_dir" && pwd)"

target="$root/original"
if [[ -L "$target" ]]; then
	echo "replacing legacy symlink $target" >&2
	rm "$target"
fi
mkdir -p "$target"
touch "$target/.gdignore"
for entry in "$game_dir"/*; do
	ln -sfn "$entry" "$target/$(basename "$entry")"
done

mkdir -p "$root/extracted"
touch "$root/extracted/.gdignore"

echo "linked $game_dir -> $target (Godot-ignored)"
