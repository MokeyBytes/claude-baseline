#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks destructive commands and user-intent commands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
COMMAND=$(json_get "$INPUT" '.tool_input.command')

if [[ -z "$COMMAND" ]]; then
	exit 0
fi

COMMAND_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

# --- Commands that require explicit user intent ---
# These are not destructive but should never be run autonomously.
# The user gets a clear message telling them how to run it themselves.
USER_INTENT_PATTERNS=(
	'git push'
	'npm publish'
	'yarn publish'
	'cargo publish'
	'twine upload'
	'gem push'
)

for pattern in "${USER_INTENT_PATTERNS[@]}"; do
	PATTERN_LOWER=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
	if [[ "$COMMAND_LOWER" == *"$PATTERN_LOWER"* ]]; then
		echo "BLOCKED: '$pattern' requires explicit user intent." >&2
		echo "Run it yourself with:  ! $COMMAND" >&2
		exit 2
	fi
done

# --- Destructive commands — always blocked ---
BLOCKED_PATTERNS=(
	# Filesystem destruction
	'rm -rf'
	'--no-preserve-root'
	'mkfs\.'
	'dd if='
	'> /dev/sda'
	':(){:|:&};:'
	# Database destruction
	'DROP TABLE'
	'DROP DATABASE'
	# Git destructive operations
	'git reset --hard'
	'git clean -fd'
	'git clean -fx'
	'git checkout -- .'
	# Permission escalation
	'chmod -R 777 /'
	'chmod 777 /'
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
	PATTERN_LOWER=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
	if [[ "$COMMAND_LOWER" == *"$PATTERN_LOWER"* ]]; then
		echo "BLOCKED: command contains destructive pattern '$pattern'" >&2
		echo "Command was: $COMMAND" >&2
		exit 2
	fi
done

# Remote code execution — requires regex matching (glob can't express pipe semantics)
if [[ "$COMMAND_LOWER" =~ (curl|wget).+\|[[:space:]]*(bash|sh) ]]; then
	echo "BLOCKED: command pipes remote content directly to a shell" >&2
	echo "Command was: $COMMAND" >&2
	exit 2
fi

exit 0
