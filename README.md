# fullstack-php-go — Hermes profile distribution

Multi-profile dev pack for PHP/Yii2/Laravel and Go. Hermes ≥0.16.

## How it works

One **orchestrator** profile reads your task, picks the right sub-profile,
and dispatches it via `hermes -p <profile> chat -q ...`. Sub-profiles
(`php-dev`, `go-dev`, `database-dev`, `devops-dev`, `docs-dev`,
`researcher`, `planner`, `reviewer`) each have their own skill loaded and
do the actual work. Coding profiles also load the shared `_ponytail`
discipline skill.

You only ever invoke the orchestrator. It routes for you.

## Install

```bash
# from a clone
bash scripts/install.sh

# or one-shot from the repo
hermes profile install https://github.com/Sc0rri/hermes_multiagent
```

Idempotent — run again after `git pull`.

## Use

```bash
hermes -p orchestrator chat
# then: "Fix the null pointer in LoginController on empty email"
```

The orchestrator uses `terminal` to spawn sub-profiles, so pipeline
behaviour (planner → coder → reviewer) works automatically inside one
chat session.

`install.sh` opts every profile out of bundled skills so only the
role-specific SKILL.md is loaded — without this, hermes would load 70+
default skills (apple notes, mlops, github, productivity, …) and the
orchestrator would route to one of them instead of dispatching to your
sub-profiles.

## Per-profile model

Profiles default to **Ollama Cloud** (no daily cap, per-model rate only).
Available models tested 2026-06: `gemma3:4b`, `ministral-3:{3b,8b,14b}`,
`devstral-small-2:24b`, `qwen3-coder:480b`, `gpt-oss:120b`.

Override per profile:
```bash
hermes -p orchestrator config set model.default ministral-3:14b
hermes -p php-dev      config set model.default qwen3-coder:480b
hermes -p reviewer     config set model.default gpt-oss:120b
```

Switch to OpenRouter if you prefer (less headroom, daily cap):
```bash
hermes -p <profile> config set model.provider openrouter
hermes -p <profile> config set model.default qwen/qwen3-coder:free
```

List live Ollama Cloud models: `curl -H "Authorization: Bearer $OLLAMA_API_KEY" https://ollama.com/api/tags`.

## Routing

The orchestrator picks by keyword. Default routing:

| Task shape                                | Profile(s)                              |
|-------------------------------------------|-----------------------------------------|
| PHP / Yii2 / Laravel code change          | `php-dev` → `reviewer`                  |
| Go / fiber / gin / gRPC code change       | `go-dev` → `reviewer`                   |
| docker / nginx / systemd / CI / deploy    | `devops-dev` → `reviewer`               |
| Schema / migration / query / index        | `database-dev` → `reviewer`             |
| README / CHANGELOG only                   | `docs-dev`                              |
| New library / version lookup              | `researcher` → coding profile           |
| Multi-step new feature across layers      | `planner` → coding → `reviewer`         |

Reviewer policy (passed via `Pass:` line):
auth / payment / crypto / raw SQL / secret → `security`. N+1 / redis /
queue / goroutine / index → `performance`. New service / cross-module
refactor / breaking change → `architecture`. Otherwise `review`.