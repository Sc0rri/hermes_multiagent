# fullstack-php-go — Hermes profile distribution

Multi-profile dev pack for PHP/Yii2/Laravel and Go projects. Built for
[Hermes Agent](https://hermes-agent.nousresearch.com/) ≥0.16 with
OpenRouter free tier + Ollama Cloud (optional).

## Install

```bash
# from a clone
bash scripts/install.sh

# or directly from the repo (requires git)
hermes profile install https://github.com/Sc0rri/hermes_multiagent
```

`install.sh` creates one Hermes profile per role, each pinned to a default
model and preloaded with its own skill. Run it again after `git pull` —
it's idempotent.

## Profiles

| Profile       | Default model                                  | Role                              |
|---------------|------------------------------------------------|-----------------------------------|
| `orchestrator`| qwen3-14b:free                                 | classify + dispatch (router)      |
| `planner`     | qwen3-14b:free                                 | decompose features into steps     |
| `researcher`  | qwen3-14b:free                                 | library / version lookup          |
| `php-dev`     | deepseek-chat-v3.1:free                        | write PHP/Yii2/Laravel code       |
| `go-dev`      | deepseek-chat-v3.1:free                        | write Go code                     |
| `database-dev`| deepseek-chat-v3.1:free                        | schema, migrations, queries       |
| `devops-dev`  | deepseek-chat-v3.1:free                        | Docker, nginx, systemd, CI        |
| `docs-dev`    | qwen3-14b:free                                 | README, CHANGELOG, docblocks      |
| `reviewer`    | gemma-3-27b-it:free                            | independent review (≠ coding)     |

Override per-role model via env:
```bash
export HERMES_CODING_MODEL=openrouter/anthropic/claude-sonnet-4
export HERMES_REVIEW_MODEL=openrouter/google/gemini-2.5-pro
```

## Run a task

```bash
# full pipeline: orchestrator classifies → dispatches → reviews
bash scripts/orchestrate.sh "Add JWT authentication to the API"

# direct: skip classification, you've already routed
bash scripts/orchestrate.sh -p php-dev "Add a GET /api/users/{id} endpoint"

# planner only (no execution)
bash scripts/orchestrate.sh --plan "Split monolith into 3 services"

# review an existing diff
bash scripts/orchestrate.sh --review --diff /tmp/changes.diff
```

## Pipeline semantics

1. **Classify** — orchestrator returns a JSON envelope:
   `{task_summary, complexity, review_policy, pipeline, reasoning}`.
2. **Dispatch** — each step in `pipeline[]` runs in order. Each step
   receives the previous step's output verbatim.
3. **Review** — every coding step ends in a `reviewer` pass. Reviewer
   model is always ≠ coding model. Pass is chosen from policy:
   `normal` → review; `security` → security; `performance` →
   performance; `architecture` → architecture; `trivial` → review with
   lighter scope.

Keyword rules (security wins if any match): auth, password, token, jwt,
payment, crypto, raw SQL, secret, permission → `security`. slow, N+1,
redis, cache, queue, goroutine, throughput, latency, index →
`performance`. new service, refactor across modules, breaking change,
major version → `architecture`. Multiple matches → pick the most
expensive (architecture > security/performance > normal > trivial).

## What's NOT here

- **No Telegram bots.** This is a CLI pack. `hermes gateway` supports
  Telegram separately if you want a chat interface — that's a Hermes
  feature, not a profile.
- **No per-agent AGENTS.md.** Hermes reads one `AGENTS.md` per project.
  Profile behaviour lives in `skills/<profile>/SKILL.md`, installed into
  the profile's skill directory by `install.sh`.
- **No separate logging DB.** `hermes` already writes everything to
  `~/.hermes/state.db` and `~/.hermes/logs/`. Adding a parallel
  `agent-logs.db` was a Telegram-era artifact; removed.
- **No custom MCP servers in this repo.** Use `hermes mcp add` for
  Filesystem/Git MCP — that's the recommended path.

## Smoke test

```bash
bash scripts/smoke-test.sh
```

Three scenarios: bug fix (php-dev → reviewer), auth feature (forces
security pass), docs-only (no reviewer). All return descriptions, no
project files are touched.

## Architecture notes

This pack went through one major restructure. The previous version
shipped as `agents/<name>/` folders with `profile:` frontmatter keys and
YAML policy files (`config/cost_policy.yaml`, `config/review_policy.yaml`,
`config/capabilities.yaml`) that no Hermes runtime actually parsed. The
Telegram-era artifacts (per-agent AGENTS.md, custom logging DB, hardcoded
agent-name routing) are gone. The current shape matches what Hermes
actually does: profiles for isolation, skills for behaviour, one
orchestrator script for routing, free-tier defaults baked in.