#!/usr/bin/env bash
# PostToolUse hook for Write|Edit|MultiEdit|NotebookEdit — auto-formats written files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  exit 0
fi

EXTENSION="${FILE_PATH##*.}"

case "$EXTENSION" in
  js|jsx|ts|tsx|json|css|scss|md|html|yaml|yml)
    if command -v prettier &>/dev/null; then
      prettier --write "$FILE_PATH" 2>&1 >/dev/null || echo "prettier failed on $FILE_PATH" >&2
    fi
    ;;
  py)
    if command -v black &>/dev/null; then
      black --quiet "$FILE_PATH" 2>&1 >/dev/null || echo "black failed on $FILE_PATH" >&2
    fi
    ;;
  go)
    if command -v gofmt &>/dev/null; then
      gofmt -w "$FILE_PATH" 2>&1 >/dev/null || echo "gofmt failed on $FILE_PATH" >&2
    fi
    ;;
esac

# Run ESLint --fix on JS/TS files (after prettier so eslint rules win on conflicts)
case "$EXTENSION" in
  js|jsx|ts|tsx)
    if command -v eslint &>/dev/null; then
      eslint --fix "$FILE_PATH" 2>&1 >/dev/null || echo "eslint failed on $FILE_PATH" >&2
    fi
    ;;
esac

# Note: tsc --noEmit is intentionally NOT run here — it type-checks the entire
# project on every file save, which is too slow. Type-checking runs in the
# Stop hook instead (once, after all edits are done).

# Non-blocking: always exit 0
exit 0
