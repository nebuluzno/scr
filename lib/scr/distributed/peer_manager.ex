defmodule SCR.Distributed.PeerManager do
  @moduledoc """
  Simple peer connectivity manager for distributed SCR nodes.

  Periodically attempts to connect to configured peers.
  """

  use GenServer

  @default_reconnect_interval_ms 5_000
  @default_backoff_multiplier 2.0

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def connect_now do
    GenServer.call(__MODULE__, :connect_now)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(opts) do
    cfg = Keyword.get(opts, :config, distributed_config())
    enabled = Keyword.get(cfg, :enabled, false)
    peers = normalize_peers(Keyword.get(cfg, :peers, []))
    interval_ms = Keyword.get(cfg, :reconnect_interval_ms, @default_reconnect_interval_ms)
    max_interval_ms = Keyword.get(cfg, :max_reconnect_interval_ms, interval_ms * 12)
    backoff_multiplier = Keyword.get(cfg, :backoff_multiplier, @default_backoff_multiplier)

    state = %{
      enabled: enabled,
      peers: peers,
      reconnect_interval_ms: interval_ms,
      current_reconnect_interval_ms: interval_ms,
      max_reconnect_interval_ms: max_interval_ms,
      backoff_multiplier: backoff_multiplier,
      consecutive_failures: 0,
      last_connect_results: %{},
      last_connect_at: nil
    }

    if enabled do
      send(self(), :connect_tick)
      schedule_connect(interval_ms)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connect_now, _from, state) do
    new_state = connect_to_peers(state)
    {:reply, new_state.last_connect_results, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       enabled: state.enabled,
       configured_peers: state.peers,
       connected_peers: Node.list(),
       last_connect_results: state.last_connect_results,
       current_reconnect_interval_ms: state.current_reconnect_interval_ms,
       max_reconnect_interval_ms: state.max_reconnect_interval_ms,
       consecutive_failures: state.consecutive_failures,
       last_connect_at: state.last_connect_at
     }, state}
  end

  @impl true
  def handle_info(:connect_tick, state) do
    new_state = connect_to_peers(state)

    if new_state.enabled do
      schedule_connect(new_state.current_reconnect_interval_ms)
    end

    {:noreply, new_state}
  end

  defp connect_to_peers(%{enabled: false} = state), do: state

  defp connect_to_peers(state) do
    results =
      if Node.alive?() do
        Enum.into(state.peers, %{}, fn peer ->
          {peer, Node.connect(peer)}
        end)
      else
        Enum.into(state.peers, %{}, fn peer ->
          {peer, :node_not_alive}
        end)
      end

    update_backoff(%{
      state
      | last_connect_results: results,
        last_connect_at: DateTime.utc_now()
    })
  end

  defp update_backoff(state) do
    failed =
      Enum.any?(state.last_connect_results, fn {_peer, result} ->
        result not in [true, :ignored]
      end)

    if failed do
      next_interval =
        state.current_reconnect_interval_ms
        |> Kernel.*(state.backoff_multiplier)
        |> round()
        |> min(state.max_reconnect_interval_ms)
        |> max(state.reconnect_interval_ms)

      %{
        state
        | consecutive_failures: state.consecutive_failures + 1,
          current_reconnect_interval_ms: next_interval
      }
    else
      %{
        state
        | consecutive_failures: 0,
          current_reconnect_interval_ms: state.reconnect_interval_ms
      }
    end
  end

  defp schedule_connect(interval_ms) do
    Process.send_after(self(), :connect_tick, interval_ms)
  end

  defp normalize_peers(peers) when is_binary(peers) do
    peers
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end

  defp normalize_peers(peers) when is_list(peers) do
    Enum.map(peers, fn
      peer when is_atom(peer) -> peer
      peer when is_binary(peer) -> String.to_atom(peer)
      other -> other
    end)
    |> Enum.filter(&is_atom/1)
  end

  defp normalize_peers(_), do: []

  defp distributed_config do
    Application.get_env(:scr, :distributed, [])
  end
end
