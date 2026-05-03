# Claude Code Hooks Baseline

A drop-in `.claude/` directory that adds safety guardrails, auto-formatting, audit logging, desktop notifications, test verification, and a full multi-agent orchestration system to any project. Copy it into your repo and start coding.

## What's Included

```
.claude/
├── settings.json            # Hook configuration (events, matchers, timeouts)
├── agents/                  # Orchestrator + 10 specialist agents
│   ├── orchestrator.md      # Default agent — routes all tasks to specialists
│   ├── code-reviewer.md     # Correctness, security, style, performance review
│   ├── security-auditor.md  # Secrets, injection vectors, CVEs, auth gaps
│   ├── doc-writer.md        # TSDoc, module docs, README sections
│   ├── test-writer.md       # Unit and integration test generation
│   ├── refactor.md          # Structure, naming, complexity cleanup
│   ├── debugger.md          # Root cause analysis and fix proposals
│   ├── code-humanizer.md    # Readability, naming clarity, complexity reduction
│   ├── dependency-auditor.md # Outdated, vulnerable, and abandoned packages
│   ├── performance-reviewer.md # N+1, re-renders, unoptimized loops
│   └── migration-planner.md # DB migrations, breaking changes, version bumps
└── hooks/
    ├── json-helper.sh       # Shared JSON parser — python3 with jq fallback
    ├── validate-bash.sh     # PreToolUse      — blocks destructive and user-intent commands
    ├── guard-files.sh       # PreToolUse      — blocks writes to protected files
    ├── format.sh            # PostToolUse     — auto-formats files after every write
    ├── session-init.sh      # SessionStart    — logs project context and detects tooling
    ├── audit-prompt.sh      # UserPromptSubmit — logs prompts with secret redaction
    ├── notify.sh            # Notification    — desktop alerts when Claude needs input
    ├── audit-config.sh      # ConfigChange    — logs settings/skills file changes
    └── post-run-tests.sh    # Stop            — runs type-checking and tests when Claude finishes
```

## Hook Lifecycle

Hooks fire at specific points in Claude Code's lifecycle. This baseline covers 7 of the available events:

```
SessionStart ──► UserPromptSubmit ──► PreToolUse ──► [tool runs] ──► PostToolUse
                                                                         │
Notification (anytime Claude waits) ◄────────────────────────────────────┘
ConfigChange (anytime settings change)                                    │
                                                                    Stop ◄┘
```

## Agents

The `agents/` directory provides an orchestrator and 10 specialist agents. The orchestrator is the default agent for all tasks — it reads each request, routes to the appropriate specialists (in parallel where possible), and synthesizes their outputs into a single response.

### How it works

The orchestrator handles two execution modes depending on whether the specialists are independent or dependent on each other's output.

**Parallel** — independent tasks run simultaneously:

```
User request
    │
    ▼
orchestrator
    │
    ├──► code-reviewer        ──┐
    ├──► security-auditor     ──┤
    └──► dependency-auditor   ──┘
                                │
                                ▼
                        synthesized response
```

**Pipeline** — dependent tasks run sequentially, each receiving the previous agent's full output as context:

```
User request ("refactor and test")
    │
    ▼
orchestrator
    │
    ▼
refactor ──► (output) ──► code-reviewer ──► (output) ──► test-writer
                                                              │
                                                              ▼
                                                      synthesized response
```

Built-in pipelines:

| Pipeline            | Trigger                                    | Steps                                        |
| ------------------- | ------------------------------------------ | -------------------------------------------- |
| Improve             | "clean up", "refactor and review"          | `refactor` → `code-reviewer`                 |
| Full improvement    | "refactor and test", "clean up with tests" | `refactor` → `code-reviewer` → `test-writer` |
| Fix and verify      | "fix this bug", "debug and test"           | `debugger` → `test-writer`                   |
| Humanize and verify | "make readable", "humanize and check"      | `code-humanizer` → `code-reviewer`           |
| Plan and review     | "plan this migration", "plan and validate" | `migration-planner` → `code-reviewer`        |

