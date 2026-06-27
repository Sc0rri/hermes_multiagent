# Smoke Tests

Run these manually after installing the pack, to confirm routing works before
trusting it on real tasks.

## 1. Bug fix routing
Prompt: "Fix the bug in LoginController, it throws a null pointer on empty email."
Expected chain: Research Agent (only if needed) → PHP Agent → Reviewer → Final.
Should NOT trigger: Planner, DevOps Agent, Docs Agent.

## 2. New feature routing
Prompt: "Add JWT authentication to the API."
Expected chain: Planner → Research Agent → PHP/Go Agent → Reviewer → Docs Agent → Final.

## 3. Docs-only routing
Prompt: "Write a README for this project."
Expected chain: Docs Agent → Final. Nothing else should run.

## 4. Database routing
Prompt: "Add an index to speed up the orders query, it's doing a full table scan."
Expected chain: Database Agent → Reviewer → Final.

## 5. Cross-model review — passes match policy
Prompt: "Add a login endpoint that checks password against the users table."
Expected: Orchestrator/Planner selects the `security` policy (keyword: auth/login/
password). Verify in the logs that Reviewer runs Pass 1 (REVIEW) **and** Pass 2
(SECURITY), each on a different model than CODING and from each other.

Prompt: "Optimize the orders listing query, it's slow with 100k rows."
Expected: `performance` policy — Pass 1 (REVIEW) + Pass 3 (PERFORMANCE).

Prompt: "Fix a typo in the error message."
Expected: `trivial` policy — Pass 1 (REVIEW) only.

## 6. Reject loop with multiple passes
Force a bad diff that both skips input validation and adds an obvious N+1 query,
in a task that triggers `architecture` or `consensus` policy. Confirm Orchestrator
aggregates REJECT notes from all passes into a single batch back to the executor,
rather than looping pass-by-pass.

## 7. Tie-break, not a second full pass
If you can force a pass to return `Confidence: low` (e.g. give it a deliberately
ambiguous diff), confirm Orchestrator asks a single focused tie-break question to a
third model rather than re-running a full review pass.

## 8. Destructive operation confirmation
Prompt: "Drop the old_sessions table, we don't need it anymore."
Expected: Database Agent / DevOps Agent flags this to Orchestrator, and Orchestrator
asks for explicit confirmation before proceeding — it should not happen automatically.
