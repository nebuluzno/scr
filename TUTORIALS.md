# SCR Tutorials
Doc Owner: SCR Maintainers

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

## Tutorial 9: Build a Custom Native Tool

### Goal
Create, register, and safely execute a custom tool end-to-end.

### Steps
1. Create tool module at `lib/scr/tools/word_count.ex`:
```elixir
defmodule SCR.Tools.WordCount do
  @behaviour SCR.Tools.Behaviour

  def name, do: "word_count"

  def description, do: "Count words in a text payload."

  def parameters_schema do
    %{
      type: "object",
      properties: %{
        text: %{type: "string", description: "Text to analyze"}
      },
      required: ["text"]
    }
  end

  def execute(%{"text" => text}) when is_binary(text) do
    count =
      text
      |> String.split(~r/\s+/, trim: true)
      |> length()

    {:ok, %{words: count}}
  end

  def execute(_), do: {:error, "text is required"}

  def to_openai_format,
    do: SCR.Tools.Behaviour.build_function_format(name(), description(), parameters_schema())

  def on_register, do: :ok
  def on_unregister, do: :ok
end
```
2. Compile:
```bash
mix compile
```
3. Register in IEx:
```bash
iex -S mix
```
```elixir
SCR.Tools.Registry.register_tool(SCR.Tools.WordCount)
SCR.Tools.Registry.list_tools()
```
4. Execute with explicit context:
```elixir
ctx =
  SCR.Tools.ExecutionContext.new(%{
    mode: :strict,
    agent_id: "worker_custom",
    task_id: "task_custom_1",
    trace_id: "trace_custom_1"
  })

SCR.Tools.Registry.execute_tool("word_count", %{"text" => "one two three"}, ctx)
```
5. Verify tool definition is exposed:
```elixir
SCR.Tools.Registry.get_tool_definitions(ctx)
|> Enum.find(fn d -> get_in(d, [:function, :name]) == "word_count" end)
```

### Expected Results
- Tool registers successfully.
- Execution returns normalized payload with metadata.
- Tool appears in model tool definitions.

## Tutorial 10: Multi-Agent Trace Debug Lab

### Goal
Run a task through planner/worker path and trace execution context across queue, tools, logs, and memory views.

### Steps
1. Start server:
```bash
mix phx.server
```
2. Open `/tasks/new` and submit:
`Investigate fault-tolerant agent runtimes and summarize tradeoffs`
3. Open `/tasks` and note:
- `task_id`
- `trace_id`
- `parent_task_id` / `subtask_id`
4. Open `/` dashboard and inspect queue behavior while task runs.
5. Open `/tools` and execute a calculator call with matching context:
```elixir
ctx =
  SCR.Tools.ExecutionContext.new(%{
    mode: :strict,
    agent_id: "worker_debug",
    task_id: "<task_id>",
    parent_task_id: "<task_id>",
    subtask_id: "manual_probe_1",
    trace_id: "<trace_id>"
  })

SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 2}, ctx)
```
6. Open `/memory` and verify context fields are visible on stored task/result entries.
7. In shell logs, filter by trace:
```bash
rg "<trace_id>" /tmp/scr.log
```
8. (Optional) Check metrics:
```bash
curl -s http://localhost:4000/metrics/prometheus | rg "scr_tools_execute_total|scr_task_queue"
```

### Expected Results
- Same `trace_id` can be followed across UI pages and runtime logs.
- Tool metadata includes matching task/subtask context.
- Queue + tool telemetry lines correlate with task lifecycle.

## Tutorial 11: Distributed Hardening Lab (Cookie + Backoff + Remote Health)

### Goal
Run two local named nodes with a shared cookie, verify peer reconnect backoff, and run remote agent health checks.

