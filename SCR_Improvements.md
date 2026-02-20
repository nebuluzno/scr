# SCR Improvement Suggestions

This document outlines potential improvements and optimizations for the Supervised Cognitive Runtime.

## Backlog Status Legend
- `[done]`: implemented and merged to `main`
- `[in-progress]`: partially implemented
- `[planned]`: approved but not yet implemented
- `[idea]`: candidate item, not yet scheduled

## Current Delivery Status
- `[done]` Unified hybrid tool architecture (native + MCP) via one registry/policy/execution path.
- `[done]` Strict/demo tool policy enforcement with execution context propagation.
- `[done]` MCP server lifecycle manager and smoke task (`mix scr.mcp.smoke`).
- `[done]` Web UI layout polish and docs refresh for CLI + Web UI examples.
- `[done]` Portability cleanup removing hardcoded local `/Users/lars/...` paths.
- `[done]` CI baseline: formatting, compile warnings-as-errors, tests.
- `[done]` Coverage CI artifact job (non-blocking until coverage rises).
- `[done]` Optional CI MCP smoke job (secret-gated).
- `[done]` Docs quality gate in CI (markdown lint + internal link validation).
- `[done]` Priority task queue + backpressure (`SCR.TaskQueue`) with planner/task submission wiring.
- `[done]` Agent health checks + self-heal hook (`SCR.HealthCheck`).
- `[done]` Tool rate limiting guardrail (`SCR.Tools.RateLimiter`) integrated in tool execution.
- `[done]` Shared agent task context (`SCR.AgentContext`) with planner/worker updates.
- `[done]` Deep agent health probes (`SCR.Agent.health_check/1` + optional per-agent probe callbacks).
- `[done]` Rate limiter maintenance (`SCR.Tools.RateLimiter` periodic cleanup + limiter stats).
- `[done]` Queue visibility/control in dashboard (stats + pause/resume/clear/drain actions).
- `[done]` Agent context lifecycle policy (retention + periodic cleanup + context stats).
- `[done]` Execution-context propagation (`trace_id`, `parent_task_id`, `subtask_id`) across planner/worker/tool path.
- `[done]` Tool composition/chaining utility (`SCR.Tools.Chain`) with step-level error handling.
- `[done]` Structured logging baseline with trace metadata in queue/planner/worker/tool/chain flow.
- `[done]` Web UI task/memory pages now show execution context (`trace_id`, `parent_task_id`, `subtask_id`) for debugging.
- `[done]` Telemetry event stream + Prometheus endpoint (`/metrics/prometheus`) for queue/tool/health/runtime metrics.
- `[done]` Added tool rate-limit telemetry and MCP health/circuit metrics + starter Grafana dashboard JSON.

## Roadmap Parity (From AGENTS.md Future Roadmap)
- `[planned]` OpenAI adapter support
- `[planned]` Anthropic adapter support
- `[planned]` Streaming LLM responses
- `[planned]` Persistent storage backend (beyond ETS-only runtime)
- `[planned]` Distributed agent support
- `[planned]` Enhanced tool sandboxing

## Additional Suggestions (Post-Implementation)
- `[done]` Deep health probes: per-agent health callbacks and probe-based validation in `SCR.HealthCheck`.
- `[done]` Queue visibility and controls in Web UI: `SCR.TaskQueue.stats/0`, priority counts, and admin actions (`pause`, `resume`, `drain`, `clear`).
- `[done]` Agent context lifecycle policy: retention + cleanup job in `SCR.AgentContext`.
- `[done]` Rate limiter maintenance: periodic cleanup of expired ETS buckets + limiter stats API.
- `[done]` Execution-context propagation: `trace_id`, `parent_task_id`, and `subtask_id` are propagated across planner/worker/tool path.
- `[done]` Add telemetry events for queue actions and tool execution outcomes/duration, with Prometheus export.
- `[planned]` Add production JSON log profile and OpenTelemetry log/trace export bridge.
- `[planned]` Promote visual regression from artifact-only to baseline-diff blocking checks after snapshot stabilization.

## New BEAM/OTP-Focused Suggestions
- `[idea]` Add `:telemetry` event stream + `TelemetryMetricsPrometheus` endpoint for queue depth, tool latency, and supervisor restarts, with per-agent labels.
- `[idea]` Introduce `PartitionSupervisor` for high-cardinality worker pools and sharded `AgentContext` ownership to reduce single-process contention.
- `[idea]` Add optional durable queue backend (`:disk_log` or DETS + replay) to restore queued work across node restarts while keeping current in-memory fast path.
- `[idea]` Add distributed node mode (`libcluster` + Horde/Swarm-style registry handoff) for cross-node agent spawning and failover experiments.
- `[idea]` Add `:persistent_term` backed static config cache for hot-path policy/rate-limit lookups, with safe invalidation on config reload.
- `[idea]` Add alert rule templates (Prometheus/Alertmanager) for MCP circuit-open spikes, queue saturation, and sustained rate-limit rejection bursts.

