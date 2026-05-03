#!/usr/bin/env bats
# Tests for session-summary.sh — stop hook that emits session summary as systemMessage.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	HOOK="$REPO_ROOT/.claude/hooks/session-summary.sh"
	SPAWN_LOG="$REPO_ROOT/.claude/logs/agent-spawns.log"
	TEST_SESSION="bats-summary-$$-$RANDOM"
	CURRENT_HEAD=$(git -C "$REPO_ROOT" rev-parse HEAD)
}

teardown() {
	rm -f "/tmp/claude-session-head-${TEST_SESSION}"
	if [[ -f "$SPAWN_LOG" ]]; then
		grep -v "session=${TEST_SESSION}" "$SPAWN_LOG" > /tmp/bats-summary-clean.log || true
		mv /tmp/bats-summary-clean.log "$SPAWN_LOG"
	fi
}

add_spawn() {
	local tier="$1"
	local agent="$2"
	echo "[2026-05-03T10:00:00Z] session=${TEST_SESSION} agent=${agent} tier=${tier} total=1 heavy=0" >> "$SPAWN_LOG"
}

# --- Infinite loop guard ---

@test "exits silently when stop_hook_active is true" {
	run bash -c "echo '{\"stop_hook_active\":true,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# --- Skip when nothing happened ---

@test "exits silently when no files changed and no agents spawned" {
	# Run inside a git worktree so uncommitted local changes don't inflate the count
	local worktree
	worktree=$(mktemp -d)
	git worktree add "$worktree" HEAD --quiet 2>/dev/null
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	run bash -c "cd '$worktree' && echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	git worktree remove "$worktree" --force 2>/dev/null
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# --- Fires when agents were spawned ---

@test "emits systemMessage when agents spawned even with no file changes" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "mid" "code-reviewer"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"systemMessage"* ]]
}

# --- Agent tier breakdown ---

@test "shows low tier agent count" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "low" "doc-writer"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 low"* ]]
}

@test "shows high tier agent count" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "high" "debugger"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 high"* ]]
}

@test "shows total agent count" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "low" "doc-writer"
	add_spawn "mid" "code-reviewer"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"total: 2"* ]]
}

# --- No fake dollar estimates ---

@test "output contains no dollar sign cost estimates" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "high" "debugger"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" != *'est.'* ]]
}

# --- Output format ---

@test "output is valid JSON" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "mid" "code-reviewer"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)"
}

@test "output has systemMessage key" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "mid" "code-reviewer"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"systemMessage"'* ]]
}

@test "always exits 0 (never blocks)" {
	echo "$CURRENT_HEAD" > "/tmp/claude-session-head-${TEST_SESSION}"
	add_spawn "high" "debugger"
	run bash -c "echo '{\"stop_hook_active\":false,\"session_id\":\"${TEST_SESSION}\"}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
}
