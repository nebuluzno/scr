# SKILL.md
Doc Owner: SCR Maintainers

## Purpose

This file provides a compatibility skill profile for agentic tools/frameworks that expect a `SKILL.md` contract.

Canonical runtime and contributor guidance remains in `AGENTS.md`.

## Compatibility Contract

1. Source of truth
- `AGENTS.md` is canonical.
- `SKILL.md` is a compatibility layer and must stay aligned with canonical behavior.

2. Scope
- Keep this file concise and operational.
- Link to deeper docs instead of duplicating large sections.

3. Resolution rule
- If `SKILL.md` and `AGENTS.md` differ, follow `AGENTS.md`.

## Quick Start

1. Install and compile
```bash
mix deps.get
mix compile
```

2. Run Web UI
```bash
mix phx.server
```

3. Run CLI demo
```bash
mix run -e "SCR.CLI.Demo.main([])"
```

4. Run tests
```bash
mix test
```

## Runtime Model

- SCR is an OTP-supervised multi-agent runtime on Elixir/BEAM.
- Core agents: `Planner`, `Worker`, `Critic`, `Memory`.
- Dynamic agents: `Researcher`, `Writer`, `Validator`.
- Tool execution is hybrid: native tools + MCP tools through unified registry/policy/execution.

## Agent Workflow Expectations

1. Prefer deterministic local tools for local/system tasks.
2. Use MCP tools for external integrations where configured.
3. Respect tool policy mode (`:strict` by default).
4. Preserve context propagation (`trace_id`, `task_id`, `parent_task_id`, `subtask_id`) across tool calls.
5. Keep operations observable (structured logs, metrics, tool audit).

## Commands and Operations

Memory:
```bash
mix scr.memory.verify --backend ets
mix scr.memory.migrate --from dets --to sqlite --from-path tmp/memory --to-path tmp/memory/scr_memory.sqlite3
```

MCP smoke:
```bash
mix scr.mcp.smoke
```

Distributed resilience:
```bash
mix test --only distributed_resilience --exclude multi_node
SCR_RUN_MULTI_NODE_TESTS=true mix test --only distributed_resilience --only multi_node
```

## Key Paths

- `AGENTS.md` (canonical architecture and contributor guidance)
- `README.md` (overview and setup)
- `QUICKSTART.md` (first run)
- `TUTORIALS.md` (step-by-step flows)
- `docs/roadmap/FUTURE_TODO.md` (forward backlog)

## Version

Current version: **v0.5.0-alpha**
