#!/usr/bin/env bash
# smoke.sh — validate config + simulate routing on canned tasks.
# No LLM calls. Fast. Run before every commit.
#
# Note: pipefail is intentionally NOT set — orchestrator.sh returns
# non-zero from the (stubbed) hermes invocation, which would mask the
# real test result (the stdout line we grep for).

set -eu
cd "$(dirname "$0")/.."

echo "=== validate-config ==="
bash scripts/validate-config.sh

echo
echo "=== routing simulation ==="
python3 - <<'PY'
import re, sys, yaml
routing = yaml.safe_load(open("config/routing.yaml"))["routes"]
caps = yaml.safe_load(open("config/capabilities.yaml"))["profiles"]

def kw_match(t, k):
    return bool(re.search(r"\b" + re.escape(k) + r"\b", t))

# (task, expected: "route:<name>" or "ask")
cases = [
    ("Fix null pointer in LoginController", "ask"),         # no stack cue → orchestrator asks
    ("Add a fiber endpoint in our Go service", "route:go"),
    ("Add an index to speed up orders query", "route:database"),
    ("Update README to document /api/users", "route:docs"),
    ("Check correctness of documentation and tests", "route:auditor"),
    ("What is the latest Yii2 version", "route:research"),
    ("Drop the old_sessions table", "ask"),                 # destructive, no stack cue
    ("Add redis caching for user sessions", "ask"),          # no stack cue → orchestrator asks
    ("Add Laravel redis caching for user sessions", "route:php"),  # both cues → php-dev
    # bug-report cases — must be single-route now, no pipeline union
    ("Fix cargo build error in src/parser.rs", "route:rust"),  # cargo=cue, build=ignored
    ("What is the latest Yii2 version", "route:research"),      # research > php (priority 20)
    ("Implement user authentication", "route:new_feature"),    # build+ → planner
    ("Add feature for export to CSV", "route:new_feature"),     # add feature+ → planner
]

ok = fail = 0
# ponytail: highest priority wins. Tie at top priority = ask. No
# union-of-pipelines (that produced nonsense like rust-dev + php-dev
# when both 'cargo' and 'build' matched).
for task, expected in cases:
    matched = []
    for name, r in routing.items():
        if any(kw_match(task.lower(), k) for k in r["keywords"]):
            matched.append((name, r.get("priority", 0)))
    if matched:
        matched.sort(key=lambda x: -x[1])
        # tie at top priority → ask
        top_prio = matched[0][1]
        tied = [m for m in matched if m[1] == top_prio]
        pipeline = list(dict.fromkeys(routing[tied[0][0]]["pipeline"])) \
            if len(tied) == 1 else []
    else:
        pipeline = []
    if expected == "ask":
        status = "OK" if (not matched or len(tied) > 1) else "FAIL"
    else:
        _, want = expected.split(":")
        status = "OK" if len(tied) == 1 and tied[0][0] == want else "FAIL"
    shown = matched[0][0] if matched else None
    print(f"  [{status}] '{task}' (expected: {expected})")
    print(f"         matched: {matched}  picked: {shown}  pipeline: {pipeline}")
    if status == "OK":
        ok += 1
    else:
        fail += 1
print()
print(f"{ok} ok / {fail} fail")
sys.exit(0 if fail == 0 else 1)
PY

echo
echo "=== plugin registration + orchestrator toolset gates ==="
python3 <<'PY'
import yaml, sys
ok, fail = 0, 0
def check(cond, label):
    global ok, fail
    if cond:
        print(f"  [OK] {label}"); ok += 1
    else:
        print(f"  [FAIL] {label}"); fail += 1

# 1. global config: hermes_multiagent in plugins.enabled
g = yaml.safe_load(open('/home/almes/.hermes/config.yaml')) if False else yaml.safe_load(open('/home/alex/.hermes/config.yaml'))
enabled = g.get('plugins', {}).get('enabled', []) or []
check('hermes_multiagent' in enabled,
      "global plugins.enabled contains hermes_multiagent")

# 2. orchestrator disabled_toolsets covers all file/search/skills tools
o = yaml.safe_load(open('/home/alex/.hermes/profiles/orchestrator/config.yaml'))
dt = set(o.get('agent', {}).get('disabled_toolsets', []) or [])
must_disable = ['terminal', 'file', 'search', 'session_search',
                'skills', 'memory', 'todo', 'project', 'process',
                'browser', 'code_execution', 'delegation', 'cronjob']
for t in must_disable:
    check(t in dt, f"orchestrator disables toolset '{t}'")
check('clarify' not in dt, "orchestrator keeps 'clarify' enabled")
check('read_file' in dt or 'file' in dt,
      "orchestrator disables read_file (via 'file' toolset)")

# 3. plugin file is present in ~/.hermes/plugins
import os
plug_dir = '/home/alex/.hermes/plugins/hermes_multiagent'
check(os.path.isdir(plug_dir), f"plugin dir exists: {plug_dir}")
check(os.path.isfile(os.path.join(plug_dir, 'plugin.yaml')),
      "plugin.yaml is present")
check(os.path.isfile(os.path.join(plug_dir, '__init__.py')),
      "__init__.py is present")

print()
print(f"{ok} ok / {fail} fail")
sys.exit(0 if fail == 0 else 1)
PY
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
check(json.dumps(DISPATCH_PROFILE_SCHEMA) and "hermes" in DISPATCH_PROFILE_SCHEMA["description"],
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