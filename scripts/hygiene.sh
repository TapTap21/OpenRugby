#!/usr/bin/env bash
# Hygiene gate: fail if original game material or decompiled code is in the git index.
# Checks the index (staged + tracked files), so it works as a pre-commit hook and in CI.
set -uo pipefail

cd "$(dirname "$0")/.."
fail=0

files="$(git ls-files --cached)"

bad_paths="$(printf '%s\n' "$files" | grep -E '^(original|extracted)(/|$)' || true)"
# Containers, binaries and media formats from the original install (Data/, Audio/, root).
bad_ext="$(printf '%s\n' "$files" | grep -iE '\.(big|gob|viv|exe|dll|dat|evt|vp6)$' || true)"

if [ -n "$bad_paths" ]; then
	echo "HYGIENE FAIL: files under original/ or extracted/ are in the index:" >&2
	echo "$bad_paths" >&2
	fail=1
fi
if [ -n "$bad_ext" ]; then
	echo "HYGIENE FAIL: original-game container/binary extensions in the index:" >&2
	echo "$bad_ext" >&2
	fail=1
fi

# Decompiled-looking pseudo-code under docs/re (Hex-Rays/Ghidra style markers).
pattern='\b(undefined[0-9]?|_(DWORD|WORD|BYTE|QWORD)\b|__(cdecl|thiscall|fastcall|stdcall)|LOBYTE\(|HIWORD\(|\*\(_?(DWORD|int|undefined)|[a-z]+Var[0-9]+\b|FUN_[0-9a-f]{6,8}|sub_[0-9A-F]{6,8}|LAB_[0-9a-f]{6,8})'
while IFS= read -r f; do
	[ -n "$f" ] && [ -f "$f" ] || continue
	hits="$(grep -nE "$pattern" "$f" || true)"
	if [ -n "$hits" ]; then
		echo "HYGIENE FAIL: decompiler-looking pseudo-code in $f:" >&2
		echo "$hits" | head -5 >&2
		fail=1
	fi
done < <(printf '%s\n' "$files" | grep -E '^docs/re/.*\.(md|txt|c|cpp|h)$' || true)

# Renamed originals: EA container magic (BIGF/BIG4 archives, SCHl audio streams) in any file.
# Test fixtures must be generated at test time, not committed as EA-format binaries.
while IFS= read -r f; do
	[ -f "$f" ] && [ ! -L "$f" ] || continue
	magic="$(head -c 4 "$f" 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9')"
	case "$magic" in
	BIGF | BIG4 | SCHl)
		echo "HYGIENE FAIL: $f has EA container magic '$magic' (original game data?)" >&2
		fail=1
		;;
	esac
done <<<"$files"

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "hygiene: ok"
