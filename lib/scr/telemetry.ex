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
        tags: [:priority, :result, :task_type]
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
      )
    ]
  end

  defp periodic_measurements, do: [{__MODULE__, :emit_runtime_stats, []}]

  def emit_runtime_stats do
    emit_task_queue_stats()
    emit_mcp_stats()
    emit_health_stats()
    emit_llm_stats()
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
