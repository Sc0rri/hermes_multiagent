# Hermes Developer Pack — Full-Stack (PHP / Go / Yii2 / Laravel)

Built for: **hermes-desktop + Ollama (local/cloud) + OpenRouter free tier**.

## Structure

```
├─ config/
│  └── profiles.yaml          # role -> model routing (OpenRouter free / Ollama Cloud)
└─ skills/
   ├── orchestrator/SKILL.md  # task routing, never writes code
   ├── planner/SKILL.md       # decomposition, pipeline selection
   ├── research-agent/SKILL.md
   ├── php-agent/SKILL.md     # Yii2 / Laravel / Composer / PSR
   ├── go-agent/SKILL.md      # goroutines / gRPC / fiber / gin
   ├── devops-agent/SKILL.md  # docker / nginx / systemd / wsl / ssh
   ├── reviewer/SKILL.md      # ALWAYS a different model, no memory
   └── docs-agent/SKILL.md    # README / CHANGELOG
```

## Installation (for hermes-desktop)

1. In hermes-desktop: Settings → Providers → add OpenRouter (key from openrouter.ai) and Ollama (local or Cloud URL).
2. Copy `config/profiles.yaml` → `~/.hermes/profiles.yaml` (or import via `/profile import` if your version supports it — check `/profile help`).
3. Copy each folder from `skills/` into `~/.hermes/skills/<name>/SKILL.md` (or via UI: Skills → Import).
4. In `orchestrator/SKILL.md`, make sure the agent names match exactly what you named them when creating agents in hermes-desktop (Agents → Create).
5. Smoke test: give the task "Fix the bug in LoginController" and confirm the chain that fires is Research → PHP Agent → Reviewer — not every agent at once.

## Pipeline logic (Planner decides dynamically)

| Task type | Pipeline |
|---|---|
| New feature ("add JWT auth") | Planner → Research → PHP/Go Agent → Reviewer → Docs → Final |
| Bug fix | Research → PHP/Go Agent → Reviewer → Final |
| Docs only | Docs Agent → Final |
| Infrastructure (docker/deploy) | Planner → DevOps Agent → Reviewer → Final |

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
- **Reviewer**: memory fully disabled — every review is independent, with no knowledge
  of past decisions.
- **Research/Docs/Planner/Orchestrator**: shared short-term session memory only, no
  long-term accumulation of stack-specific details.

## Ponytail (mandatory for every coding agent)

Before calling any LLM, a coding agent must:
1. Fetch the project structure.
2. Find relevant symbols/files.
3. Resolve dependencies (composer.json / go.mod).
4. Assemble a minimal but precise context.
5. Only then send the request to the model.

This isn't a separate SKILL.md — it's a rule embedded at the top of php-agent,
go-agent, and devops-agent.
