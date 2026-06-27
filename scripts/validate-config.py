#!/usr/bin/env python3
"""validate-config.py — check config/*.yaml is internally consistent.

Validates:
- Every profile in capabilities.yaml exists in models.yaml (and vice versa).
- Routing pipelines reference existing profiles.
- Routing keywords are non-empty.
- Models have primary set.
- Cost-policy complexity keys are valid.

Exit 0 = OK, exit 1 = errors found.
"""
import sys, yaml
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
cfg_dir = REPO / "config"

caps = yaml.safe_load(open(cfg_dir / "capabilities.yaml"))["profiles"]
models = yaml.safe_load(open(cfg_dir / "models.yaml"))["profiles"]
routing = yaml.safe_load(open(cfg_dir / "routing.yaml"))["routes"]
policy = yaml.safe_load(open(cfg_dir / "review-policy.yaml"))
cost = yaml.safe_load(open(cfg_dir / "cost-policy.yaml"))["complexity"]

errs = []

# 1. capabilities <-> models parity
for p in caps:
    if p not in models:
        errs.append(f"capabilities.yaml: profile '{p}' not in models.yaml")
for p in models:
    if p not in caps:
        errs.append(f"models.yaml: profile '{p}' not in capabilities.yaml")

# 2. Routing pipelines reference existing profiles; keywords non-empty
for name, r in routing.items():
    for step in r.get("pipeline", []):
        if step not in caps:
            errs.append(f"routing.yaml[{name}]: pipeline step '{step}' not in capabilities.yaml")
    for kw in r.get("keywords", []):
        if not str(kw).strip():
            errs.append(f"routing.yaml[{name}]: empty keyword")

# 3. Models have primary
for p, m in models.items():
    if not m.get("primary"):
        errs.append(f"models.yaml[{p}]: no primary model")

# 4. Cost policy keys
for k in cost:
    if k not in ("low", "medium", "high"):
        errs.append(f"cost-policy.yaml: unknown complexity '{k}'")

# Note: review-policy "passes" (review/security/performance/architecture) are
# pass names consumed by the reviewer skill — NOT profile names. We don't
# validate them as profiles on purpose.

if errs:
    print("FAIL")
    for e in errs:
        print(f"  - {e}")
    sys.exit(1)
print(f"OK: {len(caps)} profiles, {len(routing)} routes, {len(policy['policies'])} policies")