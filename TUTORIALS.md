# SCR Tutorials

This file contains practical step-by-step tutorials for core SCR workflows.

## Tutorial 1: First End-to-End Run (CLI + Runtime Checks)

### Goal
Run SCR locally, execute a task, and verify runtime health.

### Steps
1. Install and compile:
```bash
mix deps.get
mix compile
```
2. Run the demo:
```bash
mix run -e "SCR.CLI.Demo.main([])"
```
3. Open IEx for verification:
```bash
iex -S mix
```
4. Run health and runtime checks:
```elixir
SCR.Supervisor.list_agents()
SCR.TaskQueue.stats()
SCR.HealthCheck.stats()
SCR.Agent.health_check("planner_1")
```

### Expected Results
- Core agents are running (`memory_1`, `critic_1`, `planner_1`).
- Queue stats return a map with `size`, `high`, `normal`, `low`.
- Health check returns runtime counters and last run information.

## Tutorial 2: Web UI Queue Controls (Pause/Resume/Clear/Drain)

### Goal
Use the dashboard queue controls to manage dispatch behavior safely.

### Steps
1. Start web server:
```bash
mix phx.server
```
2. Open [http://localhost:4000](http://localhost:4000).
3. Open `/tasks/new` and submit 2-3 tasks.
4. On dashboard (`/`), locate `Queue Control`.
5. Click `Pause`.
6. Submit one more task from `/tasks/new`.
7. Verify queue size increases but new work is not dispatched.
8. Click `Resume`.
9. Verify planner dispatch resumes.
10. Optionally test:
- `Clear`: removes queued tasks.
- `Drain`: returns queued tasks and marks them as `:drained` in `SCR.AgentContext`.

### Expected Results
- Pause halts dequeue/dispatch.
- Resume restarts dequeue/dispatch.
- Queue counters update live.

## Tutorial 3: MCP + Safety + Rate Limits + Context Debug

### Goal
Validate MCP integration and safety controls, then inspect tracing metadata.

### Steps
1. Install filesystem MCP server:
```bash
npm install -g @modelcontextprotocol/server-filesystem
```
2. Configure MCP env:
```bash
export SCR_MCP_ENABLED=true
export SCR_WORKSPACE_ROOT="$PWD"
export SCR_MCP_SERVER_NAME=filesystem
export SCR_MCP_SERVER_COMMAND=mcp-server-filesystem
export SCR_MCP_SERVER_ARGS="$SCR_WORKSPACE_ROOT"
export SCR_MCP_ALLOWED_TOOLS="list_directory,read_file,write_file"
```
3. Run MCP smoke task:
```bash
mix scr.mcp.smoke --server filesystem --tool list_directory --args-json '{"path":"."}'
```
4. Open IEx and enable strict rate limit for calculator:
```bash
iex -S mix
```
```elixir
Application.put_env(:scr, :tool_rate_limit,
  enabled: true,
  default_max_calls: 100,
  default_window_ms: 60_000,
  cleanup_interval_ms: 60_000,
  per_tool: %{"calculator" => %{max_calls: 1, window_ms: 60_000}}
)
```
5. Build execution context and call tool:
```elixir
ctx =
  SCR.Tools.ExecutionContext.new(%{
    mode: :strict,
    agent_id: "worker_1",
    task_id: "task_main_1",
    parent_task_id: "task_main_1",
    subtask_id: "subtask_1",
    trace_id: "trace_demo_1"
  })

SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 1, "b" => 1}, ctx)
SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 2}, ctx)
```
6. Inspect limiter and context stats:
```elixir
SCR.Tools.RateLimiter.stats()
SCR.AgentContext.stats()
```

### Expected Results
- MCP smoke succeeds with listed tool output.
- First calculator call succeeds; second returns `{:error, :rate_limited}`.
- Tool metadata includes `trace_id`, `task_id`, `parent_task_id`, `subtask_id`, `agent_id`.

## Tutorial 4: Observability Stack (Prometheus + Alertmanager + Grafana)

### Goal
Run the bundled observability stack and verify live runtime metrics + alert templates.

### Steps
1. Start SCR web server in one terminal:
```bash
mix phx.server
```
2. In a second terminal, start observability services:
```bash
docker compose -f docker-compose.observability.yml up -d
```
Alternative:
```bash
make obs-up
```
3. Open [http://localhost:9090/targets](http://localhost:9090/targets).
4. Confirm `scr_app` target is `UP`.
5. Open [http://localhost:3000](http://localhost:3000).
6. Login with `admin` / `admin`.
7. Open dashboard `SCR Runtime Overview`.
8. Submit a few tasks from `/tasks/new`.
9. Trigger a few tool calls from `/tools`.
10. Check Alertmanager:
```bash
curl -s http://localhost:9093/api/v2/alerts | jq 'length'
```
11. Stop observability stack when done:
```bash
docker compose -f docker-compose.observability.yml down
```
Alternative:
```bash
make obs-down
```

### Expected Results
- Prometheus target `scr_app` is healthy.
- Grafana displays queue, rate-limit, MCP, and latency panels.
- Alertmanager is running and ready to receive alerts from Prometheus rules.

## Next Tutorials (Planned)
- Build a custom native tool and register it safely.
- Add an MCP server profile and strict allowlist policy.
- Run a multi-agent task and debug it with trace IDs end-to-end.
