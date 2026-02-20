defmodule SCR.AgentContext.Shard do
  @moduledoc """
  One shard of the shared agent context store.
  """

  use GenServer

  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 300_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    cfg = SCR.ConfigCache.get(:agent_context, [])
    retention_ms = Keyword.get(cfg, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(cfg, :cleanup_interval_ms, @default_cleanup_interval_ms)
    table = :ets.new(:scr_agent_context_shard, [:set, :private, read_concurrency: true])

    Process.send_after(self(), :cleanup, cleanup_interval_ms)

    {:ok,
     %{
       table: table,
       retention_ms: retention_ms,
       cleanup_interval_ms: cleanup_interval_ms,
       cleaned_entries: 0
     }}
  end

  @impl true
  def handle_call({:upsert, task_id, attrs}, _from, state) do
    now = DateTime.utc_now()

    context =
      case :ets.lookup(state.table, task_id) do
        [{^task_id, existing}] ->
          existing
          |> Map.merge(attrs)
          |> Map.put(:updated_at, now)

        [] ->
          Map.merge(
            %{
              task_id: task_id,
              status: :queued,
              findings: [],
              created_at: now,
              updated_at: now
            },
            attrs
          )
      end

    :ets.insert(state.table, {task_id, context})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_finding, task_id, finding}, _from, state) do
    now = DateTime.utc_now()

    context =
      case :ets.lookup(state.table, task_id) do
        [{^task_id, existing}] ->
          findings = [finding | Map.get(existing, :findings, [])] |> Enum.take(100)
          existing |> Map.put(:findings, findings) |> Map.put(:updated_at, now)

        [] ->
          %{
            task_id: task_id,
            status: :in_progress,
            findings: [finding],
            created_at: now,
            updated_at: now
          }
      end

    :ets.insert(state.table, {task_id, context})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_status, task_id, status}, _from, state) do
    now = DateTime.utc_now()

    context =
      case :ets.lookup(state.table, task_id) do
        [{^task_id, existing}] ->
          existing |> Map.put(:status, status) |> Map.put(:updated_at, now)

        [] ->
          %{task_id: task_id, status: status, findings: [], created_at: now, updated_at: now}
      end

    :ets.insert(state.table, {task_id, context})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, task_id}, _from, state) do
    reply =
      case :ets.lookup(state.table, task_id) do
        [{^task_id, context}] -> {:ok, context}
        [] -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    contexts = :ets.tab2list(state.table) |> Enum.map(fn {_task_id, context} -> context end)
    {:reply, contexts, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{entries: :ets.info(state.table, :size), cleaned_entries: state.cleaned_entries},
     state}
  end

  @impl true
  def handle_call(:run_cleanup, _from, state) do
    {deleted, next_state} = cleanup(state)
    {:reply, {:ok, deleted}, next_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {_deleted, next_state} = cleanup(state)
    Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
    {:noreply, next_state}
  end

  defp cleanup(state) do
    now = DateTime.utc_now()

    deleted =
      :ets.foldl(
        fn {task_id, context}, acc ->
          updated_at = Map.get(context, :updated_at, Map.get(context, :created_at, now))
          stale_ms = DateTime.diff(now, updated_at, :millisecond)

          if stale_ms > state.retention_ms do
            :ets.delete(state.table, task_id)
            acc + 1
          else
            acc
          end
        end,
        0,
        state.table
      )

    {deleted, %{state | cleaned_entries: state.cleaned_entries + deleted}}
  end
end
