# Hermes Developer Pack — Full-Stack (PHP / Go / Yii2 / Laravel)

Built for: **hermes-desktop + Ollama (local/cloud) + OpenRouter free tier**.

## Installation (for hermes-desktop)

1. In hermes-desktop: Settings → Providers → add OpenRouter (key from openrouter.ai) and Ollama (local or Cloud URL).
2. Copy `config/profiles/*.yaml` and `config/review_policy.yaml` into `~/.hermes/` (or import via `/profile import` if your version supports it — check `/profile help`). Each profile is its own file under `profiles/` so you can update one model without touching the rest.
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

## Cross-model review (mandatory for code) — review policies, not separate agents

There is still only **one Reviewer agent** — it runs different passes depending on
the review policy Orchestrator/Planner selects from `config/review_policy.yaml`.
Each pass uses its own model profile, always different from CODING:

```
PHP/Go/Database/DevOps Agent (CODING profile) → writes code
        ↓
Reviewer runs the passes required by the chosen policy:

  trivial / normal (default, ~90% of tasks):
    Pass 1 — Review (REVIEW profile)

  security (auth/payments/crypto/raw SQL/public API):
    Pass 1 — Review (REVIEW)  +  Pass 2 — Security (SECURITY profile)

  performance (query optimization/Redis/queues/concurrency):
    Pass 1 — Review (REVIEW)  +  Pass 3 — Performance (PERFORMANCE profile)

  architecture (new service/cross-module refactor):
    Pass 1 — Review  +  Pass 2 — Security  +  Pass 4 — Architecture

  consensus (Planner flags as critical, or a pass comes back low-confidence):
    Pass 1 — Review  +  Pass 2 — Security  +  Pass 3 — Performance
        ↓
  Any REJECT from any pass → back to the executor with all notes from all passes
  at once (max 3 cycles)
  All passes APPROVE → final answer to the user
```

The user only sees the final answer unless they explicitly asked to see drafts/review steps.

For complex tasks (new features, architectural decisions), Planner can additionally
run an independent check via the CODING_ALT profile in parallel with CODING, and
Reviewer's first pass compares both variants before finalizing.

**Tie-break instead of a second full review**: if a pass returns `Confidence: low`,
Orchestrator can ask one additional model a single focused question — "given this
diff and these notes, who's right?" — using a third profile. This is far cheaper on
free-tier quota than always running 2-3 full passes.

**Roadmap (not implemented yet):**
- 🔜 Confidence score parsed automatically from each pass, with Orchestrator
  auto-escalating to the tie-break only when confidence is actually low, rather than
  relying on Reviewer to flag it explicitly.
- 🔜 A real `consensus` short-circuit: instead of running a full third pass, ask the
  tie-break question directly when Review and a specialized pass disagree.

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