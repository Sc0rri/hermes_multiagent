#!/usr/bin/env bash
# orchestrator.sh — deterministic router that bypasses the LLM
# orchestrator profile. Use when the LLM orchestrator starts answering
# on its own or when the platform layer doesn't surface the
# dispatch_profile plugin tool in the model's tool palette.
#
# History: this wrapper was the primary path in v0.19.8. v0.19.9
# replaced it with a Hermes plugin tool (dispatch_profile) under
# the assumption that a model-side tool would be more flexible.
# v0.19.10 showed that the plugin tool, while registered correctly
# in plugins.enabled and visible in `hermes plugins list`, did not
# appear in the model's available tool palette on the user's
# installation. Wrapper came back.
#
# Usage:
#   bash scripts/orchestrator.sh "Fix the YAML config error"
#   bash scripts/orchestrator.sh "Add redis caching for sessions"   # no stack cue -> asks
#
# Exit codes:
#   0  = dispatched
#   2  = ambiguous, ask user (printed to stdout)
#   1  = error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES="${HERMES_BIN:-hermes}"

if [[ $# -lt 1 ]]; then
    echo "usage: orchestrator.sh <task>" >&2
    exit 1
fi
task="$*"
task_l="$(echo "$task" | tr '[:upper:]' '[:lower:]')"

# Step 1: stack detection via filesystem markers. Single shell pipeline,
# no LLM. Works for any project the user opens. We check both the cwd
# AND src/ (common in Yii2 layouts where composer.json is in src/).
cwd="$(pwd)"
markers=()
for base in "$cwd" "$cwd/src"; do
    [[ -f "$base/composer.json" ]] && markers+=(php) && break
done
[[ -f "$cwd/go.mod" ]]        && markers+=(go)
[[ -f "$cwd/Cargo.toml" ]]    && markers+=(rust)
[[ -f "$cwd/package.json" ]]  && markers+=(js)

if [[ ${#markers[@]} -eq 1 ]]; then
    stack="${markers[0]}"
    case "$stack" in
        php) profile="php-dev"   ;;
        go)  profile="go-dev"    ;;
        rust) profile="rust-dev" ;;
        js)  profile="researcher" ;;  # read-only default — no JS profile yet
    esac
    echo "→ Detected $stack via $stack marker; dispatching to $profile"
    "$HERMES" -p "$profile" chat -q "$task" --yolo --quiet
    exit $?
fi

# Step 2: keyword scan, priority order. Mirrors config/routing.yaml.
declare -A priority=(
    [research]=20   [php]=10        [go]=10    [rust]=10
    [database]=10   [devops]=10     [docs]=5  [auditor]=5
    [new_feature]=0
)

best="" best_prio=0
declare -A routes=(
    [research]="researcher"
    [php]="php-dev"
    [go]="go-dev"
    [rust]="rust-dev"
    [database]="database-dev"
    [devops]="devops-dev"
    [docs]="docs-dev"
    [auditor]="auditor"
    [new_feature]="planner"  # planner decides the actual stack later
)
declare -A keywords=(
    [research]="what is latest version library package framework version"
    [php]="php yii2 laravel composer blade twig eloquent opencart vqmod"
    [go]="go golang fiber gin grpc goroutine errgroup"
    [rust]="rust cargo rustc tokio wasm cdylib serde ownership borrow"
    [database]="schema migration query index sql mysql postgres sqlite"
    [devops]="docker nginx systemd ci deploy ansible k8s helm"
    [docs]="readme changelog docblock api docs"
    [auditor]="check audit review code naming lint consistency correctness verify"
    [new_feature]="add feature implement build new service refactor across"
)

for route in "${!priority[@]}"; do
    for kw in ${keywords[$route]}; do
        if [[ "$task_l" =~ (^|[^a-z0-9])${kw}([^a-z0-9]|$) ]]; then
            p="${priority[$route]}"
            if (( p >= best_prio )); then
                best="$route"
                best_prio=$p
            fi
            break
        fi
    done
done

if [[ -n "$best" ]]; then
    profile="${routes[$best]}"
    echo "→ Matched route '$best' (priority $best_prio); dispatching to $profile"
    "$HERMES" -p "$profile" chat -q "$task" --yolo --quiet
    exit $?
fi

# Step 3: ask the user. Print to stderr so it doesn't get piped into
# another command by accident.
cat >&2 <<EOF
No route matched the task and no filesystem marker was found in:
  $cwd
Either:
  - run from inside the project root (cwd should contain composer.json,
    go.mod, Cargo.toml, or package.json), or
  - include a stack cue in the task ("Fix the PHP ...", "Build a Go
    service", "Cargo build error", etc.).
EOF
exit 2