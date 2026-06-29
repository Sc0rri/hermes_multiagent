"""hermes_multiagent plugin entrypoint.

Single tool: dispatch_profile. See tools.py for rationale.

ponytail: keep this module flat. No re-exports, no fancy namespaces,
just `register(ctx)`. The plugin loader expects this exact symbol.
"""

from __future__ import annotations

from typing import Any

from .tools import TOOLS, _check_dispatch_available


def register(ctx: Any) -> None:
    """Register all plugin tools. Called once by the plugin loader."""
    for name, schema, handler, emoji in TOOLS:
        ctx.register_tool(
            name=name,
            toolset="hermes_multiagent",
            schema=schema,
            handler=handler,
            check_fn=_check_dispatch_available,
            emoji=emoji,
        )