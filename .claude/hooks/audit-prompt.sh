#!/usr/bin/env bash
# UserPromptSubmit hook — logs prompts and blocks dangerous input patterns.
set -euo pipefail

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# Ensure log directory exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"

# Redact potential secrets before logging
# Matches common API key/token formats and replaces with [REDACTED]
SAFE_PROMPT=$(echo "$PROMPT" | sed -E \
  -e 's/(sk-[a-zA-Z0-9]{20,})/[REDACTED]/g' \
  -e 's/(key-[a-zA-Z0-9]{20,})/[REDACTED]/g' \
  -e 's/(ghp_[a-zA-Z0-9]{36,})/[REDACTED]/g' \
  -e 's/(gho_[a-zA-Z0-9]{36,})/[REDACTED]/g' \
  -e 's/(github_pat_[a-zA-Z0-9_]{20,})/[REDACTED]/g' \
  -e 's/(xox[bposatr]-[a-zA-Z0-9\-]{10,})/[REDACTED]/g' \
  -e 's/(AKIA[A-Z0-9]{16})/[REDACTED]/g' \
  -e 's/(eyJ[a-zA-Z0-9_\-]{20,}\.[a-zA-Z0-9_\-]{20,})/[REDACTED]/g' \
  -e 's/([a-zA-Z0-9_]*([Ss]ecret|[Tt]oken|[Kk]ey|[Pp]assword|[Cc]redential|API_KEY|api_key)[a-zA-Z0-9_]*[=: ]+['\''"]?)([^ '\''",}{]{8,})/\1[REDACTED]/g' \
  -e 's/(-----BEGIN [A-Z ]+ KEY-----)/[REDACTED PEM KEY]/g' \
)

# Log the redacted prompt
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[$TIMESTAMP] session=$SESSION_ID prompt=$(echo "$SAFE_PROMPT" | head -c 500)" >> "$LOG_DIR/prompts.log"

# Block dangerous patterns in prompts
BLOCKED_PATTERNS=(
  'rm -rf'
  'DROP TABLE'
  'DROP DATABASE'
  '--no-preserve-root'
  'format c:'
  'delete from.*where 1=1'
)

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  PATTERN_LOWER=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
  if [[ "$PROMPT_LOWER" == *"$PATTERN_LOWER"* ]]; then
    echo "WARNING: prompt contains pattern '$pattern' — proceed with caution" >&2
    # Warn only; do not block natural language prompts
    exit 0
  fi
done

exit 0
