#!/usr/bin/env python3
"""explain.py — print why a task routes where it does, no LLM.

Usage:
    python3 scripts/explain.py "Fix null pointer in LoginController"
"""
import re, sys, yaml
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
cfg_dir = REPO / "config"

routing = yaml.safe_load(open(cfg_dir / "routing.yaml"))["routes"]
caps = yaml.safe_load(open(cfg_dir / "capabilities.yaml"))["profiles"]
cost = yaml.safe_load(open(cfg_dir / "cost-policy.yaml"))["complexity"]
review = yaml.safe_load(open(cfg_dir / "review-policy.yaml"))["policies"]


def kw_match(task_l: str, kw: str) -> bool:
    """Match keyword as whole word (case-insensitive). Avoids 'gin' matching 'Login'."""
    return bool(re.search(r"\b" + re.escape(kw) + r"\b", task_l))


def match(task: str):
    task_l = task.lower()
    hits = []
    for name, r in routing.items():
        matched_kw = [k for k in r["keywords"] if kw_match(task_l, k)]
        if matched_kw:
            hits.append((name, matched_kw, r["pipeline"]))
    return hits


def pick_policy(task: str) -> str:
    task_l = task.lower()
    prio = ["architecture", "security", "performance", "trivial", "normal"]
    for p in prio:
        pol = review[p]
        if any(kw_match(task_l, kw) for kw in pol.get("keywords", [])):
            return p
    return "normal"


def pick_complexity(task: str) -> str:
    task_l = task.lower()
    sec = any(kw_match(task_l, k) for k in review["security"].get("keywords", []))
    arch = any(kw_match(task_l, k) for k in review["architecture"].get("keywords", []))
    perf = any(kw_match(task_l, k) for k in review["performance"].get("keywords", []))
    if sec or arch or perf or kw_match(task_l, "refactor") or kw_match(task_l, "new service"):
        return "high"
    if any(kw_match(task_l, k) for k in ("add", "implement", "build")):
        return "medium"
    return "low"


def main():
    if len(sys.argv) < 2:
        print("usage: explain.py <task>")
        sys.exit(2)
    task = " ".join(sys.argv[1:])
    print(f"Task: {task}")
    print()

    hits = match(task)
    if not hits:
        print("No route matched. Default: orchestrator asks user.")
        return

    pipeline = []
    for name, kws, ppl in hits:
        print(f"  matched route '{name}': keywords {kws}")
        pipeline.extend(ppl)
    pipeline = list(dict.fromkeys(pipeline))
    print()
    print(f"Pipeline: {' -> '.join(pipeline)}")
    for step in pipeline:
        if step in caps:
            c = caps[step]
            desc = c.get("languages", c.get("databases", c.get("mode", c.get("role", ""))))
            print(f"  - {step}: {desc}")

    policy = pick_policy(task)
    complexity = pick_complexity(task)
    print()
    print(f"Review policy: {policy}")
    print(f"Complexity: {complexity} (budget: {cost[complexity]['max_calls']} LLM calls)")


if __name__ == "__main__":
    main()