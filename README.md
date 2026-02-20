# Supervised Cognitive Runtime (SCR)
[![CI](https://github.com/nebuluzno/scr/actions/workflows/ci.yml/badge.svg)](https://github.com/nebuluzno/scr/actions/workflows/ci.yml)

SCR is a supervised, fault-tolerant multi-agent runtime built with Elixir/OTP.

It provides:
- OTP-supervised agents (`Planner`, `Worker`, `Critic`, `Memory`, plus specialized agents)
- Priority task queue with backpressure (`SCR.TaskQueue`)
- Agent health monitoring + auto-heal hooks (`SCR.HealthCheck`)
- Shared task context store for multi-agent coordination (`SCR.AgentContext`)
- LLM execution (Ollama by default, mock provider for tests)
- Unified tool execution (native tools + MCP integration path)
- Tool rate limiting guardrail (`SCR.Tools.RateLimiter`)
- Phoenix Web UI for monitoring, tasks, memory, and metrics

## Quick Links
- Full setup + first run: `QUICKSTART.md`
- Use-case walkthroughs: `SCR_UseCases.md`
- LLM architecture details: `SCR_LLM_Documentation.txt`
- Improvement backlog: `SCR_Improvements.md`
- Docs/UI quality suggestions (visual regression + docs CI): `SCR_Improvements.md`

## Prerequisites
- Elixir `1.14+`
- Erlang/OTP `24+`

## Install
```bash
mix deps.get
mix compile
```

## CI Notes
- Main CI validates formatting, compile warnings, and tests.
- Coverage runs in a non-blocking job and uploads `cover/` as an artifact.
- Docs quality gate validates markdown lint + internal links on key project docs.
- Optional MCP smoke job runs only on non-PR events when these repo secrets are set:
  `SCR_MCP_SERVER_NAME`, `SCR_MCP_SERVER_COMMAND`, `SCR_MCP_SERVER_ARGS`, `SCR_MCP_ALLOWED_TOOLS`.

## Run (CLI)

### 1. Standard demo
```bash
mix run -e "SCR.CLI.Demo.main([])"
```
What it does:
1. Starts runtime and core agents
2. Submits a top-level task to `PlannerAgent`
3. Spawns workers for subtasks
4. Runs critique and finalization
5. Prints cache/metrics summary

### 2. Crash recovery demo
```bash
mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"
```
What it does:
1. Starts a worker
2. Crashes it intentionally
3. Restarts it
4. Verifies work continues

### 3. Help
```bash
mix run -e "SCR.CLI.Demo.main([\"--help\"])"
```

## Run (Web UI)
```bash
mix phx.server
```
Open [http://localhost:4000](http://localhost:4000).

### Web UI pages
- `/` Live dashboard (agents, cache, calls, quick actions)
- `/tasks/new` Submit new tasks
- `/agents` Inspect running agents
- `/tools` Inspect/execute tools
- `/memory` Browse ETS memory state
- `/metrics` LLM and cache metrics

### Web UI task example
1. Open `/tasks/new`
2. Enter: `Research AI agent runtimes and produce a concise comparison`
3. Submit
4. Watch status on `/` and `/agents`
5. Review state on `/memory` and `/metrics`

## LLM Setup (Optional)

### Ollama
```bash
ollama serve
ollama pull llama2
```

Environment variables:
```bash
export LLM_BASE_URL=http://localhost:11434
export LLM_MODEL=llama2
```

If Ollama is unavailable, agents fall back to mock behavior where implemented.

## Tool System (Hybrid)
SCR uses a unified tool registry:
- Native tools: calculator, file ops, weather, etc.
- MCP-backed tools: managed via MCP server manager (local stdio)

Default safety mode is `:strict`.

### Example tool call from IEx
```bash
iex -S mix
```
```elixir
SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 3})
# => {:ok, %{data: 5, meta: %{source: :native, tool: "calculator", ...}}}
```

## Development Commands
```bash
mix test
mix compile
mix phx.server
```

## MCP Smoke Check (Dev)
Use this to validate a real MCP server integration locally:
```bash
mix scr.mcp.smoke
```
You can also call one MCP tool directly:
```bash
mix scr.mcp.smoke --server <server_name> --tool <tool_name> --args-json '{"key":"value"}'
```

### MCP Verified Example (Filesystem)
Verified locally with the filesystem MCP server from [mcpservers.org](https://mcpservers.org):

```bash
brew install node
npm install -g @modelcontextprotocol/server-filesystem

export SCR_MCP_ENABLED=true
export SCR_WORKSPACE_ROOT="$PWD"
export SCR_MCP_SERVER_NAME=filesystem
export SCR_MCP_SERVER_COMMAND=mcp-server-filesystem
export SCR_MCP_SERVER_ARGS="$SCR_WORKSPACE_ROOT"
export SCR_MCP_ALLOWED_TOOLS="list_directory,read_file,write_file"

mix scr.mcp.smoke
mix scr.mcp.smoke --server filesystem --tool list_directory --args-json '{"path":"."}'
```

## Current Version
`v0.1.0-alpha`
