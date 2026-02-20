defmodule SCR.Telemetry do
  @moduledoc """
  Telemetry and Prometheus metrics reporter for SCR runtime events.
  """

  use Supervisor

  import Telemetry.Metrics

  @reporter_name :scr_prometheus_metrics
  @default_poller_interval_ms 10_000

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def scrape do
    TelemetryMetricsPrometheus.Core.scrape(@reporter_name)
  end

  @impl true
  def init(_opts) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: poller_interval_ms()},
      {TelemetryMetricsPrometheus.Core,
       name: @reporter_name, metrics: metrics(), start_async: false}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      counter("scr.task_queue.enqueue.total",
        event_name: [:scr, :task_queue, :enqueue],
        measurement: :count,
        tags: [:priority, :result, :task_type]
      ),
      counter("scr.task_queue.dequeue.total",
        event_name: [:scr, :task_queue, :dequeue],
        measurement: :count,
        tags: [:priority, :result, :task_type, :task_class]
      ),
      counter("scr.task_queue.fairness.total",
        event_name: [:scr, :task_queue, :fairness],
        measurement: :count,
        tags: [:priority, :task_class, :reason]
      ),
      last_value("scr.task_queue.size",
        event_name: [:scr, :task_queue, :stats],
        measurement: :size
      ),
      last_value("scr.task_queue.max_size",
        event_name: [:scr, :task_queue, :stats],
        measurement: :max_size
      ),
      last_value("scr.task_queue.high",
        event_name: [:scr, :task_queue, :stats],
        measurement: :high
      ),
      last_value("scr.task_queue.normal",
        event_name: [:scr, :task_queue, :stats],
        measurement: :normal
      ),
      last_value("scr.task_queue.low",
        event_name: [:scr, :task_queue, :stats],
        measurement: :low
      ),
      last_value("scr.task_queue.paused",
        event_name: [:scr, :task_queue, :stats],
        measurement: :paused
      ),
      distribution("scr.tools.execute.duration.milliseconds",
        event_name: [:scr, :tools, :execute],
        measurement: :duration_ms,
        tags: [:tool, :source, :result, :agent_id],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      counter("scr.tools.execute.total",
        event_name: [:scr, :tools, :execute],
        measurement: :count,
        tags: [:tool, :source, :result, :agent_id]
      ),
      counter("scr.tools.rate_limit.total",
        event_name: [:scr, :tools, :rate_limit],
        measurement: :count,
        tags: [:tool, :result]
      ),
      counter("scr.mcp.calls.total",
        event_name: [:scr, :mcp, :call],
        measurement: :count,
        tags: [:server, :tool, :result]
      ),
      distribution("scr.mcp.calls.duration.milliseconds",
        event_name: [:scr, :mcp, :call],
        measurement: :duration_ms,
        tags: [:server, :tool, :result],
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]]
      ),
      last_value("scr.mcp.server.healthy",
        event_name: [:scr, :mcp, :server, :status],
        measurement: :healthy,
        tags: [:server]
      ),
      last_value("scr.mcp.server.failures",
        event_name: [:scr, :mcp, :server, :status],
        measurement: :failures,
        tags: [:server]
      ),
      last_value("scr.mcp.server.circuit_open",
        event_name: [:scr, :mcp, :server, :status],
        measurement: :circuit_open,
        tags: [:server]
      ),
      counter("scr.health.check.total",
        event_name: [:scr, :health, :check],
        measurement: :count,
        tags: [:result, :agent_id]
      ),
      counter("scr.health.heal.total",
        event_name: [:scr, :health, :heal],
        measurement: :count,
        tags: [:result, :agent_id]
      ),
      last_value("scr.health.unhealthy.total",
        event_name: [:scr, :health, :stats],
        measurement: :unhealthy
      ),
      last_value("scr.health.healed.total",
        event_name: [:scr, :health, :stats],
        measurement: :healed
      ),
      last_value("scr.llm.calls.total",
        event_name: [:scr, :llm, :stats],
        measurement: :total_calls
      ),
      last_value("scr.llm.tokens.prompt.total",
        event_name: [:scr, :llm, :stats],
        measurement: :total_prompt_tokens
      ),
      last_value("scr.llm.tokens.completion.total",
        event_name: [:scr, :llm, :stats],
        measurement: :total_completion_tokens
      ),
      last_value("scr.llm.failover.circuit_open",
        event_name: [:scr, :llm, :failover, :provider],
        measurement: :circuit_open,
        tags: [:provider]
      ),
      last_value("scr.llm.failover.failures",
        event_name: [:scr, :llm, :failover, :provider],
        measurement: :failures,
        tags: [:provider]
      ),
      last_value("scr.llm.failover.successes",
        event_name: [:scr, :llm, :failover, :provider],
        measurement: :successes,
        tags: [:provider]
      ),
      last_value("scr.llm.failover.retry_budget_remaining",
        event_name: [:scr, :llm, :failover, :budget],
        measurement: :remaining
      ),
      last_value("scr.distributed.backpressure.cluster_utilization",
        event_name: [:scr, :distributed, :backpressure, :stats],
        measurement: :cluster_utilization
      ),
      last_value("scr.distributed.backpressure.max_utilization",
        event_name: [:scr, :distributed, :backpressure, :stats],
        measurement: :max_utilization
      ),
      last_value("scr.distributed.backpressure.saturated_nodes",
        event_name: [:scr, :distributed, :backpressure, :stats],
        measurement: :saturated_nodes
      ),
      last_value("scr.distributed.backpressure.node_count",
        event_name: [:scr, :distributed, :backpressure, :stats],
        measurement: :node_count
      ),
      last_value("scr.distributed.backpressure.throttled",
        event_name: [:scr, :distributed, :backpressure, :stats],
        measurement: :throttled
      ),
      last_value("scr.distributed.placement.queue_growth_per_sec",
        event_name: [:scr, :distributed, :placement, :stats],
        measurement: :queue_growth_per_sec
      ),
      last_value("scr.distributed.placement.agent_growth_per_sec",
        event_name: [:scr, :distributed, :placement, :stats],
        measurement: :agent_growth_per_sec
      ),
      last_value("scr.distributed.placement.max_queue_growth_per_sec",
        event_name: [:scr, :distributed, :placement, :stats],
        measurement: :max_queue_growth_per_sec
      ),
      last_value("scr.distributed.placement.max_agent_growth_per_sec",
        event_name: [:scr, :distributed, :placement, :stats],
        measurement: :max_agent_growth_per_sec
      ),
      counter("scr.distributed.capacity_tuning.decision.total",
        event_name: [:scr, :distributed, :capacity_tuning, :decision],
        measurement: :count,
        tags: [:decision, :reason]
      ),
      last_value("scr.distributed.capacity_tuning.estimated_latency.milliseconds",
        event_name: [:scr, :distributed, :capacity_tuning, :decision],
        measurement: :estimated_latency_ms
      )
    ]
  end

  defp periodic_measurements, do: [{__MODULE__, :emit_runtime_stats, []}]

  def emit_runtime_stats do
    emit_task_queue_stats()
    emit_mcp_stats()
    emit_health_stats()
    emit_llm_stats()
    emit_llm_failover_stats()
    emit_distributed_backpressure_stats()
  end

  defp emit_task_queue_stats do
    case safe_call(fn -> SCR.TaskQueue.stats() end) do
      {:ok, stats} ->
        :telemetry.execute(
          [:scr, :task_queue, :stats],
          %{
            size: Map.get(stats, :size, 0),
            max_size: Map.get(stats, :max_size, 0),
            high: Map.get(stats, :high, 0),
            normal: Map.get(stats, :normal, 0),
            low: Map.get(stats, :low, 0),
            paused: if(Map.get(stats, :paused, false), do: 1, else: 0)
          },
          %{}
        )

      _ ->
        :ok
    end
  end

  defp emit_health_stats do
    case safe_call(fn -> SCR.HealthCheck.stats() end) do
      {:ok, stats} ->
        :telemetry.execute(
          [:scr, :health, :stats],
          %{
            unhealthy: Map.get(stats, :unhealthy, 0),
            healed: Map.get(stats, :healed, 0)
          },
          %{}
        )

      _ ->
        :ok
    end
  end

  defp emit_mcp_stats do
    case safe_call(fn -> SCR.Tools.MCP.ServerManager.list_servers() end) do
      {:ok, servers} when is_list(servers) ->
        Enum.each(servers, fn server ->
          :telemetry.execute(
            [:scr, :mcp, :server, :status],
            %{
              healthy: if(Map.get(server, :healthy, false), do: 1, else: 0),
              failures: Map.get(server, :failures, 0),
              circuit_open: if(Map.get(server, :circuit_open, false), do: 1, else: 0)
            },
            %{server: Map.get(server, :name, "unknown")}
          )
        end)

      _ ->
        :ok
    end
  end

  defp emit_llm_stats do
    case safe_call(fn -> SCR.LLM.Metrics.stats() end) do
      {:ok, stats} ->
        :telemetry.execute(
          [:scr, :llm, :stats],
          %{
            total_calls: Map.get(stats, :total_calls, 0),
            total_prompt_tokens: Map.get(stats, :total_prompt_tokens, 0),
            total_completion_tokens: Map.get(stats, :total_completion_tokens, 0)
          },
          %{}
        )

      _ ->
        :ok
    end
  end

  defp emit_llm_failover_stats do
    case safe_call(fn -> SCR.LLM.Client.failover_state() end) do
      {:ok, %{providers: providers, retry_budget: retry_budget}} ->
        Enum.each(providers, fn provider ->
          :telemetry.execute(
            [:scr, :llm, :failover, :provider],
            %{
              circuit_open: if(Map.get(provider, :circuit_open, false), do: 1, else: 0),
              failures: Map.get(provider, :failures, 0),
              successes: Map.get(provider, :successes, 0)
            },
            %{provider: Map.get(provider, :provider, :unknown)}
          )
        end)

        :telemetry.execute(
          [:scr, :llm, :failover, :budget],
          %{remaining: Map.get(retry_budget, :remaining, 0)},
          %{}
        )

      _ ->
        :ok
    end
  end

  defp emit_distributed_backpressure_stats do
    case safe_call(fn -> SCR.Distributed.queue_pressure_report() end) do
      {:ok, {:ok, [_ | _] = report}} ->
        utilizations = Enum.map(report, &Map.get(&1, :utilization, 0.0))
        node_count = length(utilizations)
        saturated_nodes = Enum.count(report, &Map.get(&1, :saturated, false))

        :telemetry.execute(
          [:scr, :distributed, :backpressure, :stats],
          %{
            cluster_utilization: Enum.sum(utilizations) / node_count,
            max_utilization: Enum.max(utilizations),
            saturated_nodes: saturated_nodes,
            node_count: node_count,
            throttled: if(SCR.Distributed.cluster_backpressured?(), do: 1, else: 0)
          },
          %{}
        )

      _ ->
        :ok
    end

    case safe_call(fn -> SCR.Distributed.placement_report() end) do
      {:ok, {:ok, [_ | _] = report}} ->
        queue_growth = Enum.map(report, &Map.get(&1, :queue_growth_per_sec, 0.0))
        agent_growth = Enum.map(report, &Map.get(&1, :agent_growth_per_sec, 0.0))
        node_count = length(report)

        :telemetry.execute(
          [:scr, :distributed, :placement, :stats],
          %{
            queue_growth_per_sec: Enum.sum(queue_growth) / node_count,
            agent_growth_per_sec: Enum.sum(agent_growth) / node_count,
            max_queue_growth_per_sec: Enum.max(queue_growth),
            max_agent_growth_per_sec: Enum.max(agent_growth)
          },
          %{}
        )

      _ ->
        :ok
    end
  end

  defp poller_interval_ms do
    Application.get_env(:scr, __MODULE__, [])
    |> Keyword.get(:poller_interval_ms, @default_poller_interval_ms)
  end

  defp safe_call(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
