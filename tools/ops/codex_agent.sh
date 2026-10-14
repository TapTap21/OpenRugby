#!/usr/bin/env bash
# Run one non-interactive Codex sub-agent (provider fallback, docs/PLAN.md section 2b).
#
# Usage: tools/ops/codex_agent.sh NAME EFFORT PROMPT_FILE [WORKDIR]
#   NAME         phase-prefixed agent name, e.g. p1-physics-lead (used for logs and the ledger)
#   EFFORT       low | medium | high | xhigh
#   PROMPT_FILE  task brief (markdown); AGENTS.md rules are prepended automatically
#   WORKDIR      repo or worktree to run in (default: repo root)
# Env: OPENRUGBY_CODEX_MODEL (default gpt-6-luna)
#
# Output: .omc/codex/<NAME>/{prompt.md,events.jsonl,stderr.log,report.md,exit_code}
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name="$1"; effort="$2"; prompt_file="$3"; workdir="${4:-$root}"
model="${OPENRUGBY_CODEX_MODEL:-gpt-6-luna}"
out="$root/.omc/codex/$name"
mkdir -p "$out"

{
	echo "You are '$name', an OpenRugby sub-agent running on $model (Claude quota fallback)."
	echo "First read $root/AGENTS.md and obey it. Work only inside $workdir unless the brief says otherwise."
	echo "Never commit unless the brief explicitly says to. Put your final report as your last message."
	echo
	cat "$prompt_file"
} > "$out/prompt.md"

set +e
codex exec \
	-m "$model" \
	-c model_reasoning_effort="$effort" \
	-c approval_policy=never \
	-c 'mcp_servers.rea.env.REA_GHIDRA_STARTUP_TIMEOUT_MS="1800000"' \
	-c mcp_servers.rea.tool_timeout_sec=1800 \
	-c 'mcp_servers.rea.default_tools_approval_mode="approve"' \
	-c mcp_servers.rea.startup_timeout_sec=120 \
	-s workspace-write \
	--add-dir "$root/.omc" \
	--add-dir "$root/.git" \
	-C "$workdir" \
	-o "$out/report.md" \
	--json \
	"$(cat "$out/prompt.md")" > "$out/events.jsonl" 2> "$out/stderr.log"
code=$?
set -e
echo "$code" > "$out/exit_code"
exit "$code"
