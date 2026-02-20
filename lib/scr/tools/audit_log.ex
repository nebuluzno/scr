defmodule SCR.Tools.AuditLog do
  @moduledoc """
  In-memory audit trail for tool authorization/execution decisions.
  """

  use GenServer

  @table :scr_tool_audit_log
  @dets_table :scr_tool_audit_log_dets
  @default_limit 200

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def record(entry, server \\ __MODULE__) when is_map(entry) do
    GenServer.cast(server, {:record, entry})
  end

  def recent(limit \\ 25, server \\ __MODULE__) when is_integer(limit) and limit > 0 do
    GenServer.call(server, {:recent, limit})
  end

  @impl true
  def init(opts) do
    tools_cfg = SCR.ConfigCache.get(:tools, [])
    audit_cfg = Keyword.get(tools_cfg, :audit, [])
    backend = Keyword.get(opts, :backend, Keyword.get(audit_cfg, :backend, :ets))
    limit = Keyword.get(opts, :limit, Keyword.get(audit_cfg, :max_entries, @default_limit))

    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:ordered_set, :named_table, :public, read_concurrency: true])
    else
      :ets.delete_all_objects(@table)
    end

    {seq, dets_ref} =
      case backend do
        :dets ->
          path =
            Keyword.get(opts, :path, Keyword.get(audit_cfg, :path, "tmp/tool_audit_log.dets"))

          open_dets(path)

        _ ->
          {0, nil}
      end

    {:ok, %{limit: limit, seq: seq, backend: backend, dets_table: dets_ref}}
  end

  @impl true
  def handle_cast({:record, entry}, state) do
    seq = state.seq + 1
    timestamp = DateTime.utc_now()

    normalized =
      entry
      |> Map.put_new(:decision, :unknown)
      |> Map.put_new(:reason, :unknown)
      |> Map.put_new(:source, :unknown)
      |> Map.put_new(:tool, "unknown")
      |> Map.put_new(:timestamp, timestamp)
      |> Map.put_new(:seq, seq)

    :ets.insert(@table, {seq, normalized})
    maybe_persist_entry(state, seq, normalized)
    trim_old(state.limit, state.dets_table)

    if Process.whereis(SCR.PubSub) do
      Phoenix.PubSub.broadcast(SCR.PubSub, "tool_audit", {:tool_audit_updated, normalized})
    end

    {:noreply, %{state | seq: seq}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    entries =
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {seq, _entry} -> -seq end)
      |> Enum.take(limit)
      |> Enum.map(fn {_seq, entry} -> entry end)

    {:reply, entries, state}
  end

  @impl true
  def terminate(_reason, %{dets_table: dets_table}) when is_atom(dets_table) do
    _ = :dets.sync(dets_table)
    _ = :dets.close(dets_table)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp trim_old(limit, dets_table) do
    size = :ets.info(@table, :size) || 0

    if size > limit do
      drop_count = size - limit

      @table
      |> :ets.first()
      |> drop_n(drop_count, dets_table)
    end
  end

  defp drop_n(_key, 0, _dets_table), do: :ok
  defp drop_n(:"$end_of_table", _count, _dets_table), do: :ok

  defp drop_n(key, count, dets_table) do
    next = :ets.next(@table, key)
    :ets.delete(@table, key)
    if is_atom(dets_table), do: :dets.delete(dets_table, key)
    drop_n(next, count - 1, dets_table)
  end

  defp maybe_persist_entry(%{backend: :dets, dets_table: dets_table}, seq, entry)
       when is_atom(dets_table) do
    _ = :dets.insert(dets_table, {seq, entry})
    :ok
  end

  defp maybe_persist_entry(_state, _seq, _entry), do: :ok

  defp open_dets(path) do
    _ = File.mkdir_p(Path.dirname(path))
    file = String.to_charlist(path)

    case :dets.open_file(@dets_table, type: :set, file: file) do
      {:ok, table} ->
        seq =
          table
          |> :dets.match_object({:"$1", :"$2"})
          |> Enum.sort_by(fn {entry_seq, _} -> entry_seq end)
          |> Enum.reduce(0, fn {entry_seq, entry}, _acc ->
            :ets.insert(@table, {entry_seq, entry})
            max(entry_seq, 0)
          end)

        {seq, table}

      {:error, _reason} ->
        {0, nil}
    end
  end
end
