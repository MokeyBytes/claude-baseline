#!/usr/bin/env bash
# Stop hook — outputs a non-disruptive session summary after Claude finishes.
# Shows files changed, agent tier breakdown, and new TODO/FIXME/HACK markers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)

# Infinite loop protection (required for all Stop hooks)
STOP_HOOK_ACTIVE=$(json_get "$INPUT" '.stop_hook_active')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
	exit 0
fi

SESSION_ID=$(json_get "$INPUT" '.session_id')
SESSION_ID="${SESSION_ID:-default}"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOG_DIR="$SCRIPT_DIR/../logs"
SPAWN_LOG="$LOG_DIR/agent-spawns.log"
HEAD_FILE="/tmp/claude-session-head-${SESSION_ID}"

# --- Files changed this session ---
INITIAL_HEAD=""
[[ -f "$HEAD_FILE" ]] && INITIAL_HEAD=$(cat "$HEAD_FILE" 2>/dev/null || echo "")

if [[ -n "$INITIAL_HEAD" ]]; then
	COMMITTED=$(git diff --name-only "${INITIAL_HEAD}" HEAD 2>/dev/null | wc -l | tr -d ' ')
	UNCOMMITTED=$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
	FILES_CHANGED=$((COMMITTED + UNCOMMITTED))
else
	FILES_CHANGED=$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Agent spawn counts for this session ---
LOW_COUNT=0
MID_COUNT=0
HIGH_COUNT=0

if [[ -f "$SPAWN_LOG" ]]; then
	LOW_COUNT=$(grep "session=${SESSION_ID} " "$SPAWN_LOG" | grep -c "tier=low" 2>/dev/null || true)
	MID_COUNT=$(grep "session=${SESSION_ID} " "$SPAWN_LOG" | grep -c "tier=mid" 2>/dev/null || true)
	HIGH_COUNT=$(grep "session=${SESSION_ID} " "$SPAWN_LOG" | grep -c "tier=high" 2>/dev/null || true)
	LOW_COUNT=${LOW_COUNT:-0}
	MID_COUNT=${MID_COUNT:-0}
	HIGH_COUNT=${HIGH_COUNT:-0}
fi

TOTAL_AGENTS=$((LOW_COUNT + MID_COUNT + HIGH_COUNT))

# Skip summary if nothing happened this session
if [[ "$FILES_CHANGED" -eq 0 && "$TOTAL_AGENTS" -eq 0 ]]; then
	exit 0
fi

# --- Agent tier summary ---
AGENT_PARTS=()
[[ "$LOW_COUNT" -gt 0 ]] && AGENT_PARTS+=("${LOW_COUNT} low")
[[ "$MID_COUNT" -gt 0 ]] && AGENT_PARTS+=("${MID_COUNT} mid")
[[ "$HIGH_COUNT" -gt 0 ]] && AGENT_PARTS+=("${HIGH_COUNT} high")

if [[ ${#AGENT_PARTS[@]} -gt 0 ]]; then
	AGENT_LIST=$(printf '%s, ' "${AGENT_PARTS[@]}")
	AGENT_LIST="${AGENT_LIST%, }"
	AGENT_STR="agents: ${AGENT_LIST} (total: ${TOTAL_AGENTS})"
else
	AGENT_STR="no agents"
fi

# --- New TODO/FIXME/HACK scanner ---
MARKER_STR=""
SESSION_DIFF=""
if [[ -n "$INITIAL_HEAD" ]]; then
	SESSION_DIFF=$(git diff "${INITIAL_HEAD}" HEAD 2>/dev/null || true)
fi
SESSION_DIFF+=$(git diff HEAD 2>/dev/null || true)

if [[ -n "$SESSION_DIFF" ]]; then
	MARKER_COUNT=$(echo "$SESSION_DIFF" |
		grep -E '^\+[^+]' |
		grep -iE '\b(TODO|FIXME|HACK)\b' |
		wc -l | tr -d ' ')
	[[ "$MARKER_COUNT" -gt 0 ]] && MARKER_STR=" | ${MARKER_COUNT} new TODO/FIXME/HACK"
fi

# --- Emit systemMessage (shown to user, not fed to Claude) ---
FILE_LABEL="${FILES_CHANGED} file"
[[ "$FILES_CHANGED" -ne 1 ]] && FILE_LABEL="${FILES_CHANGED} files"

cat <<EOF
{"systemMessage": "Session: ${FILE_LABEL} changed | ${AGENT_STR}${MARKER_STR}"}
EOF

exit 0
