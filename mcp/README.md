# MCP Integrations

Note: **Ponytail is not an MCP server** — it's a coding-discipline skill/plugin
(YAGNI ladder: don't write code that doesn't need to exist, prefer stdlib/framework/
already-installed deps, keep diffs minimal). Install it separately per
https://github.com/DietrichGebert/ponytail, matching whatever your hermes-desktop
version supports (skill import, plugin, or an AGENTS.md/rules-file style always-on
instruction). It works alongside the MCP servers below, not instead of them.

For actual project context (structure, file contents, history), the pack expects the
following MCP servers to be available to the relevant agents in hermes-desktop:

| MCP server | Used by | Purpose |
|---|---|---|
| **Filesystem MCP** | PHP Agent, Go Agent, DevOps Agent, Database Agent | Read project structure and file contents — mandatory first step before any LLM call. |
| **Git MCP** | All coding agents, Reviewer | Diff generation, blame, history — Reviewer uses this to see exactly what changed, not the whole file. |
| **SQLite MCP** | Database Agent | Inspect local dev database directly (schema, row counts, query plans). |
| **GitHub MCP** | Orchestrator, Documentation Agent | Open PRs, read/close Issues, post review comments — only if you want Hermes to interact with GitHub directly rather than just local git. Optional; skip if you don't want it touching your remote repo. |

## Context Pipeline (the LLM never searches for files itself)

```
Ponytail (decide if new code is even needed, YAGNI check)
        ↓
Filesystem MCP (symbol/file search — find exactly what's relevant)
        ↓
Git MCP (history/diff/blame — only if the task is "fix this" or "why did X change")
        ↓
LLM receives an already-assembled, capped context (see config/context_policy.yaml)
```

The model is never handed a raw "go explore the repo" task — by the time a coding
agent calls the model, Filesystem/Git MCP have already narrowed things down to the
specific files/symbols/history the task needs, capped by `max_files`/`max_tokens` in
`config/context_policy.yaml`. This is also why `config/tool_policy.yaml` forbids
`grep`/`find` for coding agents — if Filesystem MCP already indexes and searches the
project, falling back to shell search means redoing (worse) what the MCP layer
already did, and burns tokens explaining the result back to the model.

## Setup notes

- Register each MCP server in hermes-desktop under Settings -> MCP Servers (or via
  CLI config, depending on your version).
- Scope access per-agent if hermes-desktop supports it: Reviewer should have
  **read-only** Git/Filesystem access — it should never be able to commit or modify
  files, only inspect them. This enforces the "independent review" principle even
  at the tool level, not just in the prompt.
- GitHub MCP is optional and higher-risk (can touch your remote repo) — only enable
  it for Orchestrator/Docs Agent, and only if you actually want PR/issue automation.
  If you're not ready for that, skip it; everything else in this pack works fine
  with just local Git.

## Recommended minimal set to start with
1. Filesystem MCP (mandatory)
2. Git MCP (mandatory, read-only for Reviewer)
3. Ponytail installed as its own skill/plugin (see note above — not an MCP server)

Add SQLite MCP once Database Agent is in active use, and GitHub MCP only if you
want PR-level automation.
