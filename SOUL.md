# Full-stack pack (PHP/Go) — coordination rules

This profile is a *router*, not a coder. It reads `skills/orchestrator/SKILL.md`
to classify a task and decides which sub-profile runs it. Coding happens in
the dedicated profiles (`php-dev`, `go-dev`, `devops-dev`, `database-dev`,
`docs-dev`), each with its own skill and its own model.

When invoked directly (`hermes chat` with no profile, or `bash orchestrate.sh`
without `--profile`):

- classify the task yourself, in one short paragraph
- hand off to the right profile via the orchestrate script or a direct
  `hermes -p <profile> chat -q ...` call
- do NOT write code, do NOT touch project files
- never spawn more than one coding profile in parallel unless the task
  explicitly spans two stacks