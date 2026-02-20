# Supervised Cognitive Runtime (SCR)
Doc Owner: SCR Maintainers

[![CI](https://github.com/nebuluzno/scr/actions/workflows/ci.yml/badge.svg)](https://github.com/nebuluzno/scr/actions/workflows/ci.yml)

SCR is a supervised, fault-tolerant multi-agent runtime built with Elixir/OTP.

It provides:
- OTP-supervised agents (`Planner`, `Worker`, `Critic`, `Memory`, plus specialized agents)
- Priority task queue with backpressure (`SCR.TaskQueue`)
- Agent health monitoring + auto-heal hooks (`SCR.HealthCheck`)
- Shared task context store for multi-agent coordination (`SCR.AgentContext`)
- LLM execution (Ollama/OpenAI/Anthropic providers, mock provider for tests)
- Streaming completions support (prompt and chat streams)
- Unified tool execution (native tools + MCP integration path)
- Distributed runtime baseline (libcluster discovery + spec-registry handoff + cross-node RPC)
- Distributed watchdog quarantine + placement guardrails
- Sharded agent context ownership via `PartitionSupervisor`
- Optional durable task queue replay backend (DETS)
- Tool composition helper for pipelines (`SCR.Tools.Chain`)
- Tool rate limiting guardrail (`SCR.Tools.RateLimiter`)
- Execution context propagation (`trace_id`, `parent_task_id`, `subtask_id`) across tool calls
- Structured runtime logging with trace metadata (`SCR.Trace` + logger metadata keys)
- Production JSON logging profile (`SCR_LOG_FORMAT=json`)
- Optional OpenTelemetry telemetry-to-span bridge (`SCR_OTEL_ENABLED=true`)
- Phoenix Web UI for monitoring, tasks, memory, and metrics

## Quick Links
- Full setup + first run: `QUICKSTART.md`
- Step-by-step tutorials: `TUTORIALS.md`
- Documentation index: `DOCS_INDEX.md`
- Release prep checklist: `RELEASE_CHECKLIST.md`
- Latest release notes: `docs/release/RELEASE_NOTES_v0.5.0-alpha.md`
- Competitive comparison: `docs/positioning/SCR_Competitive_Comparison.md`
- Future roadmap TODO: `docs/roadmap/FUTURE_TODO.md`
- Use-case walkthroughs: `docs/guides/SCR_UseCases.md`
- Distributed resilience runbook: `docs/guides/DISTRIBUTED_RESILIENCE_RUNBOOK.md`
- LLM architecture details: `docs/architecture/SCR_LLM_Documentation.txt`
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
- Visual regression baseline-diff job is blocking in CI and uploads Playwright artifacts on failure.
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
- `/tasks` Track task status and execution context (`trace_id`, parent/subtask IDs)
- `/tasks/new` Submit new tasks
- `/agents` Inspect running agents
- `/tools` Inspect/execute tools
- `/memory` Browse memory state (ETS or DETS-backed) with trace/context fields
- `/metrics` LLM and cache metrics
- `/metrics/prometheus` Prometheus scrape endpoint for runtime telemetry

Dashboard now includes queue controls:
- Pause/resume task dispatch
- Clear queued tasks
- Drain queue (marks drained tasks in shared context)

Queue scheduler notes:
- Dequeue path uses weighted fairness across workload classes within each priority lane.
- Fairness telemetry: `[:scr, :task_queue, :fairness]`.
- Capacity tuning decisions also track estimated latency SLO and emit reason-labeled telemetry.

### Web UI task example
1. Open `/tasks/new`
2. Enter: `Research AI agent runtimes and produce a concise comparison`
3. Submit
4. Open `/tasks` to inspect status + `trace_id` context
5. Watch runtime status on `/` and `/agents`
6. Review memory/context state on `/memory` and `/metrics`

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

### OpenAI
```bash
export OPENAI_API_KEY=sk-...
export OPENAI_MODEL=gpt-4o-mini
```

In `config/config.exs`:
```elixir
config :scr, :llm,
  provider: :openai
```

Optional overrides:
```bash
export OPENAI_BASE_URL=https://api.openai.com
```

### Streaming example
```bash
iex -S mix
```
```elixir
SCR.LLM.Client.chat_stream(
  [%{role: "user", content: "Summarize OTP in one paragraph"}],
  fn chunk -> IO.write(chunk) end
)
```

### Anthropic
```bash
export ANTHROPIC_API_KEY=sk-ant-...
export ANTHROPIC_MODEL=claude-3-5-sonnet-latest
```

In `config/config.exs`:
```elixir
config :scr, :llm,
  provider: :anthropic
```

### Provider failover policy (all providers)
Failover is enabled by default and attempts providers in order:
```elixir
config :scr, :llm,
  provider: :ollama,
  failover_enabled: true,
  failover_mode: :fail_closed, # :fail_closed | :fail_open
  failover_providers: [:ollama, :openai, :anthropic],
  failover_errors: [:connection_error, :timeout, :http_error, :api_error],
  failover_cooldown_ms: 30_000,
  failover_fail_open_provider: :mock,
  failover_retry_budget: [max_retries: 50, window_ms: 60_000]
```

Inspect runtime failover state:
```elixir
SCR.LLM.Client.failover_state()
```

Production env overrides:
```bash
export SCR_LLM_FAILOVER_ENABLED=true
export SCR_LLM_FAILOVER_MODE=fail_closed
export SCR_LLM_FAILOVER_PROVIDERS=ollama,openai,anthropic
export SCR_LLM_FAILOVER_COOLDOWN_MS=30000
export SCR_LLM_FAILOVER_FAIL_OPEN_PROVIDER=mock
export SCR_LLM_FAILOVER_RETRY_BUDGET_MAX=50
export SCR_LLM_FAILOVER_RETRY_BUDGET_WINDOW_MS=60000
```

## Memory Migration and Verify

Migrate memory records between backends:
```bash
mix scr.memory.migrate --from dets --to sqlite --from-path tmp/memory --to-path tmp/memory/scr_memory.sqlite3
```

Verify backend consistency:
```bash
mix scr.memory.verify --backend dets --path tmp/memory
mix scr.memory.verify --backend sqlite --path tmp/memory/scr_memory.sqlite3
```

Notes:
- Supported backends: `ets`, `dets`, `sqlite`, `postgres`.
- `scr.memory.migrate` clears target backend by default; pass `--merge` to upsert without clearing.

## Tool System (Hybrid)
SCR uses a unified tool registry:
- Native tools: calculator, file ops, weather, etc.
- MCP-backed tools: managed via MCP server manager (local stdio)

Default safety mode is `:strict`.

Policy governance profiles:
- `:strict` (default)
- `:balanced`
- `:research`

Switch profile at runtime:
```elixir
SCR.Tools.Policy.current_profile()
SCR.Tools.Policy.set_profile(:balanced)
```

Audit trail:
- Recent allow/deny tool decisions are visible on the dashboard.
- Configure audit backend (`:ets` or `:dets`) via:
```bash
export SCR_TOOLS_AUDIT_BACKEND=dets
export SCR_TOOLS_AUDIT_PATH=tmp/tool_audit_log.dets
```

### Example tool call from IEx
```bash
iex -S mix
```
```elixir
SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 3})
# => {:ok, %{data: 5, meta: %{source: :native, tool: "calculator", ...}}}

SCR.Tools.Chain.execute(
  [
    %{tool: "calculator", params: %{"operation" => "add", "a" => 2, "b" => 3}},
    %{tool: "calculator", params: %{"operation" => "multiply", "a" => "__input__", "b" => 10}}
  ],
  nil
)
# => {:ok, %{output: 50, steps: [...]}}
```

## Distributed Runtime
SCR includes:
- Optional node discovery via `libcluster` (`Cluster.Strategy.Epmd`)
- Distributed agent spec replication (`SCR.Distributed.SpecRegistry`)
- Node-down handoff manager (`SCR.Distributed.HandoffManager`)
- Node watchdog/quarantine for flapping peers (`SCR.Distributed.NodeWatchdog`)
- Cross-node agent APIs (`SCR.Distributed`)

Core distributed API:
- `SCR.Distributed.status/0`
- `SCR.Distributed.connect_peers/0`
- `SCR.Distributed.list_cluster_agents/0`
- `SCR.Distributed.start_agent_on/6`
- `SCR.Distributed.start_agent/5` (weighted placement)
- `SCR.Distributed.pick_start_node/1`
- `SCR.Distributed.placement_report/2`
- `SCR.Distributed.queue_pressure_report/2`
- `SCR.Distributed.cluster_backpressured?/2`
- `SCR.Distributed.pick_start_node_for_class/2`
- `SCR.Distributed.handoff_agent/3`
- `SCR.Distributed.check_agent_health_on/3`
- `SCR.Distributed.check_cluster_health/1`

Enable via config:
```elixir
config :scr, :distributed,
  enabled: true,
  cluster_registry: true,
  handoff_enabled: true,
  watchdog_enabled: true,
  peers: [:"scr2@127.0.0.1"],
  reconnect_interval_ms: 5_000,
  max_reconnect_interval_ms: 60_000,
  backoff_multiplier: 2.0,
  flap_window_ms: 60_000,
  flap_threshold: 3,
  quarantine_ms: 120_000,
  placement_weights: [
    queue_depth_weight: 1.0,
    queue_utilization_weight: 30.0,
    queue_growth_weight: 10.0,
    agent_count_weight: 1.0,
    agent_growth_weight: 5.0,
    unhealthy_weight: 15.0,
    down_event_weight: 5.0,
    saturated_penalty: 40.0,
    constraint_penalty: 500.0,
    local_bias: 2.0
  ],
  placement_constraints: [
    max_agents_per_node: nil,
    max_queue_per_node: nil
  ],
  backpressure: [
    enabled: true,
    cluster_saturation_threshold: 0.85,
    max_node_utilization: 0.98
  ],
  routing: [
    enabled: false,
    at_least_once: true,
    dedupe_enabled: true,
    dedupe_ttl_ms: 300_000,
    max_attempts: 3,
    retry_delay_ms: 100,
    rpc_timeout_ms: 5_000
  ],
  placement_observability: [
    enabled: true,
    interval_ms: 5_000,
    history_size: 120
  ],
  workload_routing: [
    enabled: false,
    strict: false,
    classes: %{
      "cpu" => ["cpu"],
      "io" => ["io"],
      "external_api" => ["external_api"]
    },
    local_capabilities: [],
    node_capabilities: %{}
  ],
  capacity_tuning: [
    enabled: false,
    interval_ms: 10_000,
    min_queue_size: 50,
    max_queue_size: 500,
    up_step: 25,
    down_step: 10,
    high_rejection_ratio: 0.08,
    low_rejection_ratio: 0.01
  ],
  rpc_timeout_ms: 5_000

config :libcluster,
  topologies: [
    scr_epmd: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"scr2@127.0.0.1", :"scr3@127.0.0.1"]]
    ]
  ]
```

Quick check from IEx:
```elixir
SCR.Distributed.status()
SCR.Distributed.placement_report()
SCR.Distributed.queue_pressure_report()
SCR.Distributed.cluster_backpressured?()
SCR.Distributed.pick_start_node_for_class("cpu")
SCR.Distributed.list_cluster_agents()
SCR.Distributed.pick_start_node()
SCR.Distributed.start_agent("worker_auto_1", :worker, SCR.Agents.WorkerAgent, %{agent_id: "worker_auto_1"})
SCR.Distributed.check_cluster_health()
SCR.Distributed.handoff_agent("worker_1", :"scr2@127.0.0.1")
SCR.Distributed.RecoveryDrills.run(:node_flap, cycles: 2, dry_run: true)
```

Telemetry stream API:
```elixir
SCR.Telemetry.Stream.subscribe()
SCR.Telemetry.Stream.recent(50)
```

Security note:
- Use a strong shared Erlang cookie for all cluster nodes.
- Avoid exposing Erlang distribution ports publicly without network controls.
- Quarantined nodes are automatically excluded from auto-placement and handoff targets.
- Optional routing semantics support at-least-once remote task delivery with dedupe keys.
- Dashboard includes placement observability history and quarantine snapshots.
- Optional workload class routing supports capability-aware placement (`cpu`, `io`, `external_api`).
- Optional capacity tuning can adapt queue limits from runtime rejection/pressure signals.

## Development Commands
```bash
mix test
mix compile
mix phx.server
```

## Runtime Controls
Tune these in `config/config.exs`:

```elixir
config :scr, :task_queue, max_size: 100
config :scr, :task_queue,
  backend: :memory, # :memory | :dets
  dets_path: "tmp/task_queue.dets"

config :scr, :health_check,
  interval_ms: 15_000,
  auto_heal: true,
  stale_heartbeat_ms: 30_000

config :scr, :tool_rate_limit,
  enabled: true,
  default_max_calls: 60,
  default_window_ms: 60_000,
  cleanup_interval_ms: 60_000,
  per_tool: %{
    "calculator" => %{max_calls: 30, window_ms: 60_000}
  }

config :scr, :agent_context,
  retention_ms: 3_600_000,
  cleanup_interval_ms: 300_000,
  shards: 8

config :scr, :memory_storage,
  backend: :ets, # :ets | :dets | :sqlite | :postgres
  path: "tmp/memory", # directory for :dets, sqlite file path for :sqlite
  postgres: [
    url: System.get_env("SCR_MEMORY_POSTGRES_URL"),
    hostname: System.get_env("SCR_MEMORY_POSTGRES_HOST"),
    port: 5432,
    username: System.get_env("SCR_MEMORY_POSTGRES_USER"),
    password: System.get_env("SCR_MEMORY_POSTGRES_PASSWORD"),
    database: System.get_env("SCR_MEMORY_POSTGRES_DB"),
    ssl: false
  ]

config :scr, :tools,
  sandbox: [
    file_operations: [
      strict_allow_writes: false,
      demo_allow_writes: true,
      allowed_write_prefixes: [],
      max_write_bytes: 100_000
    ],
    code_execution: [
      max_code_bytes: 4_000,
      blocked_patterns: []
    ]
  ]

config :scr, SCR.Telemetry,
  poller_interval_ms: 10_000

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:trace_id, :task_id, :parent_task_id, :subtask_id, :agent_id]

config :scr, SCR.Observability.OTelBridge,
  enabled: false

config :scr, :distributed,
  enabled: false,
  cluster_registry: true,
  handoff_enabled: true,
  watchdog_enabled: true,
  peers: [],
  reconnect_interval_ms: 5_000,
  max_reconnect_interval_ms: 60_000,
  backoff_multiplier: 2.0,
  flap_window_ms: 60_000,
  flap_threshold: 3,
  quarantine_ms: 120_000,
  placement_weights: [
    queue_depth_weight: 1.0,
    queue_utilization_weight: 30.0,
    queue_growth_weight: 10.0,
    agent_count_weight: 1.0,
    agent_growth_weight: 5.0,
    unhealthy_weight: 15.0,
    down_event_weight: 5.0,
    saturated_penalty: 40.0,
    constraint_penalty: 500.0,
    local_bias: 2.0
  ],
  placement_constraints: [
    max_agents_per_node: nil,
    max_queue_per_node: nil
  ],
  backpressure: [
    enabled: true,
    cluster_saturation_threshold: 0.85,
    max_node_utilization: 0.98
  ],
  routing: [
    enabled: false,
    at_least_once: true,
    dedupe_enabled: true,
    dedupe_ttl_ms: 300_000,
    max_attempts: 3,
    retry_delay_ms: 100,
    rpc_timeout_ms: 5_000
  ],
  placement_observability: [
    enabled: true,
    interval_ms: 5_000,
    history_size: 120
  ],
  workload_routing: [
    enabled: false,
    strict: false,
    classes: %{
      "cpu" => ["cpu"],
      "io" => ["io"],
      "external_api" => ["external_api"]
    },
    local_capabilities: [],
    node_capabilities: %{}
  ],
  capacity_tuning: [
    enabled: false,
    interval_ms: 10_000,
    min_queue_size: 50,
    max_queue_size: 500,
    up_step: 25,
    down_step: 10,
    high_rejection_ratio: 0.08,
    low_rejection_ratio: 0.01
  ],
  rpc_timeout_ms: 5_000

config :libcluster,
  topologies: []
```

Production observability toggles:
```bash
export SCR_LOG_FORMAT=json
export SCR_OTEL_ENABLED=true
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_SERVICE_NAME=scr-runtime
```

Production distributed toggles:
```bash
export SCR_DISTRIBUTED_ENABLED=true
export SCR_DISTRIBUTED_PEERS="scr2@127.0.0.1,scr3@127.0.0.1"
export SCR_DISTRIBUTED_RECONNECT_MS=5000
export SCR_DISTRIBUTED_MAX_RECONNECT_MS=60000
export SCR_DISTRIBUTED_BACKOFF_MULTIPLIER=2.0
export SCR_DISTRIBUTED_FLAP_WINDOW_MS=60000
export SCR_DISTRIBUTED_FLAP_THRESHOLD=3
export SCR_DISTRIBUTED_QUARANTINE_MS=120000
export SCR_DISTRIBUTED_QUEUE_WEIGHT=1.0
export SCR_DISTRIBUTED_UTILIZATION_WEIGHT=30.0
export SCR_DISTRIBUTED_QUEUE_GROWTH_WEIGHT=10.0
export SCR_DISTRIBUTED_AGENT_WEIGHT=1.0
export SCR_DISTRIBUTED_AGENT_GROWTH_WEIGHT=5.0
export SCR_DISTRIBUTED_UNHEALTHY_WEIGHT=15.0
export SCR_DISTRIBUTED_DOWN_WEIGHT=5.0
export SCR_DISTRIBUTED_SATURATED_PENALTY=40.0
export SCR_DISTRIBUTED_CONSTRAINT_PENALTY=500.0
export SCR_DISTRIBUTED_LOCAL_BIAS=2.0
export SCR_DISTRIBUTED_MAX_AGENTS_PER_NODE=
export SCR_DISTRIBUTED_MAX_QUEUE_PER_NODE=
export SCR_DISTRIBUTED_BACKPRESSURE_ENABLED=true
export SCR_DISTRIBUTED_CLUSTER_SAT_THRESHOLD=0.85
export SCR_DISTRIBUTED_MAX_NODE_UTILIZATION=0.98
export SCR_DISTRIBUTED_ROUTING_ENABLED=false
export SCR_DISTRIBUTED_AT_LEAST_ONCE=true
export SCR_DISTRIBUTED_DEDUPE_ENABLED=true
export SCR_DISTRIBUTED_DEDUPE_TTL_MS=300000
export SCR_DISTRIBUTED_ROUTING_MAX_ATTEMPTS=3
export SCR_DISTRIBUTED_ROUTING_RETRY_DELAY_MS=100
export SCR_DISTRIBUTED_ROUTING_RPC_TIMEOUT_MS=5000
export SCR_DISTRIBUTED_PLACEMENT_OBS_ENABLED=true
export SCR_DISTRIBUTED_PLACEMENT_OBS_INTERVAL_MS=5000
export SCR_DISTRIBUTED_PLACEMENT_OBS_HISTORY_SIZE=120
export SCR_DISTRIBUTED_WORKLOAD_ROUTING_ENABLED=false
export SCR_DISTRIBUTED_WORKLOAD_ROUTING_STRICT=false
export SCR_DISTRIBUTED_WORKLOAD_CPU_REQ=cpu
export SCR_DISTRIBUTED_WORKLOAD_IO_REQ=io
export SCR_DISTRIBUTED_WORKLOAD_EXTERNAL_API_REQ=external_api
export SCR_DISTRIBUTED_LOCAL_CAPABILITIES=
export SCR_DISTRIBUTED_CAPACITY_TUNING_ENABLED=false
export SCR_DISTRIBUTED_CAPACITY_TUNING_INTERVAL_MS=10000
export SCR_DISTRIBUTED_CAPACITY_TUNING_MIN_QUEUE=50
export SCR_DISTRIBUTED_CAPACITY_TUNING_MAX_QUEUE=500
export SCR_DISTRIBUTED_CAPACITY_TUNING_UP_STEP=25
export SCR_DISTRIBUTED_CAPACITY_TUNING_DOWN_STEP=10
export SCR_DISTRIBUTED_CAPACITY_TUNING_HIGH_REJECT=0.08
export SCR_DISTRIBUTED_CAPACITY_TUNING_LOW_REJECT=0.01
export SCR_DISTRIBUTED_RPC_TIMEOUT_MS=5000
export RELEASE_COOKIE="replace-with-strong-cookie"
export SCR_TASK_QUEUE_BACKEND=memory
export SCR_TASK_QUEUE_DETS_PATH=tmp/task_queue.dets
export SCR_MEMORY_BACKEND=ets
export SCR_MEMORY_PATH=tmp/memory
export SCR_MEMORY_POSTGRES_URL=
export SCR_MEMORY_POSTGRES_HOST=
export SCR_MEMORY_POSTGRES_PORT=5432
export SCR_MEMORY_POSTGRES_USER=
export SCR_MEMORY_POSTGRES_PASSWORD=
export SCR_MEMORY_POSTGRES_DB=
export SCR_MEMORY_POSTGRES_SSL=false
```

Quick IEx checks:

```bash
iex -S mix
```
```elixir
SCR.TaskQueue.stats()
SCR.HealthCheck.stats()
SCR.Agent.health_check("planner_1")
SCR.Tools.RateLimiter.stats()
SCR.AgentContext.stats()
SCR.AgentContext.list() |> Enum.take(3)
String.slice(SCR.Telemetry.scrape(), 0, 500)

# Example context-aware tool call
ctx =
  SCR.Tools.ExecutionContext.new(%{
    mode: :strict,
    agent_id: "worker_1",
    task_id: "task_main_1",
    parent_task_id: "task_main_1",
    subtask_id: "subtask_1",
    trace_id: "trace_demo_1"
  })

SCR.Tools.Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 2}, ctx)
```

Prometheus scrape check:
```bash
curl -s http://localhost:4000/metrics/prometheus | head -n 40
```

### Grafana Starter Dashboard
Import the starter dashboard JSON:
- `priv/grafana/scr-runtime-overview.json`

It includes panels for:
- Queue depth
- Tool rate-limit decisions
- MCP call outcomes and p95 latency
- MCP server health/failure/circuit-open state

### Prometheus + Alertmanager Alert Templates
Starter templates are included:
- Prometheus rule group: `priv/monitoring/prometheus/alerts.yml`
- Alertmanager routing config: `priv/monitoring/alertmanager/alertmanager.yml`

Suggested load path:
1. Mount `priv/monitoring/prometheus/alerts.yml` into your Prometheus rule files.
2. Mount `priv/monitoring/alertmanager/alertmanager.yml` into Alertmanager.
3. Adjust receiver URLs/channels for your environment.

### One-Command Observability Stack
A prewired stack is available:
- Compose file: `docker-compose.observability.yml`
- Prometheus config: `priv/monitoring/prometheus/prometheus.yml`
- Grafana provisioning: `priv/monitoring/grafana/provisioning/`

Start stack:
```bash
docker compose -f docker-compose.observability.yml up -d
```

Or with Make:
```bash
make obs-up
```

Access:
- Prometheus: [http://localhost:9090](http://localhost:9090)
- Alertmanager: [http://localhost:9093](http://localhost:9093)
- Grafana: [http://localhost:3000](http://localhost:3000) (admin/admin)

Stop stack:
```bash
docker compose -f docker-compose.observability.yml down
```

Or with Make:
```bash
make obs-down
```

Other useful targets:
- `make obs-logs`
- `make obs-reset`

## Visual Regression Workflow
Baseline snapshots live in:
- `visual_tests/snapshots/`

Run checks locally:
```bash
npm ci
npx playwright install chromium
npm run visual:test
```

Run the CI variant (expects Phoenix already running at `http://127.0.0.1:4000`):
```bash
npm run visual:test:ci
```

Refresh baselines intentionally:
```bash
npm run visual:update
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
`v0.5.0-alpha`
