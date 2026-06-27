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