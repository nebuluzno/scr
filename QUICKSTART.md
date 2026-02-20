# SCR Quickstart

This guide gets you from clone to running both CLI and Web UI in a few minutes.

## 1. Install
```bash
mix deps.get
mix compile
```

### Local dependencies for MCP servers
If you plan to use JavaScript-based MCP servers, install Node.js:
```bash
brew install node
```

## 2. Run the CLI demo
```bash
mix run -e "SCR.CLI.Demo.main([])"
```

Expected flow:
1. Application starts
2. `memory_1`, `critic_1`, `planner_1` start
3. Planner sends subtasks to workers
4. Results are critiqued and summarized

Run crash test:
```bash
mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"
```

## 3. Run the Web UI
```bash
mix phx.server
```
Open [http://localhost:4000](http://localhost:4000)

### First Web UI walkthrough
1. Dashboard: verify active runtime stats
2. Queue Control card: test pause/resume and clear/drain actions
3. `New Task`: submit a task
4. `Agents`: watch active agents
5. `Memory`: inspect stored tasks/states
6. `Metrics`: inspect LLM/cache activity
7. `Tools`: run a manual tool call

## 4. Optional: enable local LLM (Ollama)
```bash
ollama serve
ollama pull llama2
export LLM_BASE_URL=http://localhost:11434
export LLM_MODEL=llama2
```

Then rerun:
```bash
mix run -e "SCR.CLI.Demo.main([])"
```

## 4b. Optional: MCP smoke test (real server)
Set env vars (verified example with MCP filesystem server):
```bash
export SCR_MCP_ENABLED=true
export SCR_WORKSPACE_ROOT="$PWD"
export SCR_MCP_SERVER_NAME=filesystem
export SCR_MCP_SERVER_COMMAND=mcp-server-filesystem
export SCR_MCP_SERVER_ARGS="$SCR_WORKSPACE_ROOT"
export SCR_MCP_ALLOWED_TOOLS="list_directory,read_file,write_file"
```

Install server binary:
```bash
npm install -g @modelcontextprotocol/server-filesystem
```

Run smoke validation:
```bash
mix scr.mcp.smoke
```

Optional tool call:
```bash
mix scr.mcp.smoke --server filesystem --tool list_directory --args-json '{"path":"."}'
```

## 5. Useful IEx checks
```bash
iex -S mix
```
```elixir
SCR.Supervisor.list_agents()
SCR.LLM.Client.ping()
SCR.Tools.Registry.list_tools()
SCR.LLM.Cache.stats()
SCR.LLM.Metrics.stats()
SCR.TaskQueue.stats()
SCR.HealthCheck.stats()
SCR.Agent.health_check("planner_1")
SCR.Tools.RateLimiter.stats()
SCR.AgentContext.list() |> Enum.take(3)
```

### Optional: verify tool rate limiter
```elixir
Application.put_env(:scr, :tool_rate_limit,
  enabled: true,
  default_max_calls: 100,
  default_window_ms: 60_000,
  per_tool: %{"calculator" => %{max_calls: 1, window_ms: 60_000}}
)

SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 1, "b" => 2})
SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 3})
# second call => {:error, :rate_limited}
```

## 6. Troubleshooting

### Port 4000 already in use
```bash
PORT=4001 mix phx.server
```

### LLM not reachable
```bash
curl http://localhost:11434/api/tags
```
If unreachable, run `ollama serve`.

### Clean rebuild
```bash
mix clean
mix deps.get
mix compile
```
