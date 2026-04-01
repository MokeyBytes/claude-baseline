#!/usr/bin/env bash
# PostToolUse hook for Write|Edit|NotebookEdit — auto-formats written files.
# Suggests missing formatters via systemMessage (shown to user, not fed to Claude).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  exit 0
fi

EXTENSION="${FILE_PATH##*.}"
MISSING_TOOLS=()

case "$EXTENSION" in
  js|jsx|ts|tsx|json|css|scss|md|html|yaml|yml)
    if command -v prettier &>/dev/null; then
      prettier --write "$FILE_PATH" 2>&1 >/dev/null || echo "prettier failed on $FILE_PATH" >&2
    else
      MISSING_TOOLS+=("prettier (npm i -g prettier)")
    fi
    ;;
  py)
    if command -v black &>/dev/null; then
      black --quiet "$FILE_PATH" 2>&1 >/dev/null || echo "black failed on $FILE_PATH" >&2
    else
      MISSING_TOOLS+=("black (pip install black)")
    fi
    ;;
  go)
    if command -v gofmt &>/dev/null; then
      gofmt -w "$FILE_PATH" 2>&1 >/dev/null || echo "gofmt failed on $FILE_PATH" >&2
    else
      MISSING_TOOLS+=("gofmt (install Go)")
    fi
    ;;
esac

# Run ESLint --fix on JS/TS files (after prettier so eslint rules win on conflicts)
case "$EXTENSION" in
  js|jsx|ts|tsx)
    if command -v eslint &>/dev/null; then
      eslint --fix "$FILE_PATH" 2>&1 >/dev/null || echo "eslint failed on $FILE_PATH" >&2
    else
      MISSING_TOOLS+=("eslint (npm i -g eslint)")
    fi
    ;;
esac

# Note: tsc --noEmit is intentionally NOT run here — it type-checks the entire
# project on every file save, which is too slow. Type-checking runs in the
# Stop hook instead (once, after all edits are done).

# If formatters are missing, surface a non-interruptive hint to the user
# systemMessage is shown to the user but NOT fed to Claude as context
if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  SUGGESTIONS=$(printf '%s, ' "${MISSING_TOOLS[@]}")
  SUGGESTIONS="${SUGGESTIONS%, }"
  cat <<EOF
{"systemMessage": "Auto-format skipped — missing: ${SUGGESTIONS}"}
EOF
  exit 0
fi

exit 0
