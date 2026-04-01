#!/usr/bin/env bash
# Notification hook — sends desktop notification when Claude needs input.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)
MESSAGE=$(json_get "$INPUT" '.message')
TITLE=$(json_get "$INPUT" '.title')

TITLE="${TITLE:-Claude Code}"
MESSAGE="${MESSAGE:-Claude Code needs your attention}"

case "$(uname -s)" in
  Darwin)
    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\"" 2>/dev/null || true
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "$TITLE" "$MESSAGE" 2>/dev/null || true
    fi
    ;;
esac

exit 0
