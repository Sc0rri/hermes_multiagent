# Hermes Developer Pack — Full-Stack (PHP / Go / Yii2 / Laravel)

Built for: **hermes-desktop + Ollama (local/cloud) + OpenRouter free tier**.

## Installation (for hermes-desktop)

1. In hermes-desktop: Settings → Providers → add OpenRouter (key from openrouter.ai) and Ollama (local or Cloud URL).
2. Copy `config/profiles.yaml` → `~/.hermes/profiles.yaml` (or import via `/profile import` if your version supports it — check `/profile help`).
3. Copy each folder from `agents/` into `~/.hermes/skills/<name>/SKILL.md` (or via UI: Skills → Import). Note: hermes-desktop's own folder is still called `skills/` internally — this pack just calls it `agents/` at the repo level for clarity.
4. In `agents/orchestrator/SKILL.md`, make sure the agent names match exactly what you named them when creating agents in hermes-desktop (Agents → Create).
5. Register the MCP servers listed in `mcp/README.md` (Filesystem, Git — minimum set), and install Ponytail as a skill/plugin per its own install docs (it's a coding-discipline skill, not an MCP context server — see https://github.com/DietrichGebert/ponytail for the install path matching your host).
6. Smoke test: see `tests/smoke-tests.md`.

## Pipeline logic (Planner decides dynamically)

| Task type | Pipeline |
|---|---|
| New feature ("add JWT auth") | Planner → Research → PHP/Go Agent → Reviewer → Docs → Final |
| Bug fix | Research → PHP/Go Agent → Reviewer → Final |
| Docs only | Docs Agent → Final |
| Infrastructure (docker/deploy) | Planner → DevOps Agent → Reviewer → Final |
| Schema/migration/query | Database Agent → Reviewer → Final (then PHP/Go Agent if app-layer code also changes) |

## Cross-model review (mandatory for code)

```
PHP/Go Agent (CODING profile) → writes code
        ↓
Reviewer (REVIEW profile, different model!) → checks:
  - bugs
  - SOLID/PSR violations
  - performance issues
  - security issues
        ↓
  Reject → back to PHP/Go Agent with specific notes (max 3 cycles)
  Approve → final answer to the user
```

The user only sees the final answer unless they explicitly asked to see drafts/review steps.

For complex tasks (new features, architectural decisions), Planner can additionally
run an independent check via the CODING_ALT profile in parallel with CODING, and
Reviewer compares both variants before finalizing.

## Memory (strictly separated)

- **PHP Agent**: Yii2/Laravel patterns, PSR, Repository/Service/DTO, Composer package
  versions used in the project.
- **Go Agent**: goroutines/channels, gRPC, fiber/gin, project modules.
- **DevOps Agent**: docker/nginx/systemd/wsl/ssh hosts, project environment variables.
- **Database Agent**: schema shape, naming conventions, dev-vs-prod engine (SQLite/PostgreSQL).
- **Reviewer**: memory fully disabled — every review is independent, with no knowledge
  of past decisions.
- **Research/Docs/Planner/Orchestrator**: shared short-term session memory only, no
  long-term accumulation of stack-specific details.

## MCP servers

See `mcp/README.md` for the full list (Filesystem, Git, SQLite, GitHub) and which
agents need which. Minimum to start: Filesystem + Git (Reviewer should get
**read-only** Git/Filesystem access if your hermes-desktop version supports scoping).

## Ponytail (mandatory for every coding agent)

Ponytail is a coding-discipline skill ("the laziest senior dev in the room"), not a
context-fetching tool. It's installed as a plugin/skill alongside the agents (see
https://github.com/DietrichGebert/ponytail for the install method matching your
host) and makes every coding agent check, before writing anything new:

1. Does this need to exist at all? (YAGNI)
2. Does the language's stdlib already do it?
3. Does the framework (Yii2/Laravel/Go stdlib) already provide it?
4. Does an already-installed dependency provide it?
5. Can it be done in one line?
6. Only then: write the minimum custom code that actually works.

It never trims validation, error handling, security checks, or accessibility — only
unnecessary code. This is embedded as a "Ponytail discipline" section in
php-agent, go-agent, devops-agent, and database-agent.

Separately, before calling any LLM, a coding agent must also gather project context
(structure, relevant symbols/files, dependency files like composer.json/go.mod) via
the Filesystem/Git MCP — that's a distinct step from Ponytail and is described in
each agent's "gather context" section.
