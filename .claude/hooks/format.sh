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

# Detect platform for install hints
PLATFORM="unknown"
case "$(uname -s)" in
Darwin) PLATFORM="macos" ;;
Linux) PLATFORM="linux" ;;
CYGWIN* | MINGW* | MSYS*) PLATFORM="windows" ;;
esac

# Returns a platform-appropriate install hint for a given tool.
# Usage: install_hint <tool_name>
install_hint() {
	local tool="$1"
	case "$tool" in
	biome)
		echo "npm i -g @biomejs/biome"
		;;
	prettier)
		echo "npm i -g prettier"
		;;
	eslint)
		echo "npm i -g eslint"
		;;
	ruff)
		if command -v pipx &>/dev/null; then
			echo "pipx install ruff"
		else
			case "$PLATFORM" in
			macos) echo "brew install ruff" ;;
			linux) echo "pip install ruff" ;;
			windows) echo "pip install ruff" ;;
			*) echo "pip install ruff" ;;
			esac
		fi
		;;
	gofmt)
		case "$PLATFORM" in
		macos) echo "brew install go" ;;
		linux) echo "sudo apt install golang || sudo dnf install golang" ;;
		windows) echo "choco install golang" ;;
		*) echo "install Go from go.dev" ;;
		esac
		;;
	rustfmt)
		echo "rustup component add rustfmt"
		;;
	shfmt)
		case "$PLATFORM" in
		macos) echo "brew install shfmt" ;;
		linux) echo "sudo apt install shfmt || go install mvdan.cc/sh/v3/cmd/shfmt@latest" ;;
		windows) echo "choco install shfmt" ;;
		*) echo "go install mvdan.cc/sh/v3/cmd/shfmt@latest" ;;
		esac
		;;
	clang-format)
		case "$PLATFORM" in
		macos) echo "brew install clang-format" ;;
		linux) echo "sudo apt install clang-format || sudo dnf install clang-tools-extra" ;;
		windows) echo "choco install llvm" ;;
		*) echo "install LLVM/clang-format" ;;
		esac
		;;
	google-java-format)
		case "$PLATFORM" in
		macos) echo "brew install google-java-format" ;;
		linux) echo "install from github.com/google/google-java-format/releases" ;;
		windows) echo "install from github.com/google/google-java-format/releases" ;;
		*) echo "install from github.com/google/google-java-format/releases" ;;
		esac
		;;
	ktfmt)
		case "$PLATFORM" in
		macos) echo "brew install ktfmt" ;;
		linux) echo "install from github.com/facebook/ktfmt/releases" ;;
		windows) echo "install from github.com/facebook/ktfmt/releases" ;;
		*) echo "install from github.com/facebook/ktfmt/releases" ;;
		esac
		;;
	swift-format)
		case "$PLATFORM" in
		macos) echo "brew install swift-format" ;;
		linux) echo "install from github.com/swiftlang/swift-format/releases" ;;
		windows) echo "install from github.com/swiftlang/swift-format/releases" ;;
		*) echo "install from github.com/swiftlang/swift-format/releases" ;;
		esac
		;;
	dart)
		case "$PLATFORM" in
		macos) echo "brew install dart" ;;
		linux) echo "sudo apt install dart || see dart.dev/get-dart" ;;
		windows) echo "choco install dart-sdk" ;;
		*) echo "install from dart.dev/get-dart" ;;
		esac
		;;
	rubocop)
		echo "gem install rubocop"
		;;
	php-cs-fixer)
		echo "composer global require friendsofphp/php-cs-fixer"
		;;
	stylua)
		case "$PLATFORM" in
		macos) echo "brew install stylua" ;;
		linux) echo "cargo install stylua" ;;
		windows) echo "cargo install stylua" ;;
		*) echo "cargo install stylua" ;;
		esac
		;;
	zig)
		case "$PLATFORM" in
		macos) echo "brew install zig" ;;
		linux) echo "sudo snap install zig --classic || see ziglang.org/download" ;;
		windows) echo "choco install zig" ;;
		*) echo "install from ziglang.org/download" ;;
		esac
		;;
	*)
		echo "install $tool"
		;;
	esac
}

case "$EXTENSION" in
js | jsx | ts | tsx | json | css | scss | md | html | yaml | yml)
	if command -v biome &>/dev/null; then
		biome format --write "$FILE_PATH" 2>&1 >/dev/null || echo "biome failed on $FILE_PATH" >&2
	elif command -v prettier &>/dev/null; then
		prettier --write "$FILE_PATH" 2>&1 >/dev/null || echo "prettier failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("biome ($(install_hint biome))")
	fi
	;;