## Tutorial Track (Next Docs Phase)
- `[done]` Initial step-by-step tutorials in `TUTORIALS.md`:
  1. Getting started flow (CLI + runtime checks)
  2. Web UI queue controls
  3. MCP + safety/rate limits + context debug
- `[planned]` Expand tutorials with custom-tool authoring and full multi-agent debugging labs.

## Current Baseline Commands

CLI demo:
```bash
mix run -e "SCR.CLI.Demo.main([])"
```

Crash test:
```bash
mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"
```

Web UI:
```bash
mix phx.server
```

## New Suggestions: Docs and UI Quality

### 1. [in-progress] Visual Regression Testing for Web UI
**Why:** UI updates are now centralized and more design-driven; regressions are easier to introduce across pages.

**Suggestion:**
- Add screenshot-based regression tests for:
  - `/`
  - `/tasks/new`
  - `/metrics`
  - `/tools`
- Run checks in CI on pull requests and store baseline snapshots in repo.

**Expected Benefit:**
- Detect layout/style regressions before merge
- Make UI changes safer and faster

### 2. [done] Documentation CI Quality Gate
**Why:** CLI and Web UI docs are now expanded, and drift is likely as runtime features evolve.

**Suggestion:**
- Add docs CI checks:
  - markdown linting
  - internal link validation
  - optional command example smoke checks for key commands

**Expected Benefit:**
- Keep docs accurate and consistent
- Prevent stale commands and broken links

---

## 🚀 High Priority Improvements

### 1. [done] LiveView Real-Time Updates
**Current State:** Static pages require manual refresh
**Improvement:** Implement Phoenix LiveView for real-time updates

```elixir
# lib/scr_web/live/dashboard_live.ex
defmodule SCRWeb.DashboardLive do
  use SCRWeb, :live_view
  
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(SCR.PubSub, "agents")
    {:ok, assign(socket, agents: SCR.Supervisor.list_agents())}
  end
  
  def handle_info({:agent_started, agent}, socket) do
    {:noreply, update(socket, :agents, fn agents -> [agent | agents] end)}
  end
end
```

**Benefits:**
- Real-time agent status updates
- Live task progress tracking
- Instant metric updates
- No page refreshes needed

### 2. [done] Task Queue with Priority
**Current State:** Tasks execute immediately
**Improvement:** Implement a priority-based task queue

```elixir
defmodule SCR.TaskQueue do
  use GenServer
  
  defstruct [:high, :normal, :low]
  
  def enqueue(task, priority \\ :normal) do
    GenServer.cast(__MODULE__, {:enqueue, task, priority})
  end
  
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end
end
```

**Benefits:**
- Priority-based execution
- Rate limiting
- Task scheduling
- Better resource management

### 3. [done] Structured Logging & Tracing
**Current State:** Basic IO.puts logging
**Improvement:** Implement structured logging with OpenTelemetry

```elixir
# Add to mix.exs
{:opentelemetry, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.6"},
{:logger_json, "~> 6.0"}

# Configure structured logging
config :logger, :default_handler,
  formatter: {LoggerJSON, %{metadata: :all}}
```

**Benefits:**
- Distributed tracing
- Performance insights
- Debug production issues
- Compliance ready

---

## 🔧 Medium Priority Improvements

### 4. [done] Agent Health Checks
**Current State:** Agents can silently fail
**Improvement:** Implement health check system

```elixir
defmodule SCR.HealthCheck do
  use GenServer
  
  def check_health(agent_id) do
    case SCR.Supervisor.get_agent_pid(agent_id) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, :health_check, 5000)
        catch
          :exit, _ -> {:error, :unresponsive}
        end
      {:error, _} -> {:error, :not_found}
    end
  end
end
```

**Benefits:**
- Proactive failure detection
- Auto-restart unhealthy agents
- Monitoring integration
- SLA compliance

### 5. [done] Rate Limiting for Tools
**Current State:** Tools can be called unlimited times
**Improvement:** Add rate limiting per tool

```elixir
defmodule SCR.Tools.RateLimiter do
  use GenServer
  
  def check_rate(tool_name, max_calls, window_ms) do
    key = {tool_name, System.system_time(:millisecond) div window_ms}
    case :ets.lookup(:rate_limits, key) do
      [{^key, count}] when count >= max_calls -> {:error, :rate_limited}
      [{^key, count}] -> 
        :ets.update_element(:rate_limits, key, {2, count + 1})
        :ok
      [] ->
        :ets.insert(:rate_limits, {key, 1})
        :ok
    end
  end
end
```

**Benefits:**
- Prevent API abuse
- Cost control
- Fair resource allocation
- Protection against runaway agents

