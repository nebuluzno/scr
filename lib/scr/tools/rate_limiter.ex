defmodule SCR.Tools.RateLimiter do
  @moduledoc """
  ETS-backed fixed-window rate limiter for tool calls.
  """

  use GenServer

  @table :scr_tool_rate_limits
  @default_cleanup_interval_ms 60_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks and consumes one token for the tool in the current window.
  """
  def check_rate(tool_name, max_calls, window_ms) do
    key = {tool_name, window_bucket(window_ms)}
    now_ms = System.system_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, expires_at}] when count >= max_calls and now_ms < expires_at ->
        {:error, :rate_limited}

      [{^key, count, expires_at}] when now_ms < expires_at ->
        true = :ets.insert(@table, {key, count + 1, expires_at})
        :ok

      _ ->
        expires_at = now_ms + window_ms
        true = :ets.insert(@table, {key, 1, expires_at})
        :ok
    end
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    cfg = Application.get_env(:scr, :tool_rate_limit, [])
    cleanup_interval_ms = Keyword.get(cfg, :cleanup_interval_ms, @default_cleanup_interval_ms)
    Process.send_after(self(), :cleanup, cleanup_interval_ms)

    {:ok, %{cleanup_interval_ms: cleanup_interval_ms, cleaned_entries: 0}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  def handle_call(:stats, _from, state) do
    total_entries = :ets.info(@table, :size)
    {:reply, %{entries: total_entries, cleaned_entries: state.cleaned_entries}, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now_ms = System.system_time(:millisecond)

    deleted =
      :ets.select_delete(@table, [
        {{{:"$1", :"$2"}, :"$3", :"$4"}, [{:<, :"$4", now_ms}], [true]}
      ])

    Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
    {:noreply, %{state | cleaned_entries: state.cleaned_entries + deleted}}
  end

  defp window_bucket(window_ms) when is_integer(window_ms) and window_ms > 0 do
    div(System.system_time(:millisecond), window_ms)
  end
end
