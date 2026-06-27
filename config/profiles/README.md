# Model Profiles

Each file here is one profile. Agents reference profiles by name only
(e.g. `profile: CODING`) — never a specific model directly. When a free model
disappears from OpenRouter or Ollama Cloud, you edit exactly one file, not every
agent's SKILL.md.

| File | Profile name | Used by |
|---|---|---|
| `fast.yaml` | FAST | Orchestrator |
| `coding.yaml` | CODING | PHP Agent, Go Agent, Database Agent, DevOps Agent |
| `coding_alt.yaml` | CODING_ALT | Same agents, only for `dual-check` tasks flagged by Planner |
| `review.yaml` | REVIEW | Reviewer, Level 1 (default, ~90% of tasks) |
| `security.yaml` | SECURITY | Reviewer, security review mode (Level 2) |
| `performance.yaml` | PERFORMANCE | Reviewer, performance review mode (Level 3) |
| `reasoning.yaml` | REASONING | Used directly if an agent needs raw reasoning outside Planner |
| `architecture.yaml` | ARCHITECTURE | Reviewer, architecture review mode (Level 4 / `architecture` policy) |
| `planning.yaml` | PLANNING | Planner specifically — kept separate from `reasoning.yaml` so it can be tuned independently later |
| `research.yaml` | RESEARCH | Research Agent |
| `documentation.yaml` | DOCS | Documentation Agent |

Which combination of these profiles Reviewer actually runs for a given task is decided
by `config/review_policy.yaml`, not by this file — see that file for the policy levels
(trivial/normal/security/performance/architecture/consensus).

## Fallback rule (applies to every profile)
1. Try `primary`.
2. On error/rate limit/timeout → `fallback`.
3. If both are unavailable → Orchestrator informs the user and suggests waiting or
   manually switching the profile.

## Important constraint
`security.yaml`, `performance.yaml`, and `architecture.yaml` must each use a model
that differs from `coding.yaml` AND from `review.yaml`, so a specialized review pass
isn't just the same model re-checking its own (or its reviewer's) blind spots.

## Adding a new profile
Create `profiles/<name>.yaml` with the same `description` / `primary` / `fallback`
shape, then reference `<NAME>` (uppercase) from the relevant agent's SKILL.md or
from `review_policy.yaml`.

Note: OpenRouter's free model list (https://openrouter.ai/openrouter/free) changes
over time. Verify the current `:free` slugs before using this pack and update the
relevant file(s).
