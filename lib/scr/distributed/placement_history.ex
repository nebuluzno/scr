defmodule SCR.Distributed.PlacementHistory do
  @moduledoc """
  Captures periodic distributed placement snapshots for observability dashboards.
  """

  use GenServer

  @topic "distributed_observability"
  @default_interval_ms 5_000
  @default_max_entries 120

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def recent(limit \\ 20) do
    GenServer.call(__MODULE__, {:recent, limit})
  end

  def latest do
    GenServer.call(__MODULE__, :latest)
  end

  def capture_now do
    GenServer.call(__MODULE__, :capture_now)
  end

  @impl true
  def init(_opts) do
    state = %{
      enabled: enabled?(),
      interval_ms: interval_ms(),
      max_entries: max_entries(),
      entries: []
    }

    if state.enabled do
      Process.send_after(self(), :capture_tick, 0)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    {:reply, Enum.take(state.entries, max(limit, 0)), state}
  end

  def handle_call(:latest, _from, state) do
    {:reply, List.first(state.entries), state}
  end

  def handle_call(:capture_now, _from, state) do
    {snapshot, next_state} = capture_snapshot(state)
    {:reply, snapshot, next_state}
  end

  @impl true
  def handle_info(:capture_tick, state) do
    {_snapshot, next_state} = capture_snapshot(state)

    if next_state.enabled do
      Process.send_after(self(), :capture_tick, next_state.interval_ms)
    end

    {:noreply, next_state}
  end

  defp capture_snapshot(state) do
    snapshot = build_snapshot()

    entries =
      [snapshot | state.entries]
      |> Enum.take(state.max_entries)

    _ =
      Phoenix.PubSub.broadcast(
        SCR.PubSub,
        @topic,
        {:placement_observability_updated, snapshot}
      )

    {snapshot, %{state | entries: entries}}
  end

  defp build_snapshot do
    report =
      case SCR.Distributed.placement_report() do
        {:ok, entries} when is_list(entries) -> entries
        _ -> []
      end

    pressure =
      case SCR.Distributed.queue_pressure_report() do
        {:ok, entries} when is_list(entries) -> entries
        _ -> []
      end

    watchdog =
      if Process.whereis(SCR.Distributed.NodeWatchdog) do
        SCR.Distributed.NodeWatchdog.status()
      else
        %{enabled: false, quarantined_nodes: %{}, recent_down_events: %{}}
      end

    %{
      captured_at: DateTime.utc_now(),
      placement_report: report,
      pressure_report: pressure,
      watchdog: watchdog,
      best_node: best_node(report)
    }
  end

  defp best_node([_ | _] = report) do
    Enum.max_by(report, &Map.get(&1, :score, -1_000_000))
  rescue
    _ -> nil
  end

  defp best_node(_), do: nil

  defp distributed_config do
    SCR.ConfigCache.get(:distributed, [])
  end

  defp observability_config do
    distributed_config()
    |> Keyword.get(:placement_observability, [])
  end

  defp enabled? do
    observability_config()
    |> Keyword.get(:enabled, true)
  end

  defp interval_ms do
    observability_config()
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end

  defp max_entries do
    observability_config()
    |> Keyword.get(:history_size, @default_max_entries)
  end
end