### 6. [done] Tool Composition/Chaining
**Current State:** Tools execute independently
**Improvement:** Allow tool chains

```elixir
defmodule SCR.Tools.Chain do
  def execute(chain, initial_input) do
    Enum.reduce(chain, {:ok, initial_input}, fn
      tool, {:ok, input} -> tool.execute(input)
      _, error -> error
    end)
  end
end

# Example: fetch -> parse -> transform
chain = [
  {SCR.Tools.HTTPRequest, %{url: "..."}},
  {SCR.Tools.CodeExecution, %{code: "Jason.decode!(input)"}},
  {SCR.Tools.Calculator, %{operation: "add", a: "input.total", b: 10}}
]
```

**Benefits:**
- Complex workflows
- Reusable pipelines
- Reduced LLM calls
- Better performance

### 7. [done] Agent Memory Context
**Current State:** Agents don't share context
**Improvement:** Add shared context for multi-agent tasks

```elixir
defmodule SCR.AgentContext do
  use Agent
  
  def start_link(task_id) do
    Agent.start_link(fn -> %{task_id: task_id, findings: []} end, name: via(task_id))
  end
  
  def add_finding(task_id, finding) do
    Agent.update(via(task_id), fn state -> 
      %{state | findings: [finding | state.findings]}
    end)
  end
  
  def get_context(task_id) do
    Agent.get(via(task_id), & &1)
  end
  
  defp via(task_id), do: {:via, Registry, {SCR.ContextRegistry, task_id}}
end
```

**Benefits:**
- Shared knowledge between agents
- Better coordination
- Reduced redundant work
- Context-aware decisions

---

## 📊 Performance Improvements

### 8. Connection Pooling for HTTP
**Current State:** New connection per HTTP request
**Improvement:** Use connection pooling

```elixir
# Add Finch to mix.exs
{:finch, "~> 0.16"}

# Configure pool
config :scr, SCR.Finch,
  pools: %{
    "https://api.openai.com" => [size: 10, count: 2],
    "https://api.open-meteo.com" => [size: 5, count: 1]
  }
```

**Benefits:**
- Reduced latency
- Better resource usage
- Connection reuse
- Improved throughput

### 9. Batch LLM Requests
**Current State:** One LLM call per task
**Improvement:** Batch multiple prompts

```elixir
defmodule SCR.LLM.Batch do
  def batch_complete(prompts, opts \\ []) do
    # Combine prompts with separators
    combined = Enum.join(prompts, "\n---\n")
    
    case SCR.LLM.Client.complete(combined, opts) do
      {:ok, response} ->
        # Split response back
        results = String.split(response, "---")
        {:ok, Enum.zip(prompts, results)}
      error -> error
    end
  end
end
```

**Benefits:**
- Reduced API calls
- Lower costs
- Better throughput
- Efficient batching

### 10. Lazy Agent Spawning
**Current State:** All agents start at once
**Improvement:** Spawn agents on demand

```elixir
defmodule SCR.LazyAgentPool do
  use DynamicSupervisor
  
  def get_or_spawn(agent_type) do
    case find_idle(agent_type) do
      {:ok, pid} -> {:ok, pid}
      :none -> spawn_new(agent_type)
    end
  end
  
  defp find_idle(type) do
    # Find an idle agent of the given type
    SCR.Supervisor.list_agents()
    |> Enum.find(fn id -> 
      SCR.Agent.get_status(id) == :idle and get_type(id) == type
    end)
  end
end
```

**Benefits:**
- Reduced memory usage
- Faster startup
- Better resource utilization
- Scalability

---

## 🛡️ Security Improvements

### 11. Input Sanitization
**Current State:** Direct input to tools
**Improvement:** Sanitize all inputs

```elixir
defmodule SCR.Security.Sanitizer do
  def sanitize_input(input, type) when is_binary(input) do
    input
    |> String.trim()
    |> remove_null_bytes()
    |> limit_length(type)
    |> escape_html()
  end
  
  defp remove_null_bytes(str), do: String.replace(str, "\0", "")
  
  defp limit_length(str, :prompt), do: String.slice(str, 0, 10_000)
  defp limit_length(str, :code), do: String.slice(str, 0, 50_000)
  defp limit_length(str, _), do: String.slice(str, 0, 1_000)
end
```

### 12. Audit Logging
**Current State:** No audit trail
**Improvement:** Log all agent actions

```elixir
defmodule SCR.Audit do
  def log(agent_id, action, details) do
    %{
      timestamp: DateTime.utc_now(),
      agent_id: agent_id,
      action: action,
      details: details
    }
    |> store()
    |> maybe_alert()
  end
end
```

### 13. Permission System
**Current State:** All agents have full access
**Improvement:** Role-based permissions

