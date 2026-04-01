#!/usr/bin/env bash
# PreToolUse hook for Write|Edit|MultiEdit — blocks writes to protected files.
set -euo pipefail

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Resolve to absolute path for comparison
RESOLVED_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# Block .env files
BASENAME=$(basename "$RESOLVED_PATH")
if [[ "$BASENAME" == ".env" || "$BASENAME" == .env.* ]]; then
  echo "BLOCKED: cannot write to environment file '$BASENAME'" >&2
  exit 2
fi

# Block lockfiles — use the package manager instead
case "$BASENAME" in
  package-lock.json)
    echo "BLOCKED: cannot write to package-lock.json — run npm install instead" >&2
    exit 2
    ;;
  yarn.lock)
    echo "BLOCKED: cannot write to yarn.lock — run yarn install instead" >&2
    exit 2
    ;;
  pnpm-lock.yaml)
    echo "BLOCKED: cannot write to pnpm-lock.yaml — run pnpm install instead" >&2
    exit 2
    ;;
  Gemfile.lock)
    echo "BLOCKED: cannot write to Gemfile.lock — run bundle install instead" >&2
    exit 2
    ;;
  poetry.lock)
    echo "BLOCKED: cannot write to poetry.lock — run poetry install instead" >&2
    exit 2
    ;;
  Cargo.lock)
    echo "BLOCKED: cannot write to Cargo.lock — run cargo build instead" >&2
    exit 2
    ;;
  composer.lock)
    echo "BLOCKED: cannot write to composer.lock — run composer install instead" >&2
    exit 2
    ;;
esac

# Block secret/key files
EXTENSION="${BASENAME##*.}"
case "$EXTENSION" in
  pem|key|p12|pfx|jks|keystore)
    echo "BLOCKED: cannot write to secret/key file '$BASENAME'" >&2
    exit 2
    ;;
esac
case "$BASENAME" in
  credentials|credentials.*|*_credentials.*|service-account*.json)
    echo "BLOCKED: cannot write to credentials file '$BASENAME'" >&2
    exit 2
    ;;
esac

# Block .git/ directory
if [[ "$RESOLVED_PATH" == *"/.git/"* || "$RESOLVED_PATH" == *"/.git" ]]; then
  echo "BLOCKED: cannot write to .git/ directory" >&2
  exit 2
fi

# Block writes outside project directory
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR=$(realpath -m "$CLAUDE_PROJECT_DIR" 2>/dev/null || echo "$CLAUDE_PROJECT_DIR")
  if [[ "$RESOLVED_PATH" != "$PROJECT_DIR"* ]]; then
    echo "BLOCKED: cannot write to '$RESOLVED_PATH' — outside project directory '$PROJECT_DIR'" >&2
    exit 2
  fi
fi

exit 0
