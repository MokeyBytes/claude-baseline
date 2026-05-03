#!/usr/bin/env bash
# PreToolUse hook for Agent — enforces per-session spawn limits and logs all spawns for cost telemetry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
SESSION_ID=$(json_get "$INPUT" '.session_id')
AGENT_TYPE=$(json_get "$INPUT" '.tool_input.subagent_type')

SESSION_ID="${SESSION_ID:-default}"
AGENT_TYPE="${AGENT_TYPE:-general-purpose}"

# Configurable per-session limits — override via environment or .claude/settings.local.json env block
MAX_TOTAL="${CLAUDE_MAX_AGENT_SPAWNS:-20}"
MAX_HEAVY="${CLAUDE_MAX_HEAVY_SPAWNS:-4}"

# Session-scoped counter files in /tmp
TOTAL_FILE="/tmp/claude-agents-total-${SESSION_ID}"
HEAVY_FILE="/tmp/claude-agents-heavy-${SESSION_ID}"

# Agents backed by claude-opus-* models (highest cost tier)
HEAVY_AGENTS=("debugger" "migration-planner")

# Agents backed by claude-haiku-* models (lowest cost tier)
LOW_AGENTS=("doc-writer" "dependency-auditor" "performance-reviewer")

is_heavy() {
	local agent="$1"
	local h
	for h in "${HEAVY_AGENTS[@]}"; do
		[[ "$agent" == "$h" ]] && return 0
	done
	return 1
}

get_tier() {
	local agent="$1"
	local h
	for h in "${HEAVY_AGENTS[@]}"; do
		[[ "$agent" == "$h" ]] && echo "high" && return
	done
	for h in "${LOW_AGENTS[@]}"; do
		[[ "$agent" == "$h" ]] && echo "low" && return
	done
	echo "mid"
}

read_count() {
	local file="$1"
	local count=0
	if [[ -f "$file" ]]; then
		count=$(cat "$file" 2>/dev/null)
		count="${count:-0}"
	fi
	echo "$count"
}

increment() {
	local file="$1"
	local n
	n=$(read_count "$file")
	echo $((n + 1)) >"$file"
}

TOTAL=$(read_count "$TOTAL_FILE")
HEAVY=$(read_count "$HEAVY_FILE")

# Hard block: heavy agent (Opus) limit
if is_heavy "$AGENT_TYPE" && [[ "$HEAVY" -ge "$MAX_HEAVY" ]]; then
	echo "BLOCKED: '$AGENT_TYPE' uses claude-opus and has hit the heavy-agent limit ($HEAVY/$MAX_HEAVY per session)." >&2
	echo "Increase CLAUDE_MAX_HEAVY_SPAWNS to raise the limit, or route this task to a lighter agent." >&2
	exit 2
fi

# Hard block: total agent spawn limit
if [[ "$TOTAL" -ge "$MAX_TOTAL" ]]; then
	echo "BLOCKED: agent spawn limit reached ($TOTAL/$MAX_TOTAL per session)." >&2
	echo "Increase CLAUDE_MAX_AGENT_SPAWNS to raise the limit." >&2
	exit 2
fi

# Increment counters before warning so reported values reflect this spawn
increment "$TOTAL_FILE"
if is_heavy "$AGENT_TYPE"; then
	increment "$HEAVY_FILE"
fi

UPDATED_TOTAL=$(read_count "$TOTAL_FILE")
UPDATED_HEAVY=$(read_count "$HEAVY_FILE")

# Append to persistent cross-session spawn log (gitignored)
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIER=$(get_tier "$AGENT_TYPE")
echo "[$TIMESTAMP] session=$SESSION_ID agent=$AGENT_TYPE tier=$TIER total=$UPDATED_TOTAL heavy=$UPDATED_HEAVY" >>"$LOG_DIR/agent-spawns.log"

# Soft warning at 80% of total (systemMessage: shown to user, not fed to Claude)
WARN_AT=$((MAX_TOTAL * 80 / 100))
if [[ "$UPDATED_TOTAL" -ge "$WARN_AT" ]]; then
	echo "{\"systemMessage\": \"Cost watch: $UPDATED_TOTAL/$MAX_TOTAL agent spawns used this session (opus: $UPDATED_HEAVY/$MAX_HEAVY).\"}"
fi

exit 0
