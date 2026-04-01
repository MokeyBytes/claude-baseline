#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks destructive commands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
COMMAND=$(json_get "$INPUT" '.tool_input.command')

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

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
  'git push --force'
  'git push -f'
  'git reset --hard'
  'git clean -fd'
  'git clean -fx'
  'git checkout -- .'
  # Permission escalation
  'chmod -R 777 /'
  'chmod 777 /'
  # Remote code execution
  'curl.*| bash'
  'curl.*| sh'
  'wget.*| bash'
  'wget.*| sh'
  # Publishing (requires explicit intent)
  'npm publish'
  'yarn publish'
  'cargo publish'
  'twine upload'
  'gem push'
)

COMMAND_LOWER=$(echo "$COMMAND" | tr '[:upper:]' '[:lower:]')

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  PATTERN_LOWER=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
  if [[ "$COMMAND_LOWER" == *"$PATTERN_LOWER"* ]]; then
    echo "BLOCKED: command contains destructive pattern '$pattern'" >&2
    echo "Command was: $COMMAND" >&2
    exit 2
  fi
done

exit 0
