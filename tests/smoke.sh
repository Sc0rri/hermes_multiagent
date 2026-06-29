#!/usr/bin/env bash
# smoke.sh — validate config + simulate routing on canned tasks +
# check wrapper behaviour + check plugin registration. No LLM calls.
# Fast. Run before every commit.

set -eu

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

echo "=== validate-config ==="
python3 scripts/validate-config.py || exit 1

echo
echo "=== live config matches models.yaml (no drift) ==="
python3 <<'PY'
"""If config/models.yaml primary differs from the live per-profile
config.yaml, install.sh was never re-run after a change and the
profile is pinned to the old (possibly dead) model."""
import yaml, sys, os
hermes_home = os.path.expanduser('~/.hermes')
ok, fail = 0, 0
def check(cond, label):
    global ok, fail
    if cond:
        print(f"  [OK] {label}"); ok += 1
    else:
        print(f"  [FAIL] {label}"); fail += 1

repo_models = yaml.safe_load(open('config/models.yaml'))['profiles']
for prof, m in repo_models.items():
    p = os.path.join(hermes_home, 'profiles', prof, 'config.yaml')
    if not os.path.exists(p):
        print(f"  [SKIP] {prof}: no live config at {p}")
        continue
    live = yaml.safe_load(open(p))
    primary_repo = m['primary']
    primary_live = live['model']['default']
    check(primary_repo == primary_live,
          f"{prof}: repo={primary_repo} live={primary_live}")

print()
print(f"{ok} ok / {fail} fail")
sys.exit(0 if fail == 0 else 1)
PY

echo
echo "=== routing simulation ==="
python3 - <<'PY'
"""Simulate routing on canned tasks. Catches keyword over-matching and
ties broken between capabilities/models/routing."""
import yaml
from pathlib import Path
import re

ROOT = Path("config")
routes = yaml.safe_load((ROOT / "routing.yaml").read_text())["routes"]
caps = yaml.safe_load((ROOT / "capabilities.yaml").read_text())
mods = yaml.safe_load((ROOT / "models.yaml").read_text())["profiles"]

# Build profile → capabilities stack-membership lookup.
prof_to_stacks = {}
for stack, info in caps.items():
    if stack == "_comment":
        continue
    for prof in info.get("profiles", []):
        prof_to_stacks.setdefault(prof, set()).add(stack)

cases = [
    ("Fix cargo build error in src/parser.rs", "rust"),
    ("Implement user authentication", "new_feature"),
    ("Add feature for export to CSV", "new_feature"),
    ("What is the latest Yii2 version", "research"),
    ("Build a new microservice", "new_feature"),
    ("Fix the PHP login flow", "php"),
    ("Write a Go HTTP server", "go"),
    ("Add a postgres index on users.email", "database"),
    ("Setup docker-compose for staging", "devops"),
    ("Update the README", "docs"),
    ("Check naming in this codebase", "auditor"),
    ("Refactor the auth module", "new_feature"),
    ("Debug slow query", "database"),
    ("Optimize slow Postgres query with index", "database"),
]
ok, fail = 0, 0
for task, expected in cases:
    hits = []
    for route_name, route in routes.items():
        if route_name.startswith("_") or route_name == "default":
            continue
        keywords = route.get("keywords", [])
        priority = route.get("priority", 0)
        for kw in keywords:
            # word-boundary match, case-insensitive
            if re.search(rf"(^|[^a-z0-9]){re.escape(kw)}([^a-z0-9]|$)",
                         task.lower()):
                hits.append((route_name, priority))
                break
    # Sort by priority desc, take top
    hits.sort(key=lambda x: -x[1])
    if expected == "ask":
        if not hits or len(set(p for _, p in hits)) > 1:
            status = "OK"
        else:
            status = "FAIL"
    else:
        if hits and hits[0][0] == expected:
            status = "OK"
        else:
            # Check if expected is even in top priority tier
            top = set(h for h, _ in hits if _ == hits[0][1])
            if expected in top:
                status = "OK"
            else:
                status = "FAIL"
    shown = hits[0][0] if hits else None
    pipeline = routes[shown]["pipeline"] if shown else []
    print(f"  [{status}] '{task}' (expected: {expected})")
    print(f"         matched: {hits}  picked: {shown}  pipeline: {pipeline}")
    if status == "OK":
        ok += 1
    else:
        fail += 1
print()
print(f"{ok} ok / {fail} fail")
import sys as _s
_s.exit(0 if fail == 0 else 1)
PY

echo
echo "=== orchestrator.sh wrapper (deterministic router — recommended path) ==="

# ponytail: build a temp composer.json fixture so the cwd-marker test
# works on any host (was hardcoded to the dev's local project checkout).
WRAPPER="$REPO_ROOT/scripts/orchestrator.sh"
FIXTURE="$(mktemp -d)"
mkdir -p "$FIXTURE/src"
echo '{"require":{"yiisoft/yii2":"~2.0"}}' > "$FIXTURE/src/composer.json"