```elixir
defmodule SCR.Permissions do
  def can_execute?(agent_id, tool_name) do
    agent = SCR.Agent.get(agent_id)
    tool_permissions = permissions_for(agent.type)
    tool_name in tool_permissions
  end
  
  defp permissions_for(:planner), do: [:search, :http_request]
  defp permissions_for(:worker), do: [:calculator, :code_execution, :search]
  defp permissions_for(:critic), do: [:search]
  defp permissions_for(_), do: []
end
```

---

## 📈 Observability Improvements

### 14. Prometheus Metrics
**Current State:** Basic metrics
**Improvement:** Full Prometheus integration

```elixir
defmodule SCR.Metrics.Prometheus do
  use Prometheus.Metric
  
  Counter.declare(
    name: :scr_llm_calls_total,
    help: "Total LLM API calls",
    labels: [:model, :status]
  )
  
  Histogram.declare(
    name: :scr_task_duration_seconds,
    help: "Task execution duration",
    labels: [:type]
  )
end
```

### 15. Grafana Dashboard
**Improvement:** Pre-built Grafana dashboards

```yaml
# grafana/dashboards/scr.json
{
  "dashboard": {
    "title": "SCR Dashboard",
    "panels": [
      {"title": "LLM Calls/min", "type": "graph"},
      {"title": "Task Success Rate", "type": "stat"},
      {"title": "Agent Count", "type": "gauge"}
    ]
  }
}
```

---

## 🔄 Developer Experience Improvements

### 16. CLI Improvements
**Current State:** Basic CLI
**Improvement:** Interactive CLI with progress

```elixir
defmodule SCR.CLI.Interactive do
  def main(args) do
    task = parse_args(args)
    
    # Show progress bar
    ProgressBar.render(0, 100, title: "Executing task")
    
    # Subscribe to updates
    SCR.PubSub.subscribe("task:#{task.id}")
    
    receive_updates(task.id)
  end
  
  def receive_updates(task_id) do
    receive do
      {:progress, percent} ->
        ProgressBar.render(percent, 100)
        receive_updates(task_id)
      {:complete, result} ->
        ProgressBar.render(100, 100)
        print_result(result)
    end
  end
end
```

### 17. Task Templates
**Improvement:** Pre-defined task templates

```elixir
defmodule SCR.Templates do
  @templates %{
    research: %{
      description: "Research a topic",
      max_workers: 3,
      tools: [:search, :http_request],
      critic: true
    },
    analysis: %{
      description: "Analyze data",
      max_workers: 1,
      tools: [:calculator, :code_execution],
      critic: false
    }
  }
  
  def apply_template(name, overrides \\ %{}) do
    Map.merge(@templates[name], overrides)
  end
end
```

### 18. Testing Utilities
**Improvement:** Better test helpers

```elixir
defmodule SCR.TestHelpers do
  def with_mock_llm(fun) do
    SCR.LLM.Client.set_adapter(SCR.LLM.Mock)
    fun.()
  after
    SCR.LLM.Client.set_adapter(SCR.LLM.Ollama)
  end
  
  def assert_tool_called(tool_name) do
    assert_received {:tool_called, ^tool_name}
  end
end
```

---

## 📋 Implementation Priority

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 🔴 High | LiveView Updates | Medium | High |
| 🔴 High | Task Queue | Medium | High |
| 🔴 High | Structured Logging | Low | High |
| 🟡 Medium | Health Checks | Low | Medium |
| 🟡 Medium | Rate Limiting | Low | Medium |
| 🟡 Medium | Tool Chaining | Medium | High |
| 🟡 Medium | Agent Context | Medium | Medium |
| 🟢 Low | Connection Pooling | Low | Medium |
| 🟢 Low | Batch Requests | Medium | Medium |
| 🟢 Low | Lazy Spawning | Medium | Medium |
| 🔵 Security | Input Sanitization | Low | High |
| 🔵 Security | Audit Logging | Low | High |
| 🔵 Security | Permissions | Medium | High |
| 🟣 Observability | Prometheus | Low | Medium |
| 🟣 Observability | Grafana | Low | Medium |
| 🟣 DX | CLI Improvements | Medium | Medium |
| 🟣 DX | Templates | Low | Medium |
| 🟣 DX | Test Helpers | Low | High |

---

## Quick Wins (Can implement in < 1 hour each)

1. **Input Sanitization** - Add to tool execution
2. **Health Checks** - Add to agent GenServer
3. **Rate Limiting** - Add ETS-based rate limiter
4. **Audit Logging** - Add to agent actions
5. **Task Templates** - Add template module
6. **Test Helpers** - Add mock LLM adapter

---

## Recommended Next Steps

1. **Implement LiveView** - Biggest UX improvement
2. **Add Task Queue** - Essential for production
3. **Structured Logging** - Critical for debugging
4. **Health Checks** - Reliability improvement
5. **Rate Limiting** - Cost protection
