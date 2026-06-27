#!/usr/bin/env bash
# install.sh — create the 9 profiles and install each role's skill.
# Idempotent. Run again after `git pull`.
#
# The orchestrator profile does the routing itself (see its SKILL.md).
# It uses `hermes -p <profile> chat -q ...` to dispatch, so sub-profiles
# just need their skill loaded — no per-profile model pinning here.
# Override a profile's model with `hermes -p X config set model.default M`.

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PROFILES=(orchestrator planner researcher php-dev go-dev database-dev devops-dev docs-dev reviewer)

for profile in "${PROFILES[@]}"; do
  if ! hermes profile list 2>/dev/null | grep -q "^[[:space:]]*$profile\b"; then
    hermes profile create "$profile" >/dev/null
  fi

  src="$REPO_ROOT/skills/$profile/SKILL.md"
  if [[ -f "$src" ]]; then
    dst="$HERMES_HOME/profiles/$profile/skills/$profile"
    mkdir -p "$dst"
    cp "$src" "$dst/SKILL.md"
  fi

  # ponytail: _ponytail is shared base discipline for code-writing profiles.
  if [[ "$profile" =~ -dev$ ]] || [[ "$profile" == "reviewer" ]]; then
    dst="$HERMES_HOME/profiles/$profile/skills/_ponytail"
    mkdir -p "$dst"
    cp "$REPO_ROOT/skills/_ponytail/SKILL.md" "$dst/SKILL.md"
  fi

  # ponytail: new profiles have empty auth.json — copy from default so model
  # calls don't fail with "no API keys".
  if [[ ! -s "$HERMES_HOME/profiles/$profile/auth.json" ]] \
     && [[ -s "$HERMES_HOME/auth.json" ]]; then
    cp "$HERMES_HOME/auth.json" "$HERMES_HOME/profiles/$profile/auth.json"
  fi
done

echo ">>> 9 profiles installed. Use with:"
echo "    hermes -p orchestrator chat"
echo "    (or pick a sub-profile directly: hermes -p php-dev chat)"