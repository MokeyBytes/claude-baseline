#!/usr/bin/env bats
# Tests for guard-files.sh — blocks writes to env files, lockfiles, secrets, .git/, and out-of-project paths.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	HOOK="$REPO_ROOT/.claude/hooks/guard-files.sh"
}

run_hook() {
	local path="$1"
	local json="{\"tool_input\":{\"file_path\":\"$path\"}}"
	run bash -c "echo '$json' | '$HOOK' 2>&1"
}

run_hook_with_project_dir() {
	local path="$1"
	local project_dir="$2"
	local json="{\"tool_input\":{\"file_path\":\"$path\"}}"
	run bash -c "CLAUDE_PROJECT_DIR='$project_dir' bash -c \"echo '$json' | '$HOOK'\" 2>&1"
}

# --- Allowed paths ---

@test "allows: normal source file" {
	run_hook "/project/src/app.ts"
	[ "$status" -eq 0 ]
}

@test "allows: README.md" {
	run_hook "/project/README.md"
	[ "$status" -eq 0 ]
}

@test "allows: empty path" {
	run bash -c "echo '{\"tool_input\":{\"file_path\":\"\"}}' | '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
}

# --- Environment file blocks ---

@test "blocks: .env" {
	run_hook "/project/.env"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: .env.local" {
	run_hook "/project/.env.local"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: .env.production" {
	run_hook "/project/.env.production"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

# --- Lockfile blocks ---

@test "blocks: package-lock.json — hints npm install" {
	run_hook "/project/package-lock.json"
	[ "$status" -eq 2 ]
	[[ "$output" == *"npm install"* ]]
}

@test "blocks: yarn.lock — hints yarn install" {
	run_hook "/project/yarn.lock"
	[ "$status" -eq 2 ]
	[[ "$output" == *"yarn install"* ]]
}

@test "blocks: pnpm-lock.yaml" {
	run_hook "/project/pnpm-lock.yaml"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: Cargo.lock" {
	run_hook "/project/Cargo.lock"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: poetry.lock" {
	run_hook "/project/poetry.lock"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

# --- Secret/key file blocks ---

@test "blocks: .pem file" {
	run_hook "/project/cert.pem"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: .key file" {
	run_hook "/project/server.key"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: credentials.json" {
	run_hook "/project/credentials.json"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: service-account.json" {
	run_hook "/project/service-account.json"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

# --- Git internals block ---

@test "blocks: .git/config" {
	run_hook "/project/.git/config"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "blocks: .git/hooks/pre-commit" {
	run_hook "/project/.git/hooks/pre-commit"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

# --- Out-of-project block ---

@test "blocks: write outside project dir" {
	run bash -c "CLAUDE_PROJECT_DIR=/project bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"/etc/passwd\\\"}}' | '$HOOK'\" 2>&1"
	[ "$status" -eq 2 ]
	[[ "$output" == *"BLOCKED"* ]]
}

@test "allows: write inside project dir when CLAUDE_PROJECT_DIR set" {
	run bash -c "CLAUDE_PROJECT_DIR=/project bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"/project/src/app.ts\\\"}}' | '$HOOK'\" 2>&1"
	[ "$status" -eq 0 ]
}