cd "$FIXTURE"
HERMES_BIN="echo hermes-stub" \
  bash "$WRAPPER" "Fix the bug" 2>&1 \
  | grep -q "→ Detected php via php marker" \
  && echo "  [OK] cwd marker detection (composer.json in src/)" \
  || echo "  [FAIL] cwd marker broken"
cd "$REPO_ROOT" >/dev/null

# keyword routing
HERMES_BIN="echo hermes-stub" \
  bash "$WRAPPER" "Build a new microservice" 2>&1 \
  | grep -q "→ Matched route 'new_feature'" \
  && echo "  [OK] new_feature route for 'build'" \
  || echo "  [FAIL] new_feature route broken"

# priority: research > php for "What is the latest Yii2 version"
HERMES_BIN="echo hermes-stub" \
  bash "$WRAPPER" "What is the latest yii2 release" 2>&1 \
  | grep -q "→ Matched route 'research'" \
  && echo "  [OK] research priority 20 wins over php cue" \
  || echo "  [FAIL] priority logic broken"

# ambiguous: no marker, no cue → ask user
AMB="$(mktemp -d)"
cd "$AMB"
HERMES_BIN="echo hermes-stub" \
  bash "$WRAPPER" "fix the thing" 2>&1 \
  | grep -q "No route matched" \
  && echo "  [OK] ambiguous task asks user (exit 2)" \
  || echo "  [FAIL] ambiguous handling broken"
cd "$REPO_ROOT" >/dev/null

rm -rf "$FIXTURE" "$AMB"

echo
echo "=== plugin registration + orchestrator toolset gates ==="
python3 <<'PY'
import yaml, sys, os
ok, fail = 0, 0
def check(cond, label):
    global ok, fail
    if cond:
        print(f"  [OK] {label}"); ok += 1
    else:
        print(f"  [FAIL] {label}"); fail += 1

g = yaml.safe_load(open(os.path.expanduser('~/.hermes/config.yaml')))
enabled = g.get('plugins', {}).get('enabled', []) or []
check('hermes_multiagent' in enabled,
      "global plugins.enabled contains hermes_multiagent")

o = yaml.safe_load(open(os.path.expanduser('~/.hermes/profiles/orchestrator/config.yaml')))
dt = set(o.get('agent', {}).get('disabled_toolsets', []) or [])
must_disable = ['terminal', 'file', 'search', 'session_search',
                'skills', 'memory', 'todo', 'project', 'process',
                'browser', 'code_execution', 'delegation', 'cronjob']
for t in must_disable:
    check(t in dt, f"orchestrator disables toolset '{t}'")
check('clarify' not in dt, "orchestrator keeps 'clarify' enabled")

plug_dir = os.path.expanduser('~/.hermes/plugins/hermes_multiagent')
check(os.path.isdir(plug_dir), f"plugin dir exists: {plug_dir}")
check(os.path.isfile(os.path.join(plug_dir, 'plugin.yaml')),
      "plugin.yaml is present")
check(os.path.isfile(os.path.join(plug_dir, '__init__.py')),
      "__init__.py is present")

print()
print(f"{ok} ok / {fail} fail")
sys.exit(0 if fail == 0 else 1)
PY

echo
echo "=== dispatch_profile plugin handler ==="
python3 <<'PY'
import json, sys
sys.path.insert(0, "plugins")
from hermes_multiagent.tools import _handle_dispatch_profile, DISPATCH_PROFILE_SCHEMA, TOOLS

ok, fail = 0, 0
def check(cond, label):
    global ok, fail
    if cond:
        print(f"  [OK] {label}"); ok += 1
    else:
        print(f"  [FAIL] {label}"); fail += 1

check(TOOLS == [("dispatch_profile", DISPATCH_PROFILE_SCHEMA, _handle_dispatch_profile, "🔀")],
      "TOOLS tuple registered exactly once")
check(DISPATCH_PROFILE_SCHEMA["parameters"]["required"] == ["profile", "task"],
      "schema requires profile + task")
check("hermes" in DISPATCH_PROFILE_SCHEMA["description"],
      "schema description mentions hermes")

out = json.loads(_handle_dispatch_profile({"task": "x"}))
check(out["ok"] is False and "profile" in out["error"], "missing profile → JSON error")

out = json.loads(_handle_dispatch_profile({"profile": "x"}))
check(out["ok"] is False and "task" in out["error"], "missing task → JSON error")

out = json.loads(_handle_dispatch_profile({"profile": "no-such-profile-xyz", "task": "y"}))
check("exit_code" in out and "stderr" in out, "real dispatch returns exit_code + stderr")

print()
print(f"{ok} ok / {fail} fail")
sys.exit(0 if fail == 0 else 1)
PY