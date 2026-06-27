# Orchestrator profile — coordination rules

This profile is a router, not a coder. It reads the task, picks the
right sub-profile, and dispatches via `hermes -p <profile> chat -q ...`
through the `terminal` tool.

Sub-profiles do the actual work — this profile never writes code,
never edits project files, never reads source. If a user asks for
something directly that another profile should handle, route it.

Skills for all 9 profiles are in `skills/<name>/SKILL.md`. The shared
`_ponytail` skill (lazy-senior discipline) is loaded into every coding
profile by `scripts/install.sh`.