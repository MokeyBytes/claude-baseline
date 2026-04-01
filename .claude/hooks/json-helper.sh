#!/usr/bin/env bash
# Shared JSON parser — extracts values without requiring jq.
# Uses python3 (ships with macOS and Linux) with fallback to jq if available.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/json-helper.sh"
#   VALUE=$(json_get "$JSON_STRING" '.tool_input.command')

json_get() {
  local json="$1"
  local key_path="$2"

  # Build Python key traversal from dot notation (e.g. '.tool_input.command')
  local py_keys=""
  IFS='.' read -ra PARTS <<< "${key_path#.}"
  for part in "${PARTS[@]}"; do
    [[ -n "$part" ]] && py_keys="$py_keys.get('$part', {})"
  done

  # Replace final {} fallback with empty string
  py_keys="${py_keys/%\{\}/''}"

  if command -v python3 &>/dev/null; then
    echo "$json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    result = d${py_keys}
    if isinstance(result, dict):
        print('')
    else:
        print(result if result is not None else '')
except Exception:
    print('')
" 2>/dev/null
  elif command -v jq &>/dev/null; then
    echo "$json" | jq -r "${key_path} // empty" 2>/dev/null
  else
    echo ""
  fi
}