The orchestrator never writes or edits code itself. All file modifications go through specialists, and every tool call passes through the existing hooks — `validate-bash.sh` and `guard-files.sh` fire regardless of which agent is active.

### Agents

| Agent                  | Model                     | Effort | Permission | Tools                         | Purpose                                                   |
| ---------------------- | ------------------------- | ------ | ---------- | ----------------------------- | --------------------------------------------------------- |
| `orchestrator`         | claude-sonnet-4-6         | low    | default    | Read, Grep, Agent             | Routes all tasks to specialists. Default for the project. |
| `code-reviewer`        | claude-sonnet-4-6         | low    | plan       | Read, Grep                    | Correctness, security, style, performance review          |
| `security-auditor`     | claude-sonnet-4-6         | low    | plan       | Read, Grep, Bash              | Secrets, injection vectors, CVEs, auth gaps               |
| `doc-writer`           | claude-haiku-4-5-20251001 | low    | default    | Read, Grep, Edit, Write       | TSDoc, module docs, README sections                       |
| `test-writer`          | claude-sonnet-4-6         | medium | default    | Read, Grep, Edit, Write, Bash | Unit and integration test generation                      |
| `refactor`             | claude-sonnet-4-6         | low    | default    | Read, Grep, Edit              | Structure, naming, complexity cleanup                     |
| `debugger`             | claude-opus-4-7           | high   | default    | Read, Grep, Bash              | Root cause analysis and fix proposals                     |
| `code-humanizer`       | claude-sonnet-4-6         | medium | default    | Read, Grep, Edit              | Naming clarity, readability, complexity reduction         |
| `dependency-auditor`   | claude-haiku-4-5-20251001 | low    | plan       | Read, Bash                    | Outdated, vulnerable, and abandoned package scanning      |
| `performance-reviewer` | claude-haiku-4-5-20251001 | low    | plan       | Read, Grep                    | N+1, re-renders, unoptimized loops, missing pagination    |
| `migration-planner`    | claude-opus-4-7           | medium | plan       | Read, Grep                    | DB migrations, breaking API changes, version bump plans   |

### Safety model

Agents do not bypass hooks. Every Bash call passes through `validate-bash.sh` (blocks destructive commands, intercepts user-intent commands). Every file write passes through `guard-files.sh` (blocks `.env`, lockfiles, secrets, out-of-project paths) and then through `format.sh`. Agents are constrained at two layers:

- **Tool lists** — each agent declares only the tools it needs. `code-reviewer` and `performance-reviewer` have no write tools and cannot modify files.
- **`permissionMode: plan`** — five read-only agents (`code-reviewer`, `security-auditor`, `performance-reviewer`, `migration-planner`, `dependency-auditor`) run in plan mode, which enforces read-only access at the runtime level independent of the tool list.

The orchestrator builds persistent cross-session memory at `.claude/agent-memory/orchestrator/` (gitignored). This lets it learn codebase patterns and routing preferences over time without shipping user-specific context when the baseline is shared.

### Invoking agents directly

You can bypass the orchestrator and call a specialist directly:

```
@code-reviewer review the auth changes
@security-auditor scan for secrets
@migration-planner plan the users table rename
```

## Hooks

### `validate-bash.sh` (PreToolUse → Bash)

Intercepts every Bash command before execution. Commands are split into two categories:

**User-intent commands** — not destructive, but should never run autonomously. When blocked, the user sees the exact command to run themselves:

```
BLOCKED: 'git push' requires explicit user intent.
Run it yourself with:  ! git push -u origin main
```

| Category   | Patterns                                                                   |
| ---------- | -------------------------------------------------------------------------- |
| Git push   | `git push` (all variants including `--force`, `-f`, `-u`)                  |
| Publishing | `npm publish`, `yarn publish`, `cargo publish`, `twine upload`, `gem push` |

**Destructive commands** — always blocked with no workaround:

