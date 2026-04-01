# Claude Code Hooks Baseline

A drop-in set of [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that add safety guardrails, auto-formatting, and test verification to any project. Copy the `.claude/` directory into your repo and start coding.

## What's Included

```
.claude/
├── settings.json            # Hook configuration (matchers, timeouts)
└── hooks/
    ├── validate-bash.sh     # PreToolUse  — blocks destructive shell commands
    ├── guard-files.sh       # PreToolUse  — blocks writes to protected files
    ├── format.sh            # PostToolUse — auto-formats files after every write
    ├── session-init.sh      # SessionStart — logs project context and detects tooling
    ├── audit-prompt.sh      # UserPromptSubmit — logs prompts with timestamps
    └── post-run-tests.sh    # Stop — runs type-checking and tests when Claude finishes
```

## Hooks

### `validate-bash.sh` (PreToolUse → Bash)

Blocks dangerous shell commands before they execute.

| Category | Blocked Patterns |
|----------|-----------------|
| Filesystem | `rm -rf`, `mkfs.`, `dd if=`, `> /dev/sda`, fork bombs |
| Database | `DROP TABLE`, `DROP DATABASE` |
| Git | `push --force`, `push -f`, `reset --hard`, `clean -fd`, `clean -fx`, `checkout -- .` |
| Permissions | `chmod -R 777 /`, `chmod 777 /` |
| Remote exec | `curl \| bash`, `curl \| sh`, `wget \| bash`, `wget \| sh` |
| Publishing | `npm publish`, `yarn publish`, `cargo publish`, `twine upload`, `gem push` |

### `guard-files.sh` (PreToolUse → Write, Edit, MultiEdit, NotebookEdit)

Prevents Claude from writing to files that should never be directly edited.

- **Environment files** — `.env`, `.env.*`
- **Lockfiles** — `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`, `Cargo.lock`, `composer.lock`
- **Secret/key files** — `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`
- **Credentials** — `credentials`, `credentials.*`, `*_credentials.*`, `service-account*.json`
- **Git internals** — anything inside `.git/`
- **Out-of-project writes** — any path outside `$CLAUDE_PROJECT_DIR`

### `format.sh` (PostToolUse → Write, Edit, MultiEdit, NotebookEdit)

Auto-formats files after every write using whatever formatter is available on your system.

| Extension | Formatter | Linter |
|-----------|-----------|--------|
| js, jsx, ts, tsx, json, css, scss, md, html, yaml, yml | Prettier | ESLint (js/ts only) |
| py | Black | — |
| go | gofmt | — |

All formatters are optional — if a tool isn't installed, the hook silently skips it.

### `session-init.sh` (SessionStart)

Runs when a Claude Code session begins. Outputs:

- **Project root** — from `git rev-parse` or `pwd`
- **Git branch** — current branch or "detached"
- **Environment** — `$NODE_ENV` (defaults to `development`)
- **Available tools** — scans for `prettier`, `eslint`, `tsc`, `black`, `ruff`, `gofmt`, `rustfmt`, `cargo`
- **Project type** — detected from manifest files (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`)

Also exports `PROJECT_ROOT`, `GIT_BRANCH`, and `NODE_ENV` into `$CLAUDE_ENV_FILE` when available.

### `audit-prompt.sh` (UserPromptSubmit)

Logs every prompt with a UTC timestamp and session ID to `.claude/logs/prompts.log` (gitignored). Before logging, prompts are scrubbed through a redaction filter that replaces known secret patterns with `[REDACTED]`:

- **OpenAI / Anthropic** — `sk-*` prefixed keys
- **GitHub** — `ghp_*`, `gho_*`, `github_pat_*` tokens
- **Slack** — `xox[bposatr]-*` tokens
- **AWS** — `AKIA*` access key IDs
- **JWTs** — `eyJ*` encoded tokens
- **PEM keys** — `-----BEGIN * KEY-----`
- **Generic** — any value assigned to a variable containing `secret`, `token`, `key`, `password`, `credential`, or `api_key`

Warns (but does not block) if a prompt contains patterns like `rm -rf` or `DROP TABLE` — these are natural language, not commands, so blocking would be too aggressive.

### `post-run-tests.sh` (Stop)

Runs when Claude finishes a response. Skips entirely if no files were modified (checked via `git diff` and `git ls-files`).

When files have changed:
1. **TypeScript type-check** — runs `tsc --noEmit` if `tsconfig.json` exists (warns on errors, does not block)
2. **Test suite** — auto-detects and runs the appropriate runner:
   - Node.js → `npm test` (if a `test` script exists in `package.json`)
   - Python → `pytest --tb=short`
   - Go → `go test ./...`

All commands run with a **120-second timeout** (uses `timeout` on Linux, `gtimeout` on macOS) to prevent hanging test suites from blocking the session. The hook timeout in `settings.json` is set to 150 seconds to accommodate.

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

Start a Claude Code session in your project. You should see output like:

```
Session initialized
  Project: /path/to/your/project
  Branch:  main
  Env:     development
  Tools:   prettier eslint tsc
  Stack:   node
```

## Dependencies

### Required

- **bash** (4.0+) — all hooks are bash scripts
- **jq** — parses JSON input from Claude Code. If `jq` is not installed, all hooks exit gracefully (no-op)
- **git** — used by `session-init.sh` and `post-run-tests.sh` to detect project root and changed files

### Optional (formatting)

Install whichever formatters apply to your stack. Hooks skip any tool that isn't found.

| Tool | Install | Used By |
|------|---------|---------|
| [Prettier](https://prettier.io/) | `npm i -g prettier` | `format.sh` |
| [ESLint](https://eslint.org/) | `npm i -g eslint` | `format.sh` |
| [TypeScript](https://www.typescriptlang.org/) | `npm i -g typescript` | `post-run-tests.sh` |
| [Black](https://black.readthedocs.io/) | `pip install black` | `format.sh` |
| [gofmt](https://pkg.go.dev/cmd/gofmt) | included with Go | `format.sh` |

### Optional (test timeout)

The Stop hook wraps test commands in a timeout to prevent hangs:

- **Linux** — uses `timeout` (included in coreutils)
- **macOS** — uses `gtimeout` from GNU coreutils: `brew install coreutils`

If neither is available, tests run without a timeout.

## Customization

### Adding protected files

Edit `guard-files.sh` and add entries to the lockfile `case` block or the secret file extension `case` block.

### Adding blocked commands

Edit `validate-bash.sh` and add patterns to the `BLOCKED_PATTERNS` array. Patterns are matched case-insensitively as substrings.

### Adding formatters

Edit `format.sh` and add a new `case` block for your file extension and formatter.

### Changing test timeout

Edit `post-run-tests.sh` and change the `TEST_TIMEOUT` variable (default: 120 seconds). Also update the `timeout` value in `settings.json` for the Stop hook if you set it higher.

### Disabling a hook

Remove or comment out the corresponding entry in `.claude/settings.json`. The hook scripts can stay in place.

## Project Structure

```
.claude/
├── settings.json       # Hook wiring — which scripts run on which events
├── hooks/              # All hook scripts (bash, executable)
│   ├── validate-bash.sh
│   ├── guard-files.sh
│   ├── format.sh
│   ├── session-init.sh
│   ├── audit-prompt.sh
│   └── post-run-tests.sh
└── logs/               # Created at runtime, gitignored
    └── prompts.log     # Prompt audit log
```

## License

MIT
