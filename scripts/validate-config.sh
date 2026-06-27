#!/usr/bin/env bash
# validate-config.sh — wrapper for validate-config.py.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/validate-config.py