| Category    | Patterns                                                   |
| ----------- | ---------------------------------------------------------- |
| Filesystem  | `rm -rf`, `mkfs.`, `dd if=`, `> /dev/sda`, fork bombs      |
| Database    | `DROP TABLE`, `DROP DATABASE`                              |
| Git         | `reset --hard`, `clean -fd`, `clean -fx`, `checkout -- .`  |
| Permissions | `chmod -R 777 /`, `chmod 777 /`                            |
| Remote exec | `curl \| bash`, `curl \| sh`, `wget \| bash`, `wget \| sh` |

All patterns are matched case-insensitively as substrings.

### `guard-files.sh` (PreToolUse → Write, Edit, NotebookEdit)

Prevents Claude from writing to files that should never be directly edited.

- **Environment files** — `.env`, `.env.*`
- **Lockfiles** — `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`, `Cargo.lock`, `composer.lock` (each with a message suggesting the correct package manager command)
- **Secret/key files** — `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`
- **Credentials** — `credentials`, `credentials.*`, `*_credentials.*`, `service-account*.json`
- **Git internals** — anything inside `.git/`
- **Out-of-project writes** — any path outside `$CLAUDE_PROJECT_DIR`

### `format.sh` (PostToolUse → Write, Edit, NotebookEdit)

Auto-formats files after every write using whatever formatter is available on your system.

| Extension                                              | Formatter (preference order)   | Linter                        |
| ------------------------------------------------------ | ------------------------------ | ----------------------------- |
| js, jsx, ts, tsx, json, css, scss, md, html, yaml, yml | Biome → Prettier               | Biome → ESLint (js/ts only)   |
| py                                                     | Ruff → Black → autopep8 → YAPF | Ruff (via `ruff check --fix`) |
| go                                                     | gofmt                          | —                             |
| rs                                                     | rustfmt                        | —                             |
| sh, bash                                               | shfmt                          | —                             |
| c, h, cpp, cc, cxx, hpp, m, mm                         | clang-format                   | —                             |
| java                                                   | google-java-format             | —                             |
| kt, kts                                                | ktfmt                          | —                             |
| swift                                                  | swift-format                   | —                             |
| dart                                                   | dart format                    | —                             |
| rb                                                     | RuboCop                        | —                             |
| php                                                    | php-cs-fixer                   | —                             |
| lua                                                    | StyLua                         | —                             |
| zig                                                    | zig fmt                        | —                             |

The hook uses the first available formatter in the preference chain. When no formatter is found, a non-interruptive hint is shown via `systemMessage` with a **platform-aware install command** (macOS/Linux/Windows):

```
Auto-format skipped — missing: biome (npm i -g @biomejs/biome)
```

This is displayed to the user in the UI but **not fed to Claude** — it won't interrupt the workflow or trigger Claude to install anything. Type-checking (`tsc --noEmit`) is intentionally not run here since it checks the entire project per file save; it runs once in the Stop hook instead.

### `session-init.sh` (SessionStart)

Runs when a Claude Code session begins (new session, resume, clear, or compaction). Outputs project context and detected tooling:

```
Session initialized
  Project: /path/to/your/project
  Branch:  main
  Env:     development
  Tools:   prettier eslint tsc
  Stack:   node
  Agents:
    code-humanizer (claude-sonnet-4-6, medium)
    code-reviewer (claude-sonnet-4-6, low)
    debugger (claude-opus-4-7, high)
    dependency-auditor (claude-haiku-4-5-20251001, low)
    doc-writer (claude-haiku-4-5-20251001, low)
    migration-planner (claude-opus-4-7, medium)
    orchestrator (claude-sonnet-4-6, low)
    performance-reviewer (claude-haiku-4-5-20251001, low)
    refactor (claude-sonnet-4-6, low)
    security-auditor (claude-sonnet-4-6, low)
    test-writer (claude-sonnet-4-6, medium)
```

