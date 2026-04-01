#!/usr/bin/env bash
# ConfigChange hook — logs configuration changes for audit trail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
SOURCE=$(json_get "$INPUT" '.source')
FILE_PATH=$(json_get "$INPUT" '.file_path')

if [[ -z "$SOURCE" && -z "$FILE_PATH" ]]; then
  exit 0
fi

# Ensure log directory exists
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

echo "[$TIMESTAMP] session=$SESSION_ID source=$SOURCE file=$FILE_PATH" >> "$LOG_DIR/config-changes.log"

exit 0
