#!/usr/bin/env bash
# Run all hook tests. Requires bats-core: brew install bats-core
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if ! command -v bats &>/dev/null; then
	echo "bats not found. Install with: brew install bats-core" >&2
	exit 1
fi

echo "Running hook tests from $REPO_ROOT"
bats .claude/tests/*.bats
