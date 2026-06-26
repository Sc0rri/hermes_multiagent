# Deploy

This folder is intentionally close to empty — deploy scripts are project-specific
(SSH targets, Docker registries, environment names differ per project), so DevOps
Agent should generate/maintain them per-project rather than the pack shipping fake
generic scripts that someone copy-pastes without reading.

## What belongs here once you start using it
- `deploy.sh` — SSH-based deploy script (pull, build, restart service), with all
  secrets via environment variables, never hardcoded.
- `docker-compose.prod.yml` — production compose file, separate from the dev one.
- Any systemd unit files for Go services, generated/maintained by DevOps Agent.

## Rule
DevOps Agent writes these files following the security rules in
`agents/devops-agent/SKILL.md`: no secrets in code, and any destructive change
(e.g. modifying a prod deploy script) goes through Orchestrator for explicit
user confirmation before being applied.
