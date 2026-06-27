#!/usr/bin/env bash
# smoke-test.sh — verify the pipeline wires together end-to-end.
#
# Runs three tiny scenarios. None of them touch real project files —
# the orchestrator/profile calls return a description only, not a diff.
# Use this after install.sh to confirm routing, model swap, and
# review pass all work.

set -euo pipefail

cd "$(dirname "$0")/.."

run() {
  local label="$1"; shift
  echo
  echo "===== $label ====="
  bash scripts/orchestrate.sh "$@"
}

# 1. Plain bug fix — should route php-dev → reviewer (normal policy).
run "Bug fix (LoginController)" \
  "Fix the bug in LoginController: it throws a null pointer on empty email. PSR-12."

# 2. Auth feature — should force policy=security.
run "Auth feature (forces security review)" \
  "Add JWT authentication to the API. Login endpoint checks password against users table."

# 3. Docs only — should route docs-dev, no reviewer.
run "Docs-only task" \
  "Update README.md to document the new /api/users endpoint."

echo
echo "===== smoke test complete ====="