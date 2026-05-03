#!/usr/bin/env bats
# Tests for audit-prompt.sh — prompt logging and secret redaction.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	HOOK="$REPO_ROOT/.claude/hooks/audit-prompt.sh"
	PROMPT_LOG="$REPO_ROOT/.claude/logs/prompts.log"
	TEST_SESSION="bats-prompt-$$-$RANDOM"
	# Export so child processes spawned by run inherit it
	export CLAUDE_SESSION_ID="${TEST_SESSION}"
}

teardown() {
	unset CLAUDE_SESSION_ID
	if [[ -f "$PROMPT_LOG" ]]; then
		grep -v "session=${TEST_SESSION}" "$PROMPT_LOG" > /tmp/bats-prompt-clean.log || true
		mv /tmp/bats-prompt-clean.log "$PROMPT_LOG"
	fi
}

# --- Always exits 0 ---

@test "allows: clean prompt exits 0" {
	run bash -c "printf '{\"prompt\":\"refactor the auth module\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
}

@test "allows: empty prompt exits 0" {
	run bash -c "printf '{\"prompt\":\"\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
}

@test "allows: prompt with rm -rf exits 0 (natural language, not blocked)" {
	run bash -c "printf '{\"prompt\":\"explain why rm -rf is dangerous\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
}

@test "allows: prompt with DROP TABLE exits 0 (warn only)" {
	run bash -c "printf '{\"prompt\":\"what does DROP TABLE do\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
}

# --- Warning on dangerous patterns ---

@test "warns: prompt containing rm -rf" {
	run bash -c "printf '{\"prompt\":\"run rm -rf on the temp folder\"}' | '${HOOK}' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"WARNING"* ]]
}

@test "warns: prompt containing DROP TABLE" {
	run bash -c "printf '{\"prompt\":\"write a migration with DROP TABLE\"}' | '${HOOK}' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"WARNING"* ]]
}

# --- Logging ---

@test "logs prompt to prompts.log" {
	run bash -c "printf '{\"prompt\":\"add unit tests to the parser\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
	grep -q "session=${TEST_SESSION}" "$PROMPT_LOG"
}

# --- Secret redaction ---

@test "redacts OpenAI-style key from log" {
	run bash -c "printf '{\"prompt\":\"my key is sk-abcdefghijklmnopqrstuvwxyz123456\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
	LOG_LINE=$(grep "session=${TEST_SESSION}" "$PROMPT_LOG" | tail -1)
	[[ "$LOG_LINE" == *"[REDACTED]"* ]]
	[[ "$LOG_LINE" != *"sk-abcdefghijklmnopqrstuvwxyz123456"* ]]
}

@test "redacts AWS access key from log" {
	run bash -c "printf '{\"prompt\":\"aws key is AKIAIOSFODNN7EXAMPLE here\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
	LOG_LINE=$(grep "session=${TEST_SESSION}" "$PROMPT_LOG" | tail -1)
	[[ "$LOG_LINE" == *"[REDACTED]"* ]]
	[[ "$LOG_LINE" != *"AKIAIOSFODNN7EXAMPLE"* ]]
}

@test "redacts GitHub token from log" {
	run bash -c "printf '{\"prompt\":\"token ghp_abcdefghijklmnopqrstuvwxyz1234567890 for auth\"}' | '${HOOK}'"
	[ "$status" -eq 0 ]
	LOG_LINE=$(grep "session=${TEST_SESSION}" "$PROMPT_LOG" | tail -1)
	[[ "$LOG_LINE" == *"[REDACTED]"* ]]
}
