"""dispatch_profile tool — run a task on a sub-profile via subprocess.

Why a plugin tool rather than a bash call inside orchestrator's
terminal skill? Because the orchestrator profile has `terminal`
disabled (v0.19.9 — pure advisor mode). The only ways to invoke
another profile from inside the agent loop are:

1. The `terminal` tool (disabled here by design — the LLM orchestrator
   kept using terminal for cat/find/grep on project files instead of
   dispatching, even after multiple skill rewrites and a model swap).
2. `delegate_task` — spawns a child in the CURRENT profile, not the
   target profile. Useful for sub-agent specialisation, not for
   profile switching.
3. A plugin-registered tool (this one) — same effect as a bash call
   but goes through the registered tool surface, so the orchestrator
   sees it as a typed function call, not as a string it has to
   remember to pass to bash verbatim.

The handler is intentionally small: build a `hermes -p <profile> chat
-q "<task>" --yolo --quiet` command, run it with subprocess, return
stdout. stderr is captured too, on failure. Timeout 1h matches what
the orchestrator's terminal tool would normally allow.

This is one rung 6 of the ladder: minimum code that works. The
profile list is **not** validated here — if the user passes a
nonexistent profile, hermes prints its own error and we surface it.
No whitelist, no regex, no nonsense. Lazy.
"""

from __future__ import annotations

import json
import shlex
import subprocess
from typing import Any, Callable


def _handle_dispatch_profile(args: dict[str, Any]) -> str:
    profile = args.get("profile", "").strip()
    task = args.get("task", "").strip()
    if not profile:
        return json.dumps({"ok": False, "error": "profile is required"})
    if not task:
        return json.dumps({"ok": False, "error": "task is required"})

    # ponytail: profile string goes through shlex.quote so a profile
    # name like "php-dev" or "go dev" both work. Task string is passed
    # via -q which hermes-cli parses as a single arg; if the user
    # needs literal quotes inside the task they can escape them in
    # their natural-language input. No need to over-engineer here.
    cmd = ["hermes", "-p", profile, "chat", "-q", task, "--yolo", "--quiet"]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=3600,
        )
    except FileNotFoundError:
        return json.dumps({
            "ok": False,
            "error": "`hermes` binary not found on PATH",
            "command": shlex.join(cmd),
        })
    except subprocess.TimeoutExpired:
        return json.dumps({
            "ok": False,
            "error": "hermes -p ... timed out after 3600s",
            "command": shlex.join(cmd),
        })

    return json.dumps({
        "ok": proc.returncode == 0,
        "exit_code": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    }, ensure_ascii=False)


DISPATCH_PROFILE_SCHEMA = {
    "name": "dispatch_profile",
    "description": (
        "Run a task on another Hermes profile. The handler invokes "
        "`hermes -p <profile> chat -q \"<task>\" --yolo --quiet` via "
        "subprocess and returns the profile's output as JSON. Use this "
        "instead of the terminal tool when you (the orchestrator) are "
        "running in pure-advisor mode without terminal."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "profile": {
                "type": "string",
                "description": (
                    "Profile name to dispatch to, e.g. 'php-dev', "
                    "'go-dev', 'rust-dev', 'database-dev', "
                    "'devops-dev', 'docs-dev', 'planner', "
                    "'researcher', 'reviewer', 'auditor'."
                ),
            },
            "task": {
                "type": "string",
                "description": (
                    "The natural-language task for the sub-profile. "
                    "Will be passed verbatim to `hermes chat -q`."
                ),
            },
        },
        "required": ["profile", "task"],
    },
}


def _check_dispatch_available(ctx: Any) -> bool:
    """Gate on hermes binary being on PATH. Cheap probe: subprocess."""
    try:
        subprocess.run(
            ["hermes", "--version"],
            capture_output=True,
            timeout=5,
        )
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


TOOLS = [
    ("dispatch_profile", DISPATCH_PROFILE_SCHEMA, _handle_dispatch_profile, "🔀"),
]