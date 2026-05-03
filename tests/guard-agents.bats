#!/usr/bin/env bats
# Tests for guard-agents.sh — per-session spawn limits, tier classification, soft warning.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	HOOK="$REPO_ROOT/.claude/hooks/guard-agents.sh"
	SPAWN_LOG="$REPO_ROOT/.claude/logs/agent-spawns.log"
	# Unique session per test to avoid counter pollution
	TEST_SESSION="bats-agents-$$-$RANDOM"
	rm -f "/tmp/claude-agents-total-${TEST_SESSION}" "/tmp/claude-agents-heavy-${TEST_SESSION}"
}

teardown() {
	rm -f "/tmp/claude-agents-total-${TEST_SESSION}" "/tmp/claude-agents-heavy-${TEST_SESSION}"
	# Remove test entries from the persistent log
	if [[ -f "$SPAWN_LOG" ]]; then
		grep -v "session=${TEST_SESSION}" "$SPAWN_LOG" > /tmp/bats-spawns-clean.log || true
		mv /tmp/bats-spawns-clean.log "$SPAWN_LOG"
	fi
}

run_hook() {
	local agent="$1"
	local json="{\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"subagent_type\":\"$agent\"}}"
	run bash -c "echo '$json' | '$HOOK' 2>&1"
}

run_hook_with_env() {
	local agent="$1"
	local env_vars="$2"
	local json="{\"session_id\":\"${TEST_SESSION}\",\"tool_input\":{\"subagent_type\":\"$agent\"}}"
	run bash -c "$env_vars bash -c \"echo '$json' | '$HOOK'\" 2>&1"
}

# --- Allowed spawns ---

@test "allows: code-reviewer under limit" {
	run_hook "code-reviewer"
	[ "$status" -eq 0 ]
}

@test "allows: debugger under heavy limit" {
	run_hook "debugger"
	[ "$status" -eq 0 ]
}

@test "allows: doc-writer (low tier)" {
	run_hook "doc-writer"
	[ "$status" -eq 0 ]
}

@test "allows: migration-planner under heavy limit" {
	run_hook "migration-planner"
	[ "$status" -eq 0 ]
}

# --- Hard blocks ---

@test "blocks: total limit reached" {
	echo "20" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run_hook "code-reviewer"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: heavy agent at heavy limit" {
	echo "4" > "/tmp/claude-agents-heavy-${TEST_SESSION}"
	echo "3" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run_hook "debugger"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: migration-planner at heavy limit" {
	echo "4" > "/tmp/claude-agents-heavy-${TEST_SESSION}"
	echo "3" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run_hook "migration-planner"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "allows: non-heavy agent when only heavy limit is reached" {
	echo "4" > "/tmp/claude-agents-heavy-${TEST_SESSION}"
	echo "3" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run_hook "code-reviewer"
	[ "$status" -eq 0 ]
}

# --- Soft warning at 80% ---

@test "emits soft warning at 80% of total" {
	# Default MAX_TOTAL=20, WARN_AT=16. Set counter to 15 so after +1 it hits 16.
	echo "15" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run bash -c "CLAUDE_MAX_AGENT_SPAWNS=20 bash -c \"echo '{\\\"session_id\\\":\\\"${TEST_SESSION}\\\",\\\"tool_input\\\":{\\\"subagent_type\\\":\\\"code-reviewer\\\"}}' | '$HOOK'\" 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Cost watch"* ]]
}

@test "no warning below 80% threshold" {
	echo "10" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run bash -c "CLAUDE_MAX_AGENT_SPAWNS=20 bash -c \"echo '{\\\"session_id\\\":\\\"${TEST_SESSION}\\\",\\\"tool_input\\\":{\\\"subagent_type\\\":\\\"code-reviewer\\\"}}' | '$HOOK'\" 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" != *"Cost watch"* ]]
}

# --- Custom limits via env ---

@test "respects CLAUDE_MAX_AGENT_SPAWNS override" {
	echo "5" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run bash -c "CLAUDE_MAX_AGENT_SPAWNS=5 bash -c \"echo '{\\\"session_id\\\":\\\"${TEST_SESSION}\\\",\\\"tool_input\\\":{\\\"subagent_type\\\":\\\"code-reviewer\\\"}}' | '$HOOK'\" 2>&1"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "respects CLAUDE_MAX_HEAVY_SPAWNS override" {
	echo "2" > "/tmp/claude-agents-heavy-${TEST_SESSION}"
	echo "1" > "/tmp/claude-agents-total-${TEST_SESSION}"
	run bash -c "CLAUDE_MAX_HEAVY_SPAWNS=2 bash -c \"echo '{\\\"session_id\\\":\\\"${TEST_SESSION}\\\",\\\"tool_input\\\":{\\\"subagent_type\\\":\\\"debugger\\\"}}' | '$HOOK'\" 2>&1"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

# --- Spawn log ---

@test "appends to spawns log on allowed spawn" {
	run_hook "code-reviewer"
	[ "$status" -eq 0 ]
	grep -q "session=${TEST_SESSION}" "$SPAWN_LOG"
}

@test "logs correct tier for low-tier agent" {
	run_hook "doc-writer"
	[ "$status" -eq 0 ]
	grep "session=${TEST_SESSION}" "$SPAWN_LOG" | grep -q "tier=low"
}

@test "logs correct tier for high-tier agent" {
	run_hook "debugger"
	[ "$status" -eq 0 ]
	grep "session=${TEST_SESSION}" "$SPAWN_LOG" | grep -q "tier=high"
}
