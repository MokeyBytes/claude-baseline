# CLAUDE.md

This file configures Claude Code behavior for this project. It is also a
template: copy it into any new project, replace the placeholders, and delete
sections that do not apply to your stack.

---

## Project

- **Owner:** [YOUR NAME OR TEAM]
- **Stack:** [LANGUAGE / FRAMEWORK / DATABASE]
- **Package manager:** [npm / yarn / pnpm / pip / cargo / go]
- **Test runner:** [vitest / jest / pytest / go test / cargo test]
- **Formatter:** enforced automatically by `.claude/hooks/format.sh`

---

## Code Style

Keep the block that matches your stack and delete the rest.

### TypeScript / JavaScript

- Strict TypeScript; explicit return types on all exported functions
- `const` over `let`; never `var`
- async/await only; no callbacks, no raw promise chains
- Named exports only; no default exports
- Template literals over string concatenation

### Python

- Type hints on all function signatures
- PEP 8 compliance (enforced by Ruff or Black)
- f-strings over `.format()` or `%` formatting

### Go

- Standard `gofmt` style (enforced automatically)
- Errors returned and handled explicitly; never ignored with `_`
- Interfaces defined at the point of use, not the point of implementation

### Bash

- `set -euo pipefail` on every script
- `local` for all function-scoped variables
- Quote all variable expansions: `"$VAR"`, not `$VAR`
- Use `[[` not `[` for conditionals
- Snake_case function names

---

## Naming

- **TS/JS:** camelCase vars/functions, PascalCase classes/types/components
- **Python:** snake_case vars/functions, PascalCase classes
- **Booleans:** `isActive`, `hasPermission`, `canRetry`
- **Functions:** verb-noun pairs: `fetchUser()`, `parseToken()`, `validateInput()`
- No single-letter variables except loop counters (`i`, `j`, `k`)
- Banned names: `data`, `info`, `tmp`, `flag`, `val`, `obj`, `result`
- Names are self-documenting. If a name needs a comment to explain it, rename it.

---

## Engineering Constraints

- One function, one responsibility. Max 30 lines of logic. Max 3 parameters; use
  an options object or dataclass beyond that.
- Max 2 levels of nesting; use early returns.
- Never silently swallow exceptions. Log with: timestamp, error type, stack trace,
  and context.
- Validate and sanitize all external input. Assume hostile data at every system
  boundary (user input, API responses, file reads, environment variables).
- Never hardcode secrets, keys, or tokens. Environment variables only.
- Flag any injection risk: SQL, command, template literal, path traversal.
- Least privilege on all permission and scope decisions.

---

## Comments

Default to no comments. Add one only when the WHY is non-obvious: a hidden
constraint, a subtle invariant, or a workaround for a specific known bug.

Never explain what the code does. Well-named identifiers already do that.
Never reference the current task, PR number, or caller in comments; those
belong in commit messages and rot as the codebase evolves.

---

## Git

- Branch naming: `type/short-description`
- Commits: Conventional Commits format: `type(scope): description`
- Atomic commits. One logical change per commit.
- No secrets, no `.env` files, no generated build artifacts in commits.
- Never append co-authored-by or AI attribution lines.

---

## Testing

- Write tests for all new public functions and API endpoints.
- Test behavior, not implementation details.
- Name tests descriptively: `it('returns 404 when user does not exist')`
- [CUSTOMIZE: add framework-specific conventions, coverage thresholds, or mocking rules]

---

## Output

- Complete, runnable code. No placeholders unless explicitly building a template.
- Multi-file tasks: produce all files, not just the changed ones.
- Modifications: show the full updated function or block, not a diff fragment.
- State architectural assumptions before producing code.
- If the request is ambiguous, state the assumption and proceed.

---

## Safety

- Never force-push to `main` or `master`.
- Never delete branches without explicit confirmation.
- Read files before editing them.
- Run tests after changes if a test suite exists.
- Ask before any irreversible action: dropping tables, deleting data, modifying
  CI/CD pipelines, or publishing packages.
