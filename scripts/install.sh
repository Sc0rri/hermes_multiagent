#!/usr/bin/env bash
# install.sh — read config/*.yaml, create N profiles (no bundled skills),
# install each role's skill + per-profile SOUL.md + toolset allowlist +
# per-profile .env + model fallback chain (primary + openrouter + cline).
# Idempotent. Run again after `git pull`.

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$REPO_ROOT/config"

PROFILES=(orchestrator planner researcher php-dev go-dev rust-dev database-dev devops-dev docs-dev reviewer auditor)

# ponytail: per-role SOUL.md (3-4 lines each). Routing rules live in
# config/routing.yaml + capabilities.yaml — SOUL just declares what the
# profile is, in plain text for the model to internalise quickly.
declare -A SOUL=(
  [orchestrator]="You are a router. Classify tasks by reading config/routing.yaml and config/capabilities.yaml, then dispatch to sub-profiles via the terminal tool. Never write code."
  [planner]="You decompose complex features by reading config/cost-policy.yaml for budget and config/capabilities.yaml for stack routing. No code."
  [researcher]="You look up library docs and version notes. Compact report, sources cited."
  [php-dev]="You write PHP code (Yii2/Laravel). PSR-12, layered. Return a diff, no commentary."
  [go-dev]="You write Go code (fiber/gin/gRPC). Idiomatic, errgroup, table-driven tests. Return a diff."
  [rust-dev]="You write Rust code (tokio, axum, Cloudflare Workers wasm). Idiomatic ownership, Result over panic, clippy-clean. Return a diff."
  [database-dev]="You design schema, migrations, queries. Reversible migrations, indexed where justified. Return SQL."
  [devops-dev]="You edit Docker/nginx/systemd/CI. No secrets in code. Destructive ops require user confirmation."
  [docs-dev]="You write README/CHANGELOG/docblocks to match the current diff. No marketing tone."
  [reviewer]="You review a diff on a single pass. Find bugs, layering violations, N+1, missing validation. Verdict + notes only."
  [auditor]="Read-only analysis: documentation, tests, naming. You report, you do not edit. No write_file, no patch."
)

