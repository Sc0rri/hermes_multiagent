#!/usr/bin/env bash
# install.sh — wire this repo's profiles into the current Hermes install.
#
# Idempotent. Run after `git pull`. Profiles are created with the same
# names as the skills, each with a default model pinned so the model swap
# in orchestrate.sh is explicit.
#
# Usage:
#   bash install.sh           # install profiles only
#   bash install.sh --alias   # also create shell wrappers (hermes-php, etc.)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
WITH_ALIAS=0
[[ "${1:-}" == "--alias" ]] && WITH_ALIAS=1

# ponytail: model map. Same defaults as orchestrate.sh. Override with env.
# Real free-tier models from openrouter.ai/openrouter/free, fetched 2026-06.
# Tested live: google/gemma-4-31b-it:free responded 200; qwen/qwen3-coder:free
# and openai/gpt-oss-120b:free were 429-rate-limited at fetch time. Use the
# Gemma as both router and reviewer (different family from coding), and the
# Qwen coder when its rate limit clears — user can override per env.
declare -A MODELS=(
  [orchestrator]="openrouter/google/gemma-4-31b-it:free"
  [planner]="openrouter/google/gemma-4-31b-it:free"
  [researcher]="openrouter/google/gemma-4-31b-it:free"
  [php-dev]="openrouter/qwen/qwen3-coder:free"
  [go-dev]="openrouter/qwen/qwen3-coder:free"
  [database-dev]="openrouter/qwen/qwen3-coder:free"
  [devops-dev]="openrouter/qwen/qwen3-coder:free"
  [docs-dev]="openrouter/google/gemma-4-31b-it:free"
  [reviewer]="openrouter/google/gemma-4-31b-it:free"
)

echo ">>> creating profiles in $HERMES_HOME/profiles/"
for profile in "${!MODELS[@]}"; do
  model="${MODELS[$profile]}"
  # ponytail: don't re-create if profile already exists with the right model.
  if hermes profile list 2>/dev/null | grep -q "^[[:space:]]*$profile\b"; then
    echo "  · $profile exists, updating model → $model"
    bare_model="${model#openrouter/}"
    bare_model="${bare_model#ollama/}"
    hermes -p "$profile" config set model.default "$bare_model"
  else
    echo "  · creating $profile (model=$model)"
    hermes profile create "$profile" --from default 2>/dev/null \
      || hermes profile create "$profile"
    # ponytail: strip "openrouter/" prefix when setting default — Hermes adds
    # it back itself based on the provider, doubling it causes HTTP 400.
    bare_model="${model#openrouter/}"
    bare_model="${bare_model#ollama/}"
    hermes -p "$profile" config set model.default "$bare_model"
    # ponytail: pin provider so model.google/... resolves without ambiguity
    # (without this, profiles inherit the global default provider, which may
    # not be openrouter — leading to silent "no API keys" failures).
    if [[ "$model" == openrouter/* ]]; then
      hermes -p "$profile" config set model.provider openrouter
    elif [[ "$model" == ollama* ]]; then
      hermes -p "$profile" config set model.provider ollama
    fi
  fi

  # ponytail: copy skill to the profile's skill directory (idempotent).
  src_skill="$(dirname "$0")/../skills/$profile/SKILL.md"
  dst_dir="$HERMES_HOME/profiles/$profile/skills/$profile"
  if [[ -f "$src_skill" ]]; then
    mkdir -p "$dst_dir"
    cp "$src_skill" "$dst_dir/SKILL.md"
    echo "  · skill $profile → $dst_dir/SKILL.md"
  fi

  # ponytail: ponytail is shared — install into every coding profile.
  if [[ "$profile" =~ -dev$ ]] || [[ "$profile" == "reviewer" ]]; then
    ponytail_src="$(dirname "$0")/../skills/_ponytail/SKILL.md"
    ponytail_dst="$HERMES_HOME/profiles/$profile/skills/_ponytail"
    if [[ -f "$ponytail_src" ]]; then
      mkdir -p "$ponytail_dst"
      cp "$ponytail_src" "$ponytail_dst/SKILL.md"
    fi
  fi

  # ponytail: new profiles don't inherit API keys. Copy default auth.json if
  # this profile's is empty so model calls don't fail with "no API keys".
  if [[ -f "$HERMES_HOME/auth.json" ]]; then
    profile_auth="$HERMES_HOME/profiles/$profile/auth.json"
    if [[ ! -s "$profile_auth" ]] || [[ "$(wc -c < "$profile_auth")" -lt 50 ]]; then
      cp "$HERMES_HOME/auth.json" "$profile_auth"
      echo "  · inherited auth.json from default profile"
    fi
  fi

  if [[ "$WITH_ALIAS" == 1 ]]; then
    hermes profile alias "$profile" 2>/dev/null || true
  fi
done

echo ">>> done. Run a smoke test with:"
echo "    bash scripts/smoke-test.sh"