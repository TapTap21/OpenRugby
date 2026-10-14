#!/usr/bin/env bash
# Refuse to run Godot while original game files or extracted assets are visible to
# the project scanner. Godot follows symlinks and would write into the user's install.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for dir in original extracted; do
	path="$root/$dir"
	if [[ -L "$path" ]]; then
		echo "unsafe: $dir is a symlink; run scripts/link-original.sh" >&2
		status=1
	elif [[ -d "$path" && ! -f "$path/.gdignore" ]]; then
		echo "unsafe: $dir/ has no .gdignore; Godot would import it" >&2
		status=1
	fi
done
exit "$status"
