#!/usr/bin/env bash
# orchestrate.sh — full-stack dev pipeline via Hermes profiles.
#
# Usage:
#   orchestrate.sh "Fix LoginController null pointer on empty email"
#   orchestrate.sh -p php-dev "Add a GET /api/users/{id} endpoint"
#   orchestrate.sh --plan "Add JWT auth to the API"        # planner only
#   orchestrate.sh --review --diff /tmp/x.diff             # review existing diff
#
# Models (override via env HERMES_<ROLE>_MODEL):
#   HERMES_ROUTER_MODEL  — classification (small, fast)
#   HERMES_CODING_MODEL  — php-dev / go-dev / database-dev / devops-dev
#   HERMES_REVIEW_MODEL  — reviewer (always ≠ coding)
#   HERMES_SECURITY_MODEL — reviewer pass: security
#   HERMES_PERF_MODEL    — reviewer pass: performance
#   HERMES_ARCH_MODEL    — reviewer pass: architecture

set -euo pipefail

PROFILE=""
PLAN_ONLY=0
REVIEW_ONLY=0
DIFF_FILE=""
TASK="${*:?usage: orchestrate.sh [-p profile] [--plan] [--review --diff FILE] <task description>}"

# ponytail: sensible free-tier defaults; user overrides env when needed.
# Verified live 2026-06 against https://openrouter.ai/openrouter/free.
# Gemma 4 31B responded 200; qwen-coder and gpt-oss-120b were rate-limited
# upstream (429) — switch to them via env once their rate limits clear.
ROUTER_MODEL="${HERMES_ROUTER_MODEL:-openrouter/google/gemma-4-31b-it:free}"
CODING_MODEL="${HERMES_CODING_MODEL:-openrouter/qwen/qwen3-coder:free}"
REVIEW_MODEL="${HERMES_REVIEW_MODEL:-openrouter/google/gemma-4-31b-it:free}"
SECURITY_MODEL="${HERMES_SECURITY_MODEL:-openrouter/google/gemma-4-31b-it:free}"
PERF_MODEL="${HERMES_PERF_MODEL:-openrouter/google/gemma-4-31b-it:free}"
ARCH_MODEL="${HERMES_ARCH_MODEL:-openrouter/google/gemma-4-31b-it:free}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) PROFILE="$2"; shift 2;;
    --plan) PLAN_ONLY=1; shift;;
    --review) REVIEW_ONLY=1; shift;;
    --diff) DIFF_FILE="$2"; shift 2;;
    --) shift; TASK="$*"; break;;
    *) shift;;
  esac
done

# ponytail: one helper for the only repeated action — invoke a profile.
hermes_call() {
  local profile="$1" model="$2" prompt="$3"
  hermes -p "$profile" --model "$model" --skills "$profile" \
    chat -q "$prompt" --yolo --quiet 2>&1
}

# ---- review-only mode: caller already has a diff ----
if [[ "$REVIEW_ONLY" == 1 ]]; then
  [[ -z "$DIFF_FILE" ]] && { echo "ERROR: --review requires --diff FILE"; exit 2; }
  diff_body="$(cat "$DIFF_FILE")"
  hermes_call reviewer "$REVIEW_MODEL" \
    "Review this diff. Pass: review.

Diff:
\`\`\`
$diff_body
\`\`\`"
  exit $?
fi

# ---- direct profile mode: caller already routed ----
if [[ -n "$PROFILE" ]]; then
  output="$(hermes_call "$PROFILE" "$CODING_MODEL" "$TASK")"
  echo "$output"
  if [[ "$PROFILE" =~ dev$ ]]; then
    hermes_call reviewer "$REVIEW_MODEL" \
      "Review the diff produced in the previous step. Pass: review.

Task: $TASK

Output to review:
\`\`\`
$output
\`\`\`"
  fi
  exit $?
fi

# ---- plan-only mode ----
if [[ "$PLAN_ONLY" == 1 ]]; then
  hermes_call planner "$ROUTER_MODEL" "$TASK"
  exit $?
fi

# ---- full pipeline: classify then dispatch ----
echo ">>> classifying task with router model $ROUTER_MODEL" >&2
envelope="$(hermes_call orchestrator "$ROUTER_MODEL" \
  "Classify this task and return ONLY a JSON envelope (no markdown, no preamble).

Task: $TASK")"

# ponytail: strip ```json fences if the model wrapped its reply.
envelope="$(printf '%s' "$envelope" | sed -n '/^{/,/^}/p' | tr -d '\n')"
echo ">>> envelope: $envelope" >&2

# ponytail: no jq dep — extract pipeline + complexity + policy with regex.
# Each field is on its own line in the envelope (we'll pretty-print before parsing).
pretty="$(printf '%s' "$envelope" | python3 -c 'import sys,json; print(json.dumps(json.loads(sys.stdin.read()), indent=2))' 2>/dev/null || echo "$envelope")"
pipeline="$(printf '%s\n' "$pretty" | awk -F'"' '/"pipeline"/{for(i=1;i<=NF;i++) if($i~/,/) print $i}' | tr -d ' ,[]"' | grep -v '^$')"
complexity="$(printf '%s\n' "$pretty" | awk -F'"' '/"complexity"/{print $(NF-1)}')"
policy="$(printf '%s\n' "$pretty" | awk -F'"' '/"review_policy"/{print $(NF-1)}')"

if [[ -z "$pipeline" ]]; then
  echo "ERROR: orchestrator did not return a pipeline. Reply was:"
  echo "$envelope"
  exit 1
fi

echo ">>> complexity=$complexity  policy=$policy  pipeline: $(echo $pipeline | tr '\n' ' ')" >&2

# ponytail: the loop is the entire pipeline. No helper, no state machine.
prev_output=""
for step in $pipeline; do
  echo ">>> running profile: $step" >&2
  case "$step" in
    researcher|planner|orchestrator)
      model="$ROUTER_MODEL";;
    reviewer)
      model="$REVIEW_MODEL"
      # ponytail: pass the policy to reviewer as a one-line header.
      review_args="Pass: review. Review policy: $policy."
      [[ "$policy" == "security" ]] && { review_args="Pass: security."; model="$SECURITY_MODEL"; }
      [[ "$policy" == "performance" ]] && { review_args="Pass: performance."; model="$PERF_MODEL"; }
      [[ "$policy" == "architecture" ]] && { review_args="Pass: architecture."; model="$ARCH_MODEL"; }
      step_prompt="$review_args

Previous step output:
\`\`\`
$prev_output
\`\`\`"
      prev_output="$(hermes_call "$step" "$model" "$step_prompt")"
      echo "$prev_output"
      continue
      ;;
    *)
      model="$CODING_MODEL";;
  esac
  # ponytail: each non-reviewer step sees the previous output verbatim.
  if [[ -n "$prev_output" ]]; then
    step_prompt="$TASK

Context from the previous pipeline step ($prev_output_summary):
\`\`\`
$prev_output
\`\`\`"
  else
    step_prompt="$TASK"
  fi
  prev_output="$(hermes_call "$step" "$model" "$step_prompt")"
done

echo ">>> pipeline complete" >&2