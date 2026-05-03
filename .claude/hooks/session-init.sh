#!/usr/bin/env bash
# SessionStart hook — exports project context and detects available tooling.
set -uo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
NODE_ENV="${NODE_ENV:-development}"

if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
	{
		echo "PROJECT_ROOT=$PROJECT_ROOT"
		echo "GIT_BRANCH=$GIT_BRANCH"
		echo "NODE_ENV=$NODE_ENV"
	} >>"$CLAUDE_ENV_FILE"
fi

# Check for python3 — json-helper.sh depends on it (jq used as fallback)
if ! command -v python3 &>/dev/null && ! command -v jq &>/dev/null; then
	echo "WARNING: neither python3 nor jq found — all hooks will be disabled (no-op)" >&2
fi

echo "Session initialized"
echo "  Project: $PROJECT_ROOT"
echo "  Branch:  $GIT_BRANCH"
echo "  Env:     $NODE_ENV"

# Detect available formatters and linters
TOOLS=()
for tool in biome prettier eslint tsc ruff black autopep8 yapf gofmt rustfmt shfmt clang-format google-java-format ktfmt swift-format dart rubocop php-cs-fixer stylua zig cargo; do
	if command -v "$tool" &>/dev/null; then
		TOOLS+=("$tool")
	fi
done

if [[ ${#TOOLS[@]} -gt 0 ]]; then
	echo "  Tools:   ${TOOLS[*]}"
else
	echo "  Tools:   none detected (formatting hooks will be no-ops)"
fi

# Detect project type from manifest files
MANIFESTS=()
[[ -f "$PROJECT_ROOT/package.json" ]] && MANIFESTS+=("node")
[[ -f "$PROJECT_ROOT/pyproject.toml" || -f "$PROJECT_ROOT/setup.py" || -f "$PROJECT_ROOT/requirements.txt" ]] && MANIFESTS+=("python")
[[ -f "$PROJECT_ROOT/go.mod" ]] && MANIFESTS+=("go")
[[ -f "$PROJECT_ROOT/Cargo.toml" ]] && MANIFESTS+=("rust")
[[ -f "$PROJECT_ROOT/Gemfile" ]] && MANIFESTS+=("ruby")
[[ -f "$PROJECT_ROOT/composer.json" ]] && MANIFESTS+=("php")

if [[ ${#MANIFESTS[@]} -gt 0 ]]; then
	echo "  Stack:   ${MANIFESTS[*]}"
fi

# Detect loaded agents from .claude/agents/
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"
if [[ -d "$AGENTS_DIR" ]]; then
	AGENT_LINES=()
	while IFS= read -r agent_file; do
		name=$(grep -m1 '^name:' "$agent_file" 2>/dev/null | sed 's/^name:[[:space:]]*//')
		model=$(grep -m1 '^model:' "$agent_file" 2>/dev/null | sed 's/^model:[[:space:]]*//')
		effort=$(grep -m1 '^effort:' "$agent_file" 2>/dev/null | sed 's/^effort:[[:space:]]*//')
		[[ -n "$name" ]] && AGENT_LINES+=("    $name ($model${effort:+, $effort})")
	done < <(find "$AGENTS_DIR" -maxdepth 1 -name '*.md' | sort)

	if [[ ${#AGENT_LINES[@]} -gt 0 ]]; then
		echo "  Agents:"
		printf '%s\n' "${AGENT_LINES[@]}"
	fi
fi

# Show cumulative agent spawn stats from persistent cross-session log
SPAWN_LOG="$PROJECT_ROOT/.claude/logs/agent-spawns.log"
if [[ -f "$SPAWN_LOG" ]]; then
	TOTAL_ALL=$(wc -l <"$SPAWN_LOG" | tr -d ' ')
	HEAVY_ALL=$(grep -c 'tier=high' "$SPAWN_LOG" 2>/dev/null || echo 0)
	echo "  Spawns:  $TOTAL_ALL all-time ($HEAVY_ALL opus)"
fi

exit 0
