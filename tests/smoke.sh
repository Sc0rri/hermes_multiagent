#!/usr/bin/env bash
# smoke.sh — validate config + simulate routing on canned tasks.
# No LLM calls. Fast. Run before every commit.

set -euo pipefail
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
]

ok = fail = 0
for task, expected in cases:
    matched = [name for name, r in routing.items()
               if any(kw_match(task.lower(), k) for k in r["keywords"])]
    pipeline = []
    for m in matched:
        pipeline.extend(routing[m]["pipeline"])
    pipeline = list(dict.fromkeys(pipeline))
    if expected == "ask":
        status = "OK" if not matched else "FAIL"
    else:
        _, want = expected.split(":")
        status = "OK" if want in matched else "FAIL"
    print(f"  [{status}] '{task}' (expected: {expected})")
    print(f"         matched: {matched}  pipeline: {pipeline}")
    if status == "OK":
        ok += 1
    else:
        fail += 1
print()
print(f"{ok} ok / {fail} fail")
sys.exit(0 if fail == 0 else 1)
PY