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

## Tutorial 5: Visual Regression Baseline Diff

### Goal
Run Playwright baseline-diff checks locally and update snapshots when UI changes are intentional.

### Steps
1. Install Node dependencies:
```bash
npm ci
```
2. Install Chromium for Playwright:
```bash
npx playwright install chromium
```
3. Run visual checks:
```bash
npm run visual:test
```
4. If UI changes are intentional, refresh snapshots:
```bash
npm run visual:update
```
5. Re-run the test command and confirm all checks pass.

### Expected Results
- `visual:test` passes on unchanged UI.
- Intentional UI updates are captured in `visual_tests/snapshots/`.
- CI visual regression job uses the same baseline files.

## Tutorial 6: OpenAI + Streaming + Persistent Memory + Sandbox

### Goal
Run SCR with OpenAI provider, stream model output, persist memory to DETS, and validate sandbox controls.

### Steps
1. Configure OpenAI:
```bash
export OPENAI_API_KEY=sk-...
export OPENAI_MODEL=gpt-4o-mini
```
2. Set provider:
```elixir
# config/config.exs
config :scr, :llm, provider: :openai
```
3. Start IEx:
```bash
iex -S mix
```
4. Stream a chat response:
```elixir
SCR.LLM.Client.chat_stream(
  [%{role: "user", content: "Explain OTP supervision in 5 bullet points"}],
  fn chunk -> IO.write(chunk) end
)
```
5. Enable DETS memory persistence:
```elixir
Application.put_env(:scr, :memory_storage, backend: :dets, path: "tmp/memory")
```
6. Tighten sandbox rules:
```elixir
tools_cfg = Application.get_env(:scr, :tools, [])

Application.put_env(:scr, :tools,
  Keyword.merge(tools_cfg,
    sandbox: [
      file_operations: [
        strict_allow_writes: false,
        demo_allow_writes: true,
        allowed_write_prefixes: ["tmp/"],
        max_write_bytes: 100_000
      ],
      code_execution: [
        max_code_bytes: 4_000,
        blocked_patterns: ["HTTPoison."]
      ]
    ]
  )
)
```
7. Validate strict sandbox denial:
```elixir
ctx = SCR.Tools.ExecutionContext.new(%{mode: :strict})
SCR.Tools.Registry.execute_tool("file_operations", %{"operation" => "write", "path" => "tmp/a.txt", "content" => "x"}, ctx)
```

### Expected Results
- OpenAI `ping`/chat calls succeed.
- Stream callback receives incremental chunks.
- MemoryAgent can restore task memory from DETS on restart.
- Strict mode blocks disallowed file writes or blocked code patterns.

## Tutorial 7: Production JSON Logs + OTel Bridge

### Goal
Enable production JSON logs and forward SCR telemetry events as OpenTelemetry spans to an OTLP collector.

### Steps
1. Set production observability env:
```bash
export SCR_LOG_FORMAT=json
export SCR_OTEL_ENABLED=true
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_SERVICE_NAME=scr-runtime
```
2. Run in production mode:
```bash
MIX_ENV=prod mix phx.server
```
3. Trigger runtime events:
- submit task(s) via `/tasks/new`
- execute tool(s) via `/tools`
4. Verify logs are JSON lines in stdout.
5. Verify spans arrive at your OTLP collector backend.

### Expected Results
- Logs include structured metadata (`trace_id`, `task_id`, `agent_id`, etc.).
- SCR telemetry events (tool/queue/health/MCP) are exported as OTel spans.

## Tutorial 8: Anthropic Provider Check

### Goal
Run SCR with Anthropic as the active provider and verify chat + stream paths.

### Steps
1. Export Anthropic env:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
export ANTHROPIC_MODEL=claude-3-5-sonnet-latest
```
2. Set provider:
```elixir
# config/config.exs
config :scr, :llm, provider: :anthropic
```
3. Run IEx:
```bash
iex -S mix
```
4. Verify provider + ping:
```elixir
SCR.LLM.Client.provider()
SCR.LLM.Client.ping()
```
5. Run chat + stream:
```elixir
SCR.LLM.Client.chat([%{role: "user", content: "Explain OTP in 4 bullets"}])
SCR.LLM.Client.chat_stream([%{role: "user", content: "Stream a short summary"}], fn chunk -> IO.write(chunk) end)
```

### Expected Results
- Provider reports `:anthropic`.
- Ping and chat calls succeed.
- Stream callback receives incremental chunks.

## Next Tutorials (Planned)
- Build a custom native tool and register it safely.
- Add an MCP server profile and strict allowlist policy.
- Run a multi-agent task and debug it with trace IDs end-to-end.