py)
	if command -v ruff &>/dev/null; then
		ruff format "$FILE_PATH" 2>&1 >/dev/null || echo "ruff format failed on $FILE_PATH" >&2
		ruff check --fix "$FILE_PATH" 2>&1 >/dev/null || echo "ruff check failed on $FILE_PATH" >&2
	elif command -v black &>/dev/null; then
		black --quiet "$FILE_PATH" 2>&1 >/dev/null || echo "black failed on $FILE_PATH" >&2
	elif command -v autopep8 &>/dev/null; then
		autopep8 --in-place "$FILE_PATH" 2>&1 >/dev/null || echo "autopep8 failed on $FILE_PATH" >&2
	elif command -v yapf &>/dev/null; then
		yapf --in-place "$FILE_PATH" 2>&1 >/dev/null || echo "yapf failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("ruff ($(install_hint ruff))")
	fi
	;;
go)
	if command -v gofmt &>/dev/null; then
		gofmt -w "$FILE_PATH" 2>&1 >/dev/null || echo "gofmt failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("gofmt ($(install_hint gofmt))")
	fi
	;;
rs)
	if command -v rustfmt &>/dev/null; then
		rustfmt "$FILE_PATH" 2>&1 >/dev/null || echo "rustfmt failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("rustfmt ($(install_hint rustfmt))")
	fi
	;;
sh | bash)
	if command -v shfmt &>/dev/null; then
		shfmt -w "$FILE_PATH" 2>&1 >/dev/null || echo "shfmt failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("shfmt ($(install_hint shfmt))")
	fi
	;;
c | h | cpp | cc | cxx | hpp | m | mm)
	if command -v clang-format &>/dev/null; then
		clang-format -i "$FILE_PATH" 2>&1 >/dev/null || echo "clang-format failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("clang-format ($(install_hint clang-format))")
	fi
	;;
java)
	if command -v google-java-format &>/dev/null; then
		google-java-format --replace "$FILE_PATH" 2>&1 >/dev/null || echo "google-java-format failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("google-java-format ($(install_hint google-java-format))")
	fi
	;;
kt | kts)
	if command -v ktfmt &>/dev/null; then
		ktfmt "$FILE_PATH" 2>&1 >/dev/null || echo "ktfmt failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("ktfmt ($(install_hint ktfmt))")
	fi
	;;
swift)
	if command -v swift-format &>/dev/null; then
		swift-format -i "$FILE_PATH" 2>&1 >/dev/null || echo "swift-format failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("swift-format ($(install_hint swift-format))")
	fi
	;;
dart)
	if command -v dart &>/dev/null; then
		dart format "$FILE_PATH" 2>&1 >/dev/null || echo "dart format failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("dart ($(install_hint dart))")
	fi
	;;
rb)
	if command -v rubocop &>/dev/null; then
		rubocop --autocorrect --silence-deprecations "$FILE_PATH" 2>&1 >/dev/null || echo "rubocop failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("rubocop ($(install_hint rubocop))")
	fi
	;;
php)
	if command -v php-cs-fixer &>/dev/null; then
		php-cs-fixer fix "$FILE_PATH" --quiet 2>&1 >/dev/null || echo "php-cs-fixer failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("php-cs-fixer ($(install_hint php-cs-fixer))")
	fi
	;;
lua)
	if command -v stylua &>/dev/null; then
		stylua "$FILE_PATH" 2>&1 >/dev/null || echo "stylua failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("stylua ($(install_hint stylua))")
	fi
	;;
zig)
	if command -v zig &>/dev/null; then
		zig fmt "$FILE_PATH" 2>&1 >/dev/null || echo "zig fmt failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("zig ($(install_hint zig))")
	fi
	;;
esac

# Run linter --fix on JS/TS files (after formatter so linter rules win on conflicts)
case "$EXTENSION" in
js | jsx | ts | tsx)
	if command -v biome &>/dev/null; then
		biome check --fix "$FILE_PATH" 2>&1 >/dev/null || echo "biome check failed on $FILE_PATH" >&2
	elif command -v eslint &>/dev/null; then
		eslint --fix "$FILE_PATH" 2>&1 >/dev/null || echo "eslint failed on $FILE_PATH" >&2
	else
		MISSING_TOOLS+=("eslint ($(install_hint eslint))")
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
