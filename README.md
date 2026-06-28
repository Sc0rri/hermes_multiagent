# fullstack-php-go-rust

Hermes Agent profile distribution for PHP (Yii2, Laravel, OpenCart 2.x),
Go, and Rust (incl. Cloudflare Workers wasm) projects.

11 profiles, each with its own skill + model + toolset + `.env`. You only
ever invoke the orchestrator; it dispatches to sub-profiles via the
`terminal` tool.

## Install

```bash
bash scripts/install.sh
```

Idempotent. Reads `config/models.yaml` and writes per-profile
`model.default` + `model.fallback_model`. Copies `config/*.yaml` into
each profile's home so the model can read them directly.

## Use

```bash
hermes -p orchestrator chat
# then: "Fix the bug in LoginController on empty email"
```

Orchestrator reads `config/routing.yaml` + `config/capabilities.yaml`,
picks the right pipeline, and runs each step via
`hermes -p <profile> chat -q ... --yolo --quiet`.

## Profiles

| Profile         | Default model            | Disabled tools                    | Role                       |
|-----------------|--------------------------|------------------------------------|----------------------------|
| `orchestrator`  | `ministral-3:14b`        | file, search, write_file, patch   | route + dispatch           |
| `planner`       | `ministral-3:14b`        | (heavy)                            | decompose features         |
| `researcher`    | `ministral-3:8b`         | code_execution, terminal           | library/version lookup     |
| `php-dev`       | `qwen3-coder:480b`       | image, tts, video, browser, ...   | write PHP                  |
| `go-dev`        | `qwen3-coder:480b`       | same                               | write Go                   |
| `rust-dev`      | `qwen3-coder:480b`       | same                               | write Rust (incl. wasm)    |
| `database-dev`  | `qwen3-coder:480b`       | same                               | schema, migrations         |
| `devops-dev`    | `devstral-small-2:24b`   | same                               | Docker, nginx, systemd     |
| `docs-dev`      | `gemma3:4b`              | most (incl. code_execution)       | README, CHANGELOG          |
| `reviewer`      | `gpt-oss:120b`           | most (incl. code_execution)       | review diff                |
| `auditor`       | `ministral-3:14b`        | most + write_file/patch           | read-only doc/test audit   |

Coding profiles (`*-dev`, `reviewer`) also load the shared
`skills/_ponytail/SKILL.md` (lazy-senior discipline), plus role-specific
extras:

| Profile        | Extras (in addition to role + _ponytail) |
|----------------|------------------------------------------|
| `php-dev`      | `laravel-specialist`, `redis-development`, `tdd`, `sysdebug`, `req-review` |
| `go-dev`       | `golang-patterns`, `golang-testing`, `redis-development`, `tdd`, `sysdebug`, `req-review` |
| `rust-dev`     | `rust-best-practices` (Apollo handbook, 9 chapters) |
| `database-dev` | `redis-development`, `tdd`, `sysdebug`, `explain-patterns` |
| `devops-dev`   | `tdd`, `docker-nginx-patterns` |
| `reviewer`     | `sysdebug` |
| `planner`      | (none — role skill already covers planning) |
| `researcher`   | (none) |
| `auditor`      | (none) |

Extras come from two sources:
- **Bundled with Hermes** (`~/.hermes/skills/software-development/*`) — copied via `install.sh`.
- **[midudev/autoskills](https://github.com/midudev/autoskills) registry**
  (`laravel-specialist`, `golang-patterns`, `golang-testing`,
  `redis-development`) — downloaded by `install.sh` from the upstream
  SKILL.md URLs.

Add a new extra: drop `SKILL.md` at `skills/<profile>/<skill-name>/SKILL.md`
in this repo. `install.sh` will copy it into
`~/.hermes/profiles/<profile>/skills/<skill-name>/` next run.

## Config (single source of truth)

```
config/
  capabilities.yaml    profile → languages/frameworks/databases
  routing.yaml         keyword → pipeline (list of profiles)
  review-policy.yaml   policy → passes + max_cycles
  cost-policy.yaml     complexity → max LLM calls
  context-policy.yaml  max_files / max_tokens caps
  models.yaml          primary + fallback model per profile
```

Add `symfony-dev` by adding entries to `capabilities.yaml`, `models.yaml`,
and a `skills/symfony-dev/SKILL.md`. Orchestrator's routing rules don't
change — `routing.yaml` matches by keyword, `capabilities.yaml` resolves
who handles it.

## Routing (high-level)

- Code work → matching `*-dev` (`php`, `go`, `rust`, `database`, `devops`) → `reviewer`
- Read-only audit → `auditor`
- Docs update → `docs-dev`
- New library/version → `researcher`
- Multi-layer feature → `planner` → coding → `reviewer`

When a task matches more than one route's keywords (e.g. "latest Yii2
version" matches both `research` and `php`), `priority` in
`routing.yaml` decides — highest wins, a tie at the top priority falls
back to "ask user" rather than silently unioning pipelines.

Full keyword map in `config/routing.yaml`.

## Review policies

`trivial` · `normal` (default) · `security` · `performance` · `architecture`.

All passes run on the single `reviewer` profile/model — a different pass
means a different focus area, not a different model. If a pass returns
`Confidence: low`, Reviewer surfaces it as the first note for the human
to resolve; it does not trigger another LLM call.

## Tooling (run before every commit)

```bash
bash tests/smoke.sh                         # validate + routing simulation
python3 scripts/explain.py "your task"      # show pipeline without LLM
bash scripts/validate-config.sh            # config consistency check
```

`smoke.sh` runs `validate-config` and 13 canned-task routing cases —
catches keyword over-matching (e.g. `gin` matching `Login`), missing
routes, and broken ties between capabilities/models/routing.

`explain.py <task>` prints which keywords matched, the resulting
pipeline, picked review policy, and cost-policy budget. No LLM call.

## Models

Ollama Cloud primary + fallback per profile
(`config/models.yaml`). install.sh pins `model.provider=ollama-cloud`
for every profile unconditionally — switching a single profile to
OpenRouter is a manual per-profile override (no entry in `models.yaml`
yet):

```bash
# switch the orchestrator to OpenRouter (free tier)
hermes -p orchestrator config set model.provider openrouter
hermes -p orchestrator config set model.default "google/gemma-4-31b-it:free"
# check live models: curl https://openrouter.ai/openrouter/free
```

Edit `config/models.yaml` and re-run `install.sh` to apply globally
(Ollama Cloud only).
