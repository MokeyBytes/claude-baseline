#!/usr/bin/env bash
# Stop hook — runs type-checking and test suite when Claude finishes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/json-helper.sh"

INPUT=$(cat)

# Prevent infinite loop: if stop_hook_active is true, another stop hook triggered this
STOP_HOOK_ACTIVE=$(json_get "$INPUT" '.stop_hook_active')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Only run tests if files were actually modified during this session
cd "$PROJECT_DIR"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  CHANGED_FILES=$(git diff --name-only 2>/dev/null)
  UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null)
  if [[ -z "$CHANGED_FILES" && -z "$UNTRACKED_FILES" ]]; then
    exit 0
  fi
fi

# Max time for test suite (prevents hanging tests from blocking the session)
TEST_TIMEOUT=120

run_with_timeout() {
  if command -v timeout &>/dev/null; then
    timeout "$TEST_TIMEOUT" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$TEST_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# Run tsc type-check if this is a TypeScript project
if [[ -f "$PROJECT_DIR/tsconfig.json" ]] && command -v tsc &>/dev/null; then
  echo "Running type-check..."
  if ! run_with_timeout tsc --noEmit --pretty 2>&1 | head -30; then
    echo "WARNING: tsc --noEmit reported type errors" >&2
    # Non-blocking — type errors don't prevent stop
  fi
fi

# Detect and run the appropriate test runner
if [[ -f "$PROJECT_DIR/package.json" ]]; then
  HAS_TEST=$(python3 -c "
import json, sys
try:
    pkg = json.load(open('$PROJECT_DIR/package.json'))
    print(pkg.get('scripts', {}).get('test', ''))
except Exception:
    print('')
" 2>/dev/null)
  if [[ -n "$HAS_TEST" && "$HAS_TEST" != "echo \"Error: no test specified\" && exit 1" ]]; then
    cd "$PROJECT_DIR"
    if ! run_with_timeout npm test 2>&1; then
      echo "FAILED: npm test failed — review test output above" >&2
      exit 2
    fi
    exit 0
  fi
elif [[ -f "$PROJECT_DIR/pytest.ini" || -f "$PROJECT_DIR/pyproject.toml" || -f "$PROJECT_DIR/setup.py" || -d "$PROJECT_DIR/tests" ]]; then
  if command -v pytest &>/dev/null; then
    cd "$PROJECT_DIR"
    if ! run_with_timeout pytest --tb=short 2>&1; then
      echo "FAILED: pytest failed — review test output above" >&2
      exit 2
    fi
    exit 0
  fi
elif [[ -f "$PROJECT_DIR/go.mod" ]]; then
  if command -v go &>/dev/null; then
    cd "$PROJECT_DIR"
    if ! run_with_timeout go test ./... 2>&1; then
      echo "FAILED: go test failed — review test output above" >&2
      exit 2
    fi
    exit 0
  fi
fi

# No test runner found — exit silently
exit 0
