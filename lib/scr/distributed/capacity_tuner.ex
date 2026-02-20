defmodule SCR.Distributed.CapacityTuner do
  @moduledoc """
  Automatic queue capacity tuning based on recent queue pressure/rejection signals.
  """

  use GenServer

  @default_interval_ms 10_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(opts) do
    stats = safe_queue_stats(Keyword.get(opts, :queue_server, SCR.TaskQueue))

    state = %{
      enabled: Keyword.get(opts, :enabled, enabled?()),
      interval_ms: Keyword.get(opts, :interval_ms, interval_ms()),
      min_queue_size: Keyword.get(opts, :min_queue_size, min_queue_size()),
      max_queue_size: Keyword.get(opts, :max_queue_size, max_queue_size()),
      up_step: Keyword.get(opts, :up_step, up_step()),
      down_step: Keyword.get(opts, :down_step, down_step()),
      high_rejection_ratio: Keyword.get(opts, :high_rejection_ratio, high_rejection_ratio()),
      low_rejection_ratio: Keyword.get(opts, :low_rejection_ratio, low_rejection_ratio()),
      target_latency_ms: Keyword.get(opts, :target_latency_ms, target_latency_ms()),
      avg_service_ms: Keyword.get(opts, :avg_service_ms, avg_service_ms()),
      queue_server: Keyword.get(opts, :queue_server, SCR.TaskQueue),
      update_constraints: Keyword.get(opts, :update_constraints, true),
      last_accepted: Map.get(stats, :accepted, 0),
      last_rejected: Map.get(stats, :rejected, 0),
      last_size: Map.get(stats, :size, 0),
      last_max_size: Map.get(stats, :max_size, 100),
      last_decision: :none,
      last_reason: :none
    }

    if state.enabled do
      Process.send_after(self(), :tick, state.interval_ms)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:tick, state) do
    next_state = tune_once(state)

    if next_state.enabled do
      Process.send_after(self(), :tick, next_state.interval_ms)
    end

    {:noreply, next_state}
  end

  defp tune_once(state) do
    stats = safe_queue_stats(state.queue_server)
    accepted = Map.get(stats, :accepted, state.last_accepted)
    rejected = Map.get(stats, :rejected, state.last_rejected)
    queue_size = Map.get(stats, :size, state.last_size)
    current_max_size = Map.get(stats, :max_size, state.last_max_size)
    accepted_delta = max(accepted - state.last_accepted, 0)
    rejected_delta = max(rejected - state.last_rejected, 0)
    total_delta = accepted_delta + rejected_delta

    rejection_ratio =
      if total_delta > 0 do
        rejected_delta / total_delta
      else
        0.0
      end

    utilization =
      if current_max_size > 0 do
        queue_size / current_max_size
      else
        0.0
      end

    estimated_latency_ms = trunc(queue_size * state.avg_service_ms)

    {next_max_size, decision, reason} =
      cond do
        rejection_ratio >= state.high_rejection_ratio ->
          {
            min(current_max_size + state.up_step, state.max_queue_size),
            :increased,
            :high_rejection
          }

        estimated_latency_ms >= state.target_latency_ms ->
          {
            min(current_max_size + state.up_step, state.max_queue_size),
            :increased,
            :latency_slo_breach
          }

        rejection_ratio <= state.low_rejection_ratio and utilization < 0.35 ->
          {
            max(current_max_size - state.down_step, state.min_queue_size),
            :decreased,
            :low_pressure
          }

        true ->
          {current_max_size, :unchanged, :stable}
      end

    emit_tuning_event(decision, reason, rejection_ratio, utilization, estimated_latency_ms)

    if next_max_size != current_max_size do
      :ok = SCR.TaskQueue.set_max_size(next_max_size, state.queue_server)

      if state.update_constraints do
        update_distributed_queue_constraint(next_max_size)
      end
    end

    %{
      state
      | last_accepted: accepted,
        last_rejected: rejected,
        last_size: queue_size,
        last_max_size: next_max_size,
        last_decision: decision,
        last_reason: reason
    }
  end

  defp emit_tuning_event(decision, reason, rejection_ratio, utilization, estimated_latency_ms) do
    :telemetry.execute(
      [:scr, :distributed, :capacity_tuning, :decision],
      %{
        count: 1,
        rejection_ratio: rejection_ratio,
        utilization: utilization,
        estimated_latency_ms: estimated_latency_ms
      },
      %{decision: decision, reason: reason}
    )
  end

  defp safe_queue_stats(queue_server) do
    try do
      SCR.TaskQueue.stats(queue_server)
    rescue
      _ -> %{accepted: 0, rejected: 0, size: 0, max_size: 100}
    catch
      :exit, _ -> %{accepted: 0, rejected: 0, size: 0, max_size: 100}
    end
  end

  defp update_distributed_queue_constraint(max_size) do
    cfg = SCR.ConfigCache.get(:distributed, [])
    constraints = cfg |> Keyword.get(:placement_constraints, []) |> Enum.into(%{})
    next_constraints = Map.put(constraints, :max_queue_per_node, max_size)

    next_cfg = Keyword.put(cfg, :placement_constraints, Enum.into(next_constraints, []))
    Application.put_env(:scr, :distributed, next_cfg)
    _ = SCR.ConfigCache.refresh(:distributed)
    :ok
  rescue
    _ -> :ok
  end

  defp distributed_cfg do
    SCR.ConfigCache.get(:distributed, [])
  end

  defp tuning_cfg do
    distributed_cfg()
    |> Keyword.get(:capacity_tuning, [])
  end

  defp enabled? do
    tuning_cfg()
    |> Keyword.get(:enabled, false)
  end

  defp interval_ms, do: tuning_cfg() |> Keyword.get(:interval_ms, @default_interval_ms)
  defp min_queue_size, do: tuning_cfg() |> Keyword.get(:min_queue_size, 50)
  defp max_queue_size, do: tuning_cfg() |> Keyword.get(:max_queue_size, 500)
  defp up_step, do: tuning_cfg() |> Keyword.get(:up_step, 25)
  defp down_step, do: tuning_cfg() |> Keyword.get(:down_step, 10)
  defp high_rejection_ratio, do: tuning_cfg() |> Keyword.get(:high_rejection_ratio, 0.08)
  defp low_rejection_ratio, do: tuning_cfg() |> Keyword.get(:low_rejection_ratio, 0.01)
  defp target_latency_ms, do: tuning_cfg() |> Keyword.get(:target_latency_ms, 1_000)
  defp avg_service_ms, do: tuning_cfg() |> Keyword.get(:avg_service_ms, 50)
end
