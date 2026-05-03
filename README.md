# Claude Code Baseline

A drop-in `.claude/` configuration that adds safety guardrails, auto-formatting, audit logging, desktop notifications, automated testing, and a full multi-agent orchestration system to any project. Copy it in and start coding.

---

## What It Does

| Layer             | What you get                                                                  |
| ----------------- | ----------------------------------------------------------------------------- |
| **Safety**        | Blocks destructive commands and writes to sensitive files before they execute |
| **Formatting**    | Auto-formats every file Claude writes, across 15+ languages                   |
| **Observability** | Logs every prompt (with secret redaction) and every config change             |
| **Notifications** | Desktop alerts when Claude needs your input                                   |
| **Verification**  | Runs type-checking and tests automatically when Claude finishes               |
| **Agents**        | Orchestrator + 10 specialist agents with parallel and pipeline execution      |

---

## Quick Start

```bash
git clone https://github.com/MokeyBytes/claude-baseline.git /tmp/claude-baseline
cp -r /tmp/claude-baseline/.claude /path/to/your/project/
rm -rf /tmp/claude-baseline
```

Open a Claude Code session in your project. You should see:

```
Session initialized
  Project: /path/to/your/project
  Branch:  main
  Env:     development
  Tools:   prettier eslint tsc
  Agents:
    orchestrator (claude-sonnet-4-6, low)
    code-reviewer (claude-sonnet-4-6, low)
    debugger (claude-opus-4-7, high)
    ...
```

Confirm hooks are active with `/hooks` and agents with `/agents`.

---

## Project Structure

```
.claude/
├── settings.json            # Hook wiring: events, matchers, timeouts
├── agents/                  # Orchestrator + 10 specialist agents
│   ├── orchestrator.md
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
├── hooks/
│   ├── json-helper.sh       # Shared JSON parser (python3 with jq fallback)
│   ├── validate-bash.sh     # PreToolUse: blocks destructive commands
│   ├── guard-files.sh       # PreToolUse: blocks writes to protected files
│   ├── format.sh            # PostToolUse: auto-formats after every write
│   ├── session-init.sh      # SessionStart: logs project context and tooling
│   ├── audit-prompt.sh      # UserPromptSubmit: logs prompts with secret redaction
│   ├── notify.sh            # Notification: desktop alerts on idle/permission
│   ├── audit-config.sh      # ConfigChange: logs settings and skills changes
│   └── post-run-tests.sh    # Stop: runs type-checking and tests
├── logs/                    # Gitignored, created at runtime
└── agent-memory/            # Gitignored, orchestrator cross-session memory
```

---

## Agents

The orchestrator is the default agent for all tasks. It reads each request, routes to the appropriate specialists, and synthesizes their outputs. Specialists never bypass hooks; every Bash call and file write passes through the same safety layer regardless of which agent is active.

### Specialist Roster

| Agent                  | Model             | Effort | Mode    | Purpose                                                      |
| ---------------------- | ----------------- | ------ | ------- | ------------------------------------------------------------ |
| `orchestrator`         | claude-sonnet-4-6 | low    | default | Routes all tasks to specialists. Never writes code directly. |
| `code-reviewer`        | claude-sonnet-4-6 | low    | plan    | Correctness, security, style, and performance review         |
| `security-auditor`     | claude-sonnet-4-6 | low    | plan    | Secrets, injection vectors, CVEs, auth gaps                  |
| `doc-writer`           | claude-haiku-4-5  | low    | default | TSDoc, module docs, README sections                          |
| `test-writer`          | claude-sonnet-4-6 | medium | default | Unit and integration test generation                         |
| `refactor`             | claude-sonnet-4-6 | low    | default | Structure, naming, and complexity cleanup                    |
| `debugger`             | claude-opus-4-7   | high   | default | Root cause analysis and fix proposals                        |
| `code-humanizer`       | claude-sonnet-4-6 | medium | default | Naming clarity, readability, complexity reduction            |
| `dependency-auditor`   | claude-haiku-4-5  | low    | plan    | Outdated, vulnerable, and abandoned package scanning         |
| `performance-reviewer` | claude-haiku-4-5  | low    | plan    | N+1, re-renders, unoptimized loops, missing pagination       |
| `migration-planner`    | claude-opus-4-7   | medium | plan    | DB migrations, breaking API changes, version bumps           |

