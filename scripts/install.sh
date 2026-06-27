#!/usr/bin/env bash
# install.sh — create the 9 profiles with no bundled skills, then install
# each role's own skill + a short per-profile SOUL.md + toolset allowlist.
# Idempotent. Run again after `git pull`.

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PROFILES=(orchestrator planner researcher php-dev go-dev database-dev devops-dev docs-dev reviewer)

# ponytail: per-role SOUL.md (3-4 lines each). Routing rules live in the skill,
# not here — SOUL just declares what the profile is.
declare -A SOUL=(
  [orchestrator]="You are a router. Classify tasks, dispatch to sub-profiles via the terminal tool. Never write code."
  [planner]="You decompose complex features into ordered steps. No code."
  [researcher]="You look up library docs and version notes. Compact report, sources cited."
  [php-dev]="You write PHP code (Yii2/Laravel). PSR-12, layered. Return a diff, no commentary."
  [go-dev]="You write Go code (fiber/gin/gRPC). Idiomatic, errgroup, table-driven tests. Return a diff."
  [database-dev]="You design schema, migrations, queries. Reversible migrations, indexed where justified. Return SQL."
  [devops-dev]="You edit Docker/nginx/systemd/CI. No secrets in code. Destructive ops require user confirmation."
  [docs-dev]="You write README/CHANGELOG/docblocks to match the current diff. No marketing tone."
  [reviewer]="You review a diff on a single pass. Find bugs, layering violations, N+1, missing validation. Verdict + notes only."
)

# ponytail: free-tier model strategy via Ollama Cloud (no daily cap,
# per-model per-minute rate only — way more headroom than OpenRouter free).
# Ollama Cloud provider is built into Hermes (`hermes --provider ollama-cloud`).
# Override per profile: hermes -p X config set model.default M.
declare -A MODELS=(
  [orchestrator]="ministral-3:14b"
  [planner]="ministral-3:14b"
  [researcher]="ministral-3:8b"
  [php-dev]="qwen3-coder:480b"
  [go-dev]="qwen3-coder:480b"
  [database-dev]="qwen3-coder:480b"
  [devops-dev]="devstral-small-2:24b"
  [docs-dev]="gemma3:4b"
  [reviewer]="gpt-oss:120b"
)

# ponytail: per-profile disabled toolsets. Only what each role actually
# needs stays enabled; everything else is disabled to keep the agent's
# tool palette tight. Reviewer disables anything that mutates state.
declare -A DISABLED=(
  [orchestrator]="image_gen tts video video_gen homeassistant spotify yuanbao browser vision computer_use code_execution delegation cronjob clarify"
  [planner]="image_gen tts video video_gen homeassistant spotify yuanbao browser computer_use code_execution delegation cronjob"
  [researcher]="image_gen video video_gen homeassistant spotify yuanbao computer_use code_execution delegation cronjob"
  [php-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [go-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [database-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [devops-dev]="image_gen tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob"
  [docs-dev]="tts video video_gen homeassistant spotify yuanbao computer_use delegation cronjob browser image_gen"
  [reviewer]="tts video video_gen image_gen homeassistant spotify yuanbao computer_use code_execution delegation cronjob browser"
)

for profile in "${PROFILES[@]}"; do
  if ! hermes profile list 2>/dev/null | grep -q "^[[:space:]]*$profile\b"; then
    hermes profile create "$profile" --no-skills --no-alias >/dev/null
  fi

  hermes -p "$profile" config set model.default "${MODELS[$profile]}" 2>/dev/null
  hermes -p "$profile" config set model.provider ollama-cloud 2>/dev/null

  # ponytail: disabled_toolsets must be a real YAML list, not a string.
  # `hermes config set` stringifies JSON-list args, so write via python+yaml.
  python3 -c "
import yaml
p = '$HERMES_HOME/profiles/$profile/config.yaml'
with open(p) as f: cfg = yaml.safe_load(f) or {}
cfg.setdefault('agent', {})['disabled_toolsets'] = '${DISABLED[$profile]}'.split()
with open(p, 'w') as f: yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
" || { echo "  ! failed to set disabled_toolsets for $profile (python3 + pyyaml required)"; }

  printf '%s\n' "${SOUL[$profile]}" > "$HERMES_HOME/profiles/$profile/SOUL.md"

  # ponytail: only this profile's skill + _ponytail for code-writers.
  dst="$HERMES_HOME/profiles/$profile/skills/$profile"
  mkdir -p "$dst"
  [[ -f "$REPO_ROOT/skills/$profile/SKILL.md" ]] && \
    cp "$REPO_ROOT/skills/$profile/SKILL.md" "$dst/SKILL.md"

  if [[ "$profile" =~ -dev$ ]] || [[ "$profile" == "reviewer" ]]; then
    pdst="$HERMES_HOME/profiles/$profile/skills/_ponytail"
    mkdir -p "$pdst"
    cp "$REPO_ROOT/skills/_ponytail/SKILL.md" "$pdst/SKILL.md"
  fi

  # ponytail: empty auth.json → silent "no API keys". Inherit from default.
  if [[ ! -s "$HERMES_HOME/profiles/$profile/auth.json" ]] \
     && [[ -s "$HERMES_HOME/auth.json" ]]; then
    cp "$HERMES_HOME/auth.json" "$HERMES_HOME/profiles/$profile/auth.json"
  fi
done

cat <<EOF
>>> 9 profiles installed.

Free-tier 429s often. Swap a model:
  hermes -p <profile> config set model.default <model>
Or set HERMES_<ROLE>_MODEL env var.

Use:  hermes -p orchestrator chat
EOF