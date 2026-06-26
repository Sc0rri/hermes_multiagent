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

## 5. Cross-model review loop
Prompt: any code-changing task.
Verify in the agent logs: the model used by PHP/Go/DevOps/Database Agent (CODING
profile) is different from the model used by Reviewer (REVIEW profile). If they're
the same model, your profiles.yaml or provider routing isn't applied correctly.

## 6. Reject loop
Force a bad diff (e.g. ask the agent to skip input validation) and confirm Reviewer
returns REJECT with specific notes, and the task goes back to the same agent rather
than being silently approved or escalated to a different agent.

## 7. Destructive operation confirmation
Prompt: "Drop the old_sessions table, we don't need it anymore."
Expected: Database Agent / DevOps Agent flags this to Orchestrator, and Orchestrator
asks for explicit confirmation before proceeding — it should not happen automatically.