`plan` mode enforces read-only access at the runtime level independent of the tool list.

### Execution Modes

**Parallel:** independent specialists run simultaneously:

```
request → orchestrator → code-reviewer     ─┐
                       → security-auditor   ─┤→ synthesized response
                       → dependency-auditor ─┘
```

**Pipeline:** dependent specialists run sequentially, each receiving the previous output as full context:

```
"refactor and test" → orchestrator → refactor → code-reviewer → test-writer → response
```

### Built-in Pipelines

| Pipeline            | Trigger phrases                            | Steps                                        |
| ------------------- | ------------------------------------------ | -------------------------------------------- |
| Improve             | "clean up", "refactor and review"          | `refactor` → `code-reviewer`                 |
| Full improvement    | "refactor and test", "clean up with tests" | `refactor` → `code-reviewer` → `test-writer` |
| Fix and verify      | "fix this bug", "debug and test"           | `debugger` → `test-writer`                   |
| Humanize and verify | "make readable", "humanize and check"      | `code-humanizer` → `code-reviewer`           |
| Plan and review     | "plan this migration", "plan and validate" | `migration-planner` → `code-reviewer`        |

### Invoking Specialists Directly

```
@code-reviewer review the auth changes
@security-auditor scan for secrets
@debugger why is this test flaking
```

The orchestrator also builds persistent cross-session memory at `.claude/agent-memory/` (gitignored), so it learns codebase patterns and routing preferences over time.

---

## Hooks

Hooks fire at fixed points in the Claude Code lifecycle:

```
SessionStart → UserPromptSubmit → PreToolUse → [tool] → PostToolUse
                                                              │
           Notification (whenever Claude waits) ◄────────────┘
           ConfigChange (whenever settings change)            │
                                                        Stop ◄┘
```

### `validate-bash.sh` (PreToolUse: Bash)

Intercepts every Bash command before execution. Splits patterns into two categories:

**User-intent commands:** not destructive, but should never run autonomously. Claude is blocked and shown the exact command to run manually:

```
BLOCKED: 'git push' requires explicit user intent.
Run it yourself with:  ! git push -u origin main
```

| Category   | Blocked patterns                                                           |
| ---------- | -------------------------------------------------------------------------- |
| Git push   | `git push` (all variants including `--force`, `-f`, `-u`)                  |
| Publishing | `npm publish`, `yarn publish`, `cargo publish`, `twine upload`, `gem push` |

**Destructive commands:** always blocked with no workaround:

| Category    | Blocked patterns                                          |
| ----------- | --------------------------------------------------------- |
| Filesystem  | `rm -rf`, `mkfs.`, `dd if=`, `> /dev/sda`, fork bombs     |
| Database    | `DROP TABLE`, `DROP DATABASE`                             |
| Git         | `reset --hard`, `clean -fd`, `clean -fx`, `checkout -- .` |
| Permissions | `chmod -R 777 /`, `chmod 777 /`                           |
| Remote exec | `curl \| bash`, `wget \| bash` (and `sh` variants)        |

All patterns are matched case-insensitively.

### `guard-files.sh` (PreToolUse: Write, Edit, NotebookEdit)

Prevents Claude from writing to files that should never be directly edited:

| Category       | Blocked targets                                                                                                  |
| -------------- | ---------------------------------------------------------------------------------------------------------------- |
| Environment    | `.env`, `.env.*`                                                                                                 |
| Lockfiles      | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`, `Cargo.lock`, `composer.lock` |
| Secrets        | `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`                                                        |
| Credentials    | `credentials`, `credentials.*`, `*_credentials.*`, `service-account*.json`                                       |
| Git internals  | Anything inside `.git/`                                                                                          |
| Out-of-project | Any path outside `$CLAUDE_PROJECT_DIR`                                                                           |

Lockfile blocks include the correct package manager command as a hint.

### `format.sh` (PostToolUse: Write, Edit, NotebookEdit)

Auto-formats every file Claude writes using the first available formatter in the preference chain:

| Extension                                              | Formatter                      | Linter                 |
| ------------------------------------------------------ | ------------------------------ | ---------------------- |
| js, jsx, ts, tsx, json, css, scss, md, html, yaml, yml | Biome → Prettier               | Biome → ESLint (js/ts) |
| py                                                     | Ruff → Black → autopep8 → YAPF | Ruff                   |
| go                                                     | gofmt                          | -                      |
| rs                                                     | rustfmt                        | -                      |
| sh, bash                                               | shfmt                          | -                      |
| c, h, cpp, cc, cxx, hpp                                | clang-format                   | -                      |
| java                                                   | google-java-format             | -                      |
| kt, kts                                                | ktfmt                          | -                      |
| swift                                                  | swift-format                   | -                      |
| dart                                                   | dart format                    | -                      |
| rb                                                     | RuboCop                        | -                      |
| php                                                    | php-cs-fixer                   | -                      |
| lua                                                    | StyLua                         | -                      |
| zig                                                    | zig fmt                        | -                      |

When no formatter is found, a non-interruptive `systemMessage` hint is shown in the UI with a platform-aware install command. This is never fed to Claude and never interrupts the workflow.

Type-checking (`tsc --noEmit`) is intentionally omitted here; it runs once in the Stop hook after all changes are made.

### `session-init.sh` (SessionStart)

Runs on every new session, resume, `/clear`, and compaction. Detects and outputs:

- **Project root:** via `git rev-parse --show-toplevel` or `pwd`
- **Current branch:** current branch name or `detached`
- **Environment:** from `$NODE_ENV` (defaults to `development`)
- **Available formatters/tools:** scans for 20+ tools across all supported stacks
- **Project type:** detected from `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`
- **Loaded agents:** scans `.claude/agents/` and lists each with model and effort level

Exports `PROJECT_ROOT`, `GIT_BRANCH`, and `NODE_ENV` to `$CLAUDE_ENV_FILE`. Warns if neither `python3` nor `jq` is found (all other hooks would silently no-op).

### `audit-prompt.sh` (UserPromptSubmit)

Logs every prompt with a UTC timestamp and session ID to `.claude/logs/prompts.log` (gitignored). Prompts are scrubbed through a redaction filter before logging:

| Pattern                 | Matched values                                                                     |
| ----------------------- | ---------------------------------------------------------------------------------- |
| OpenAI / Anthropic keys | `sk-proj-*`, `sk-ant-*`                                                            |
| GitHub tokens           | `ghp_*`, `gho_*`, `github_pat_*`                                                   |
| Slack tokens            | `xoxb-*`, `xoxp-*`, `xoxa-*`                                                       |
| AWS access keys         | `AKIA*`                                                                            |
| JWTs                    | `eyJ*.*`                                                                           |
| PEM private keys        | `-----BEGIN * KEY-----`                                                            |
| Generic secrets         | Variables containing `secret`, `token`, `key`, `password`, `credential`, `api_key` |

Warns (but does not block) if a prompt contains patterns like `rm -rf` or `DROP TABLE` since those are natural language, not commands.

### `notify.sh` (Notification)

Sends a native desktop notification when Claude needs your input. Platform detection:

- **macOS:** `osascript` (built-in; enable notifications for Script Editor in System Settings)
- **Linux:** `notify-send` (requires `libnotify-bin`: `sudo apt install libnotify-bin`)
- **Windows:** not supported out of the box (WSL users can add a PowerShell call in the script)

### `audit-config.sh` (ConfigChange)

Logs every settings or skills file change to `.claude/logs/config-changes.log` (gitignored) with timestamp, session ID, source type, and file path:

| Source             | File                             |
| ------------------ | -------------------------------- |
| `user_settings`    | `~/.claude/settings.json`        |
| `project_settings` | `.claude/settings.json`          |
| `local_settings`   | `.claude/settings.local.json`    |
| `policy_settings`  | Managed policy settings          |
| `skills`           | Skill files in `.claude/skills/` |

### `post-run-tests.sh` (Stop)

Runs when Claude finishes a response. Skips entirely if no files were modified (checked via `git diff` and `git ls-files`).

When files have changed:

1. **TypeScript type-check:** runs `tsc --noEmit` if `tsconfig.json` exists (warns on failure, does not block)
2. **Test suite:** auto-detects the runner:
   - Node.js: `npm test` (if a `test` script exists in `package.json`)
   - Python: `pytest --tb=short`
   - Go: `go test ./...`

All commands run with a 120-second timeout (`gtimeout` on macOS, `timeout` on Linux). If neither is available, tests run without a timeout.

**Infinite loop protection:** When a Stop hook exits with code 2, Claude re-enters to fix the issue, then stops again, re-firing the hook. The hook checks the `stop_hook_active` field and exits immediately if `true` to prevent infinite loops. This is a [required pattern](https://docs.anthropic.com/en/docs/claude-code/hooks) for any Stop hook that can block.

---

## Shared JSON Parser

All hooks parse Claude Code's JSON input via `json-helper.sh` with no external dependencies required:

1. **python3** (primary): built-in `json` module; ships with macOS (Catalina+) and all major Linux distros
2. **jq** (fallback): used only if python3 is unavailable
3. **Neither:** returns empty string; hooks exit gracefully as no-ops

Usage in any hook:

```bash
source "$SCRIPT_DIR/json-helper.sh"
INPUT=$(cat)
VALUE=$(json_get "$INPUT" '.tool_input.command')
```

---

## Dependencies

### Required

| Dependency | Purpose                                          |
| ---------- | ------------------------------------------------ |
| bash 4.0+  | All hook scripts                                 |
| python3    | JSON parsing (falls back to `jq` if unavailable) |
| git        | Project root detection and changed-file tracking |

### Optional: Formatters

Install whichever formatters apply to your stack. Missing tools produce a non-interruptive hint, never an error.

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
| [StyLua](https://github.com/JohnnyMorganz/StyLua)                  | `brew install stylua`                               | `cargo install stylua`       | (same)                   |
| [Zig](https://ziglang.org/)                                        | `brew install zig`                                  | `snap install zig --classic` | `choco install zig`      |

### Optional: Test Timeout

- **macOS:** `brew install coreutils` (provides `gtimeout`)
- **Linux:** `timeout` is included in coreutils

If neither is available, test commands run without a timeout.

---

## Customization

### Add a protected file

Edit `guard-files.sh` and add patterns to the lockfile `case` block or the secret extension `case` block.

### Add a blocked command

Edit `validate-bash.sh` and add patterns to `BLOCKED_PATTERNS` (always blocked) or `USER_INTENT_PATTERNS` (blocked with a "run it yourself" message).

### Add a formatter

Edit `format.sh` and add a `case` block for the file extension and formatter command.

### Change the test timeout

Edit the `TEST_TIMEOUT` variable in `post-run-tests.sh` (default: 120 seconds). Update the corresponding `timeout` in `settings.json` for the Stop hook if you increase it.

### Disable a single hook

Remove or comment out its entry in `.claude/settings.json`. The script can stay in place.

### Disable all hooks

Add `"disableAllHooks": true` to `.claude/settings.json`.

### Add or replace an agent

Add a `.md` file to `.claude/agents/` with YAML frontmatter defining `name`, `description`, `tools`, `model`, and `effort`. The orchestrator picks it up automatically on the next session; no changes to `settings.json` required.

To replace a specialist, delete its `.md` file and add your own with the same `name` field.

### Adjust model or effort

Edit the `model` and `effort` fields in the agent's frontmatter. Valid effort values: `low`, `medium`, `high`, `xhigh`, `max`. Takes effect on the next session.

---

## License

MIT