# ponytail: per-profile disabled toolsets. Only what each role actually
# needs stays enabled; everything else is disabled to keep the agent's
# tool palette tight. Orchestrator has NO file tools — must dispatch.
declare -A DISABLED=(
  [orchestrator]="image_gen tts video video_gen homeassistant spotify yuanbao browser vision computer_use code_execution delegation cronjob clarify file search write_file patch"
  [planner]="image_gen tts video video_gen homeassistant spotify yuanbao browser computer_use code_execution delegation cronjob"
  [researcher]="image_gen video video_gen homeassistant spotify yuanbao computer_use code_execution delegation cronjob"
  [php-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [go-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [rust-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [database-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [devops-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [docs-dev]="tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob browser image_gen"
  [reviewer]="tts video video_gen image_gen homeassistant spotify yuanbao computer_use code_execution delegation cronjob browser"
  [auditor]="tts video video_gen image_gen homeassistant spotify yuanbao computer_use code_execution delegation cronjob browser write_file patch"
)

# ponytail: register custom_providers in the GLOBAL ~/.hermes/config.yaml
# (not per-profile) so every profile can reference them by name. Idempotent.
ensure_custom_providers() {
  python3 <<PY
import yaml
p = '$HERMES_HOME/config.yaml'
with open(p) as f:
    cfg = yaml.safe_load(f) or {}

# ponytail: chain listed in a single helper so adding a new provider is
# one block, not a brand-new function. CLINE_API_KEY must be exported in
# ~/.hermes/.env (env var, not direct api_key — keeps secrets out of disk).
PROVIDERS = [
    {
        "name": "cline",
        "base_url": "https://api.cline.bot/api/v1",
        "key_env": "CLINE_API_KEY",
        "api_mode": "chat_completions",
        "models": [
            "deepseek/deepseek-v4-flash",
            "stepfun/step-3.7-flash",
        ],
    },
]

cp = cfg.setdefault("custom_providers", [])
existing = {c.get("name") for c in cp}
for prov in PROVIDERS:
    if prov["name"] not in existing:
        cp.append(prov)

with open(p, "w") as f:
    yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
PY
}
ensure_custom_providers

# ponytail: write model block (primary + provider + 3-tier fallback chain)
# to every per-profile config.yaml in one python subprocess. Loop in bash
# was unreliable (SIGPIPE from python's no-trailing-newline printer under
# `set -euo pipefail` + process substitution). One process owns the whole
# parse-and-write — simpler, debuggable, idempotent.
apply_models() {
  python3 <<PY
import json, yaml
from pathlib import Path

models = yaml.safe_load(open('$CONFIG_DIR/models.yaml'))['profiles']
hermes_home = Path('$HERMES_HOME')

for name, m in models.items():
    p = hermes_home / 'profiles' / name / 'config.yaml'
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open() as f:
        cfg = yaml.safe_load(f) or {}
    block = cfg.setdefault('model', {})
    block['default'] = m['primary']
    block['provider'] = 'ollama-cloud'
    fallbacks = m.get('fallbacks', [])
    if fallbacks:
        # ponytail: ensure each fallback has provider + model; drop empty
        for fb in fallbacks:
            assert fb.get('provider') and fb.get('model'), f"{name} fallback missing field: {fb}"
        block['fallback_model'] = fallbacks
    else:
        block.pop('fallback_model', None)
    with p.open('w') as f:
        yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
    print(f"  {name}: primary={m['primary']} fallbacks={len(fallbacks)}", flush=True)
PY
}
apply_models

for profile in "${PROFILES[@]}"; do
  if ! hermes profile list 2>/dev/null | grep -q "^[[:space:]]*$profile\b"; then
    hermes profile create "$profile" --no-skills --no-alias >/dev/null
  fi
  # ponytail: disabled_toolsets via python+yaml — config set stringifies
  # JSON lists, so YAML edit is the only path that produces a real list.
  python3 -c "
import yaml
p = '$HERMES_HOME/profiles/$profile/config.yaml'
with open(p) as f: cfg = yaml.safe_load(f) or {}
cfg.setdefault('agent', {})['disabled_toolsets'] = '${DISABLED[$profile]}'.split()
with open(p, 'w') as f: yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
" || echo "  ! failed to set disabled_toolsets for $profile"

  printf '%s\n' "${SOUL[$profile]}" > "$HERMES_HOME/profiles/$profile/SOUL.md"

  # ponytail: copy config/ into profile's home so the model can read it.
  # (Hermes profile doesn't auto-mount the repo's config/.)
  mkdir -p "$HERMES_HOME/profiles/$profile/config"
  cp "$CONFIG_DIR"/*.yaml "$HERMES_HOME/profiles/$profile/config/" 2>/dev/null || true

  # ponytail: copy every skill under skills/<profile>/ to the profile's
  # skill dir. The "role skill" lives at skills/<profile>/SKILL.md;
  # extras (php-pro, golang-patterns, tdd, etc.) live at
  # skills/<profile>/<skill-name>/SKILL.md. Plus _ponytail for coders.
  mkdir -p "$HERMES_HOME/profiles/$profile/skills"
  # ponytail: clear stale skills from previous installs — if repo no
  # longer ships a skill, drop it from the profile too.
  rm -rf "$HERMES_HOME/profiles/$profile/skills"/* 2>/dev/null || true
  mkdir -p "$HERMES_HOME/profiles/$profile/skills"
  if [[ -f "$REPO_ROOT/skills/$profile/SKILL.md" ]]; then
    mkdir -p "$HERMES_HOME/profiles/$profile/skills/$profile"
    cp "$REPO_ROOT/skills/$profile/SKILL.md" \
       "$HERMES_HOME/profiles/$profile/skills/$profile/SKILL.md"
  fi
  # extras: each subdir under skills/<profile>/
  for skill_dir in "$REPO_ROOT/skills/$profile"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="$(basename "$skill_dir")"
    [[ "$skill_name" == "$profile" ]] && continue
    target="$HERMES_HOME/profiles/$profile/skills/$skill_name"
    mkdir -p "$target"
    # ponytail: copy everything in the skill dir (SKILL.md + references/ + assets/),
    # but skip files we already rm'd in the loop above (no-op safety).
    (cd "$skill_dir" && cp -R . "$target/" 2>/dev/null) || \
      cp "$skill_dir/SKILL.md" "$target/SKILL.md"
  done

  # ponytail: per-profile .env so child processes spawned from TUI have
  # keys without inheriting shell env (which TUI often has empty).
  env_file="$HERMES_HOME/profiles/$profile/.env"
  {
    echo "# Auto-generated by fullstack-php-go/scripts/install.sh"
    echo "# Per-profile secrets override the shell environment."
    echo
    if [[ -f "$HERMES_HOME/.env" ]]; then
      grep -E '^[A-Z_]+_API_KEY=' "$HERMES_HOME/.env" || true
    fi
  } > "$env_file"
  chmod 600 "$env_file"

  # ponytail: drop inherited auth.json — it pointed at env vars that
  # child processes don't see (caused HTTP 401 in hermes-desktop TUI).
  rm -f "$HERMES_HOME/profiles/$profile/auth.json"
done

cat <<EOF
>>> ${#PROFILES[@]} profiles installed.

Routing/capability/policy in: config/*.yaml (also copied to each
profile's home so the model can read them directly).

Models: primary + 3-tier fallback chain from config/models.yaml
  (ollama-cloud -> openrouter free -> cline free). Add CLINE_API_KEY
  to ~/.hermes/.env to enable tier 3.
Free-tier 429s? Swap: hermes -p <profile> config set model.default M
Or set HERMES_<ROLE>_MODEL env var.

Use:  hermes -p orchestrator chat
EOF