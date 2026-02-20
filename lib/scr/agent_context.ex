defmodule SCR.AgentContext do
  @moduledoc """
  Shared task context store for multi-agent workflows.
  """

  use GenServer

  @table :scr_agent_context

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def upsert(task_id, attrs) when is_binary(task_id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:upsert, task_id, attrs})
  end

  def add_finding(task_id, finding) when is_binary(task_id) do
    GenServer.call(__MODULE__, {:add_finding, task_id, finding})
  end

  def set_status(task_id, status) when is_binary(task_id) do
    GenServer.call(__MODULE__, {:set_status, task_id, status})
  end

  def get(task_id) when is_binary(task_id) do
    case :ets.lookup(@table, task_id) do
      [{^task_id, context}] -> {:ok, context}
      [] -> {:error, :not_found}
    end
  end

  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_task_id, context} -> context end)
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call({:upsert, task_id, attrs}, _from, state) do
    now = DateTime.utc_now()

    context =
      case get(task_id) do
        {:ok, existing} ->
          existing
          |> Map.merge(attrs)
          |> Map.put(:updated_at, now)

        {:error, :not_found} ->
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

    :ets.insert(@table, {task_id, context})
    {:reply, :ok, state}
  end

  def handle_call({:add_finding, task_id, finding}, _from, state) do
    now = DateTime.utc_now()

    context =
      case get(task_id) do
        {:ok, existing} ->
          findings = [finding | Map.get(existing, :findings, [])] |> Enum.take(100)
          existing |> Map.put(:findings, findings) |> Map.put(:updated_at, now)

        {:error, :not_found} ->
          %{
            task_id: task_id,
            status: :in_progress,
            findings: [finding],
            created_at: now,
            updated_at: now
          }
      end

    :ets.insert(@table, {task_id, context})
    {:reply, :ok, state}
  end

  def handle_call({:set_status, task_id, status}, _from, state) do
    now = DateTime.utc_now()

    context =
      case get(task_id) do
        {:ok, existing} ->
          existing |> Map.put(:status, status) |> Map.put(:updated_at, now)

        {:error, :not_found} ->
          %{task_id: task_id, status: status, findings: [], created_at: now, updated_at: now}
      end

    :ets.insert(@table, {task_id, context})
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end
end