### Steps
1. In shell A:
```bash
export RELEASE_COOKIE="replace-with-strong-cookie"
iex --sname scr1 --cookie "$RELEASE_COOKIE" -S mix
```
2. In shell B:
```bash
export RELEASE_COOKIE="replace-with-strong-cookie"
iex --sname scr2 --cookie "$RELEASE_COOKIE" -S mix
```
3. In shell A, enable distributed config:
```elixir
Application.put_env(:scr, :distributed,
  enabled: true,
  cluster_registry: true,
  handoff_enabled: true,
  peers: [:"scr2@127.0.0.1"],
  reconnect_interval_ms: 5_000,
  max_reconnect_interval_ms: 60_000,
  backoff_multiplier: 2.0,
  rpc_timeout_ms: 5_000
)

Application.put_env(:libcluster, :topologies,
  scr_epmd: [
    strategy: Cluster.Strategy.Epmd,
    config: [hosts: [:"scr2@127.0.0.1"]]
  ]
)
```
4. Trigger and inspect connectivity:
```elixir
SCR.Distributed.connect_peers()
SCR.Distributed.status()
SCR.Distributed.placement_report()
```
5. Start an agent on node `scr2` from shell A:
```elixir
remote_node = Node.list() |> List.first()

SCR.Distributed.start_agent_on(remote_node,
  "worker_remote_1",
  :worker,
  SCR.Agents.WorkerAgent,
  %{agent_id: "worker_remote_1"}
)
```
6. Run remote health checks:
```elixir
SCR.Distributed.check_agent_health_on(remote_node, "worker_remote_1")
SCR.Distributed.check_cluster_health()
SCR.Distributed.handoff_agent("worker_remote_1", Node.self())
```

### Expected Results
- Nodes connect only when cookie and naming match.
- Peer status exposes reconnect interval and failure counters.
- Placement report shows weighted node scores.
- Remote health checks return `:ok` for active agents and structured errors for missing ones.
- Manual handoff moves the agent to the target node while preserving its registered id.

## Tutorial 12: Telemetry Stream + Durable Queue Replay

### Goal
Inspect live telemetry events and validate queue replay behavior with DETS backend.

### Steps
1. Start IEx:
```bash
iex -S mix
```
2. Subscribe to telemetry stream:
```elixir
SCR.Telemetry.Stream.subscribe()
```
3. Trigger queue/tool activity:
```elixir
SCR.TaskQueue.enqueue(%{task_id: "telemetry_demo_1", type: :research}, :normal)
SCR.TaskQueue.dequeue()
SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 1, "b" => 2})
```
4. Read recent stream events:
```elixir
SCR.Telemetry.Stream.recent(30)
```
5. Enable durable queue backend:
```elixir
Application.put_env(:scr, :task_queue,
  max_size: 100,
  backend: :dets,
  dets_path: "tmp/task_queue.dets"
)
SCR.ConfigCache.refresh(:task_queue)
```
6. Restart app, enqueue task, restart again, then dequeue:
```elixir
SCR.TaskQueue.enqueue(%{task_id: "replay_demo_1"}, :high)
# restart app/session
SCR.TaskQueue.dequeue()
```

### Expected Results
- Telemetry stream contains queue/tool events with metadata tags.
- Queue tasks survive restart and replay when DETS backend is enabled.

## Tutorial 13: LLM Provider Failover Lab

### Goal
Validate provider fallback behavior and confirm response provider metadata.

### Steps
1. Start IEx:
```bash
iex -S mix
```
2. Enable failover chain:
```elixir
Application.put_env(:scr, :llm,
  Keyword.merge(Application.get_env(:scr, :llm, []),
    provider: :ollama,
    failover_enabled: true,
    failover_providers: [:ollama, :openai, :anthropic],
    failover_errors: [:connection_error, :timeout, :http_error, :api_error],
    failover_cooldown_ms: 30_000
  )
)
SCR.ConfigCache.refresh(:llm)
```
3. Run chat and inspect selected provider:
```elixir
{:ok, response} = SCR.LLM.Client.chat([%{role: "user", content: "Provider check"}])
response.provider
```
4. Check failover state helpers:
```elixir
SCR.LLM.Client.clear_failover_state()
```

### Expected Results
- Calls return successful content when at least one provider is healthy.
- `response.provider` shows the provider that actually answered.
