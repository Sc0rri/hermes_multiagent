# fullstack-php-go — Hermes profile distribution

Multi-profile dev pack for PHP/Yii2/Laravel and Go. Hermes ≥0.16,
Ollama Cloud (no daily cap).

## How it works

One **orchestrator** profile reads `config/routing.yaml` + `config/capabilities.yaml`,
classifies your task, and dispatches to the right sub-profile via
`hermes -p <profile> chat -q ...`. Sub-profiles (`php-dev`, `go-dev`,
`database-dev`, `devops-dev`, `docs-dev`, `researcher`, `planner`,
`reviewer`, `auditor`) each have their own skill and do the actual work.

You only ever invoke the orchestrator. It routes for you.

## Install

```bash
bash scripts/install.sh
```

Idempotent. Run again after `git pull`. `install.sh` reads
`config/models.yaml` and writes per-profile model + fallback into each
profile's `config.yaml`. It also copies the `config/*.yaml` files into
each profile's home so the model can read them directly.

## Use

```bash
hermes -p orchestrator chat
# then: "Check correctness of documentation and tests in pressure_bot"
```

## Config files (single source of truth)

| File | What |
|---|---|
| `config/capabilities.yaml` | profile → languages/frameworks/databases |
| `config/routing.yaml` | keyword → pipeline (list of profiles) |
| `config/review-policy.yaml` | policy name → list of review passes + tie-break |
| `config/cost-policy.yaml` | complexity → max LLM calls |
| `config/context-policy.yaml` | max_files / max_tokens per LLM call |
| `config/models.yaml` | primary + fallback model per profile |

Add a new specialist (e.g. `symfony-dev`) by adding entries in
`capabilities.yaml`, `models.yaml`, and a skill in `skills/`. The
orchestrator's routing rules don't need to change — `routing.yaml`
matches by keyword, then `capabilities.yaml` resolves who handles it.

## Routing (high-level)

- Code work → matching `*-dev` → `reviewer`
- Read-only audit → `auditor`
- Docs update → `docs-dev`
- New library/version → `researcher` → coding profile
- Multi-layer feature → `planner` → coding → `reviewer`

Full table in `config/routing.yaml`.

## Review policies

`trivial` (one line) · `normal` (default) · `security` (auth/crypto/raw SQL)
· `performance` (N+1/queue/goroutine) · `architecture` (new service/breaking).

`Confidence: low` from any pass triggers a **mandatory** tie-break (one
question to a third model — see `config/review-policy.yaml`).

## Models

Ollama Cloud primary, fallback per profile. Override:

```bash
hermes -p <profile> config set model.default <model>
hermes -p <profile> config set model.fallback_model <model>
```

Edit `config/models.yaml` to change defaults for everyone — `install.sh`
will re-apply.