- **Project root** — from `git rev-parse --show-toplevel` or `pwd`
- **Git branch** — current branch or `detached`
- **Environment** — `$NODE_ENV` (defaults to `development`)
- **Available tools** — scans for `biome`, `prettier`, `eslint`, `tsc`, `ruff`, `black`, `autopep8`, `yapf`, `gofmt`, `rustfmt`, `shfmt`, `clang-format`, `google-java-format`, `ktfmt`, `swift-format`, `dart`, `rubocop`, `php-cs-fixer`, `stylua`, `zig`, `cargo`
- **Project type** — detected from manifest files (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`)
- **Loaded agents** — scans `.claude/agents/` and lists each agent with its model and effort level

Exports `PROJECT_ROOT`, `GIT_BRANCH`, and `NODE_ENV` into `$CLAUDE_ENV_FILE` when available. Warns if neither `python3` nor `jq` is found (all other hooks would be disabled).

### `audit-prompt.sh` (UserPromptSubmit)

Logs every prompt with a UTC timestamp and session ID to `.claude/logs/prompts.log` (gitignored). Before logging, prompts are scrubbed through a redaction filter that replaces known secret patterns with `[REDACTED]`:

| Pattern                 | Examples                                                                                                     |
| ----------------------- | ------------------------------------------------------------------------------------------------------------ |
| OpenAI / Anthropic keys | `sk-proj-abc123...`                                                                                          |
| GitHub tokens           | `ghp_*`, `gho_*`, `github_pat_*`                                                                             |
| Slack tokens            | `xoxb-*`, `xoxp-*`, `xoxa-*`                                                                                 |
| AWS access keys         | `AKIA*`                                                                                                      |
| JWTs                    | `eyJ*.*`                                                                                                     |
| PEM private keys        | `-----BEGIN * KEY-----`                                                                                      |
| Generic secrets         | any value assigned to a variable containing `secret`, `token`, `key`, `password`, `credential`, or `api_key` |

Warns (but does not block) if a prompt contains patterns like `rm -rf` or `DROP TABLE` — these are natural language, not commands, so blocking would be too aggressive.

### `notify.sh` (Notification)

Sends a native desktop notification when Claude needs your input — permission prompts, idle state, or auth dialogs. Uses the notification title and message from Claude Code's event data. Auto-detects the platform:

- **macOS** — uses `osascript` (routes through Script Editor; you may need to enable notifications for Script Editor in System Settings > Notifications)
- **Linux** — uses `notify-send` (requires `libnotify`: `sudo apt install libnotify-bin`)
- **Windows** — not supported (WSL users can add a PowerShell notification call in the script)

This lets you switch to other tasks while Claude works and get alerted when it's waiting.

### `audit-config.sh` (ConfigChange)

Logs every settings or skills file change to `.claude/logs/config-changes.log` (gitignored) with timestamp, session ID, source type, and file path. Fires when any configuration file is modified during a session:

| Source             | File                             |
| ------------------ | -------------------------------- |
| `user_settings`    | `~/.claude/settings.json`        |
| `project_settings` | `.claude/settings.json`          |
| `local_settings`   | `.claude/settings.local.json`    |
| `policy_settings`  | managed policy settings          |
| `skills`           | skill files in `.claude/skills/` |

### `post-run-tests.sh` (Stop)

Runs when Claude finishes a response. Skips entirely if no files were modified during the session (checked via `git diff` and `git ls-files`).

When files have changed:

1. **TypeScript type-check** — runs `tsc --noEmit` if `tsconfig.json` exists (warns on errors, does not block)
2. **Test suite** — auto-detects and runs the appropriate runner:
   - **Node.js** → `npm test` (if a `test` script exists in `package.json`)
   - **Python** → `pytest --tb=short`
   - **Go** → `go test ./...`

All commands run with a **120-second timeout** (uses `timeout` on Linux, `gtimeout` on macOS) to prevent hanging test suites from blocking the session. The hook timeout in `settings.json` is set to 150 seconds to accommodate.

**Infinite loop protection:** When a Stop hook exits with code 2 (test failure), Claude continues working to fix the issue, then stops again — which fires the Stop hook again. To prevent infinite loops, the hook checks the `stop_hook_active` field from the JSON input and exits immediately if `true`. This is a [required pattern](https://code.claude.com/docs/en/hooks-guide#stop-hook-runs-forever) for any Stop hook that can block.

## Shared JSON Parser

All hooks parse Claude Code's JSON input using `json-helper.sh`, a shared helper that requires **no external dependencies**:

1. **python3** (primary) — uses the built-in `json` module. Ships with macOS (since Catalina) and virtually all Linux distros
2. **jq** (fallback) — used only if python3 is unavailable
3. **Neither available** — returns empty string; hooks exit gracefully (no-op)

Usage in hook scripts:

```bash
source "$SCRIPT_DIR/json-helper.sh"
INPUT=$(cat)
VALUE=$(json_get "$INPUT" '.tool_input.command')
```

## Installation

### Quick Start

```bash
# Clone into a temporary location
git clone https://github.com/MokeyBytes/claude-baseline.git /tmp/claude-baseline

# Copy into your project
cp -r /tmp/claude-baseline/.claude /path/to/your/project/

# Clean up
rm -rf /tmp/claude-baseline
```

### Manual

Copy the `.claude/` directory (with `settings.json` and the `hooks/` folder) into the root of any project.

### Verify

Start a Claude Code session in your project. You should see the session initialization output including all loaded agents:

```
Session initialized
  Project: /path/to/your/project
  Branch:  main
  Env:     development
  Tools:   prettier eslint tsc
  Stack:   node
  Agents:
    code-humanizer (claude-sonnet-4-6, medium)
    code-reviewer (claude-sonnet-4-6, low)
    debugger (claude-opus-4-7, high)
    ...
```

Type `/hooks` to confirm hooks are loaded and `/agents` to list all available agents.

## Dependencies

### Required

- **bash** (4.0+) — all hooks are bash scripts
- **python3** — parses JSON input via the built-in `json` module. Ships with macOS (since Catalina) and virtually all Linux distros. Falls back to `jq` if unavailable. If neither is found, `session-init.sh` prints a warning and all other hooks silently no-op
- **git** — used by `session-init.sh` and `post-run-tests.sh` to detect project root and changed files

### Optional (formatting)

Install whichever formatters apply to your stack. Missing tools trigger a non-interruptive `systemMessage` hint.

| Tool                                                               | macOS                                               | Linux                        | Windows                  |
| ------------------------------------------------------------------ | --------------------------------------------------- | ---------------------------- | ------------------------ |
| [Biome](https://biomejs.dev/)                                      | `npm i -g @biomejs/biome`                           | (same)                       | (same)                   |
| [Prettier](https://prettier.io/)                                   | `npm i -g prettier`                                 | (same)                       | (same)                   |
| [ESLint](https://eslint.org/)                                      | `npm i -g eslint`                                   | (same)                       | (same)                   |
| [TypeScript](https://www.typescriptlang.org/)                      | `npm i -g typescript`                               | (same)                       | (same)                   |
| [Ruff](https://docs.astral.sh/ruff/)                               | `brew install ruff`                                 | `pip install ruff`           | `pip install ruff`       |
| [Black](https://black.readthedocs.io/)                             | `pip install black`                                 | (same)                       | (same)                   |
| [gofmt](https://pkg.go.dev/cmd/gofmt)                              | `brew install go`                                   | `apt install golang`         | `choco install golang`   |
| [rustfmt](https://github.com/rust-lang/rustfmt)                    | `rustup component add rustfmt`                      | (same)                       | (same)                   |
| [shfmt](https://github.com/mvdan/sh)                               | `brew install shfmt`                                | `apt install shfmt`          | `choco install shfmt`    |
| [clang-format](https://clang.llvm.org/docs/ClangFormat.html)       | `brew install clang-format`                         | `apt install clang-format`   | `choco install llvm`     |
| [google-java-format](https://github.com/google/google-java-format) | `brew install google-java-format`                   | GitHub releases              | GitHub releases          |
| [ktfmt](https://github.com/facebook/ktfmt)                         | `brew install ktfmt`                                | GitHub releases              | GitHub releases          |
| [swift-format](https://github.com/swiftlang/swift-format)          | `brew install swift-format`                         | GitHub releases              | GitHub releases          |
| [Dart](https://dart.dev/)                                          | `brew install dart`                                 | `apt install dart`           | `choco install dart-sdk` |
| [RuboCop](https://rubocop.org/)                                    | `gem install rubocop`                               | (same)                       | (same)                   |
| [php-cs-fixer](https://cs.symfony.com/)                            | `composer global require friendsofphp/php-cs-fixer` | (same)                       | (same)                   |
| [StyLua](https://github.com/JohnnyMorganz/StyLua)                  | `brew install stylua`                               | `cargo install stylua`       | `cargo install stylua`   |
| [Zig](https://ziglang.org/)                                        | `brew install zig`                                  | `snap install zig --classic` | `choco install zig`      |

### Optional (notifications)

- **macOS** — no install needed (`osascript` is built-in). Enable notifications for Script Editor in System Settings > Notifications
- **Linux** — `sudo apt install libnotify-bin` (for `notify-send`)

### Optional (test timeout)

The Stop hook wraps test commands in a timeout to prevent hangs:

- **Linux** — uses `timeout` (included in coreutils)
- **macOS** — uses `gtimeout` from GNU coreutils: `brew install coreutils`

If neither is available, tests run without a timeout.

## Customization

### Adding protected files

Edit `guard-files.sh` and add entries to the lockfile `case` block or the secret file extension `case` block.

### Adding blocked commands

Edit `validate-bash.sh` and add patterns to the `BLOCKED_PATTERNS` array (always blocked) or `USER_INTENT_PATTERNS` array (blocked with a "run it yourself" message).

### Adding formatters

Edit `format.sh` and add a new `case` block for your file extension and formatter.

### Changing test timeout

Edit `post-run-tests.sh` and change the `TEST_TIMEOUT` variable (default: 120 seconds). Also update the `timeout` value in `settings.json` for the Stop hook if you set it higher.

### Disabling a hook

Remove or comment out the corresponding entry in `.claude/settings.json`. The hook scripts can stay in place.

### Disabling all hooks

Add `"disableAllHooks": true` to your `settings.json` to disable every hook at once.

### Adding or replacing agents

Add a `.md` file to `.claude/agents/` with YAML frontmatter defining `name`, `description`, `tools`, `model`, and `effort`. The orchestrator will automatically include it in its routing table on the next session — no changes to `settings.json` required.

To replace a specialist, delete or rename its `.md` file and add your own with the same `name` field.

### Adjusting model or effort per agent

Edit the `model` and `effort` fields in the relevant agent's frontmatter. Valid effort values: `low`, `medium`, `high`, `xhigh`, `max`. Changes take effect immediately on the next session.

## Project Structure

```
.claude/
├── settings.json            # Hook wiring — events, matchers, timeouts
├── agents/                  # Orchestrator + 10 specialist agents
│   ├── orchestrator.md      # Default — routes and pipelines all tasks
│   ├── code-reviewer.md
│   ├── security-auditor.md
│   ├── doc-writer.md
│   ├── test-writer.md
│   ├── refactor.md
│   ├── debugger.md
│   ├── code-humanizer.md
│   ├── dependency-auditor.md
│   ├── performance-reviewer.md
│   └── migration-planner.md
├── hooks/                   # All hook scripts (bash, executable)
│   ├── json-helper.sh       # Shared JSON parser (sourced by all hooks)
│   ├── validate-bash.sh
│   ├── guard-files.sh
│   ├── format.sh
│   ├── session-init.sh
│   ├── audit-prompt.sh
│   ├── notify.sh
│   ├── audit-config.sh
│   └── post-run-tests.sh
├── logs/                    # Gitignored — created at runtime
│   └── .gitkeep
└── agent-memory/            # Gitignored — orchestrator cross-session memory
```

## License

MIT
