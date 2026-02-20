defmodule SCR.Distributed.NodeWatchdog do
  @moduledoc """
  Tracks node flapping and quarantines unstable peers.

  Nodes with repeated down events inside a configured window are quarantined
  for a fixed duration and excluded from placement decisions.
  """

  use GenServer

  @default_flap_window_ms 60_000
  @default_flap_threshold 3
  @default_quarantine_ms 120_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  def quarantined?(node, server \\ __MODULE__) when is_atom(node) do
    GenServer.call(server, {:quarantined?, node})
  end

  def filter_healthy(nodes, server \\ __MODULE__) when is_list(nodes) do
    GenServer.call(server, {:filter_healthy, nodes})
  end

  def note_node_up(node, server \\ __MODULE__) when is_atom(node) do
    GenServer.cast(server, {:note_up, node})
  end

  def note_node_down(node, server \\ __MODULE__) when is_atom(node) do
    GenServer.cast(server, {:note_down, node})
  end

  def quarantine(node, ttl_ms \\ nil, server \\ __MODULE__) when is_atom(node) do
    GenServer.cast(server, {:quarantine, node, ttl_ms})
  end

  @impl true
  def init(opts) do
    cfg = Keyword.get(opts, :config, distributed_config())

    state = %{
      enabled: Keyword.get(cfg, :enabled, false) and Keyword.get(cfg, :watchdog_enabled, true),
      flap_window_ms: Keyword.get(cfg, :flap_window_ms, @default_flap_window_ms),
      flap_threshold: Keyword.get(cfg, :flap_threshold, @default_flap_threshold),
      quarantine_ms: Keyword.get(cfg, :quarantine_ms, @default_quarantine_ms),
      down_events: %{},
      quarantined_until: %{}
    }

    if state.enabled do
      :net_kernel.monitor_nodes(true)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    now_ms = now_ms()
    quarantined = active_quarantined(state.quarantined_until, now_ms)

    {:reply,
     %{
       enabled: state.enabled,
       flap_window_ms: state.flap_window_ms,
       flap_threshold: state.flap_threshold,
       quarantine_ms: state.quarantine_ms,
       quarantined_nodes: quarantined
     }, state}
  end

  @impl true
  def handle_call({:quarantined?, node}, _from, state) do
    {:reply, quarantined_in_state?(state, node), state}
  end

  @impl true
  def handle_call({:filter_healthy, nodes}, _from, state) do
    cleaned_state = cleanup_expired(state)

    healthy =
      nodes
      |> Enum.uniq()
      |> Enum.reject(&quarantined_in_state?(cleaned_state, &1))

    {:reply, healthy, cleaned_state}
  end

  @impl true
  def handle_cast({:note_up, node}, state) do
    {:noreply, clear_node_events(state, node)}
  end

  @impl true
  def handle_cast({:note_down, node}, state) do
    {:noreply, mark_down(state, node)}
  end

  @impl true
  def handle_cast({:quarantine, node, ttl_ms}, state) do
    until_ms = now_ms() + (ttl_ms || state.quarantine_ms)
    {:noreply, put_in(state.quarantined_until[node], until_ms)}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    {:noreply, clear_node_events(state, node)}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    {:noreply, mark_down(state, node)}
  end

  defp mark_down(%{enabled: false} = state, _node), do: state

  defp mark_down(state, node) do
    now_ms = now_ms()
    state = cleanup_expired(state)
    cutoff = now_ms - state.flap_window_ms

    events =
      state.down_events
      |> Map.get(node, [])
      |> Enum.filter(&(&1 >= cutoff))
      |> Kernel.++([now_ms])

    state = put_in(state.down_events[node], events)

    if length(events) >= state.flap_threshold do
      until_ms = now_ms + state.quarantine_ms
      put_in(state.quarantined_until[node], until_ms)
    else
      state
    end
  end

  defp clear_node_events(state, node) do
    state
    |> update_in([:down_events], &Map.delete(&1, node))
    |> update_in([:quarantined_until], &Map.delete(&1, node))
  end

  defp cleanup_expired(state) do
    now_ms = now_ms()
    kept = active_quarantined(state.quarantined_until, now_ms)
    %{state | quarantined_until: kept}
  end

  defp active_quarantined(quarantined_until, now_ms) do
    Enum.into(quarantined_until, %{}, fn {node, until_ms} -> {node, until_ms} end)
    |> Enum.filter(fn {_node, until_ms} -> until_ms > now_ms end)
    |> Enum.into(%{})
  end

  defp quarantined_in_state?(state, node) do
    case Map.get(state.quarantined_until, node) do
      nil -> false
      until_ms -> until_ms > now_ms()
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp distributed_config do
    SCR.ConfigCache.get(:distributed, [])
  end
end
