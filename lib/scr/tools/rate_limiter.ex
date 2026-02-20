defmodule SCR.Tools.RateLimiter do
  @moduledoc """
  ETS-backed fixed-window rate limiter for tool calls.
  """

  use GenServer

  @table :scr_tool_rate_limits

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

    {:ok, %{}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  defp window_bucket(window_ms) when is_integer(window_ms) and window_ms > 0 do
    div(System.system_time(:millisecond), window_ms)
  end
end
