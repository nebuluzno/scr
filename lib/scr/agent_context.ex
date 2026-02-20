defmodule SCR.AgentContext do
  @moduledoc """
  Shared task context store for multi-agent workflows.

  Backed by partitioned shard processes to reduce contention on busy systems.
  """

  use GenServer

  @partition_name SCR.AgentContext.PartitionSupervisor
  @default_shards 8

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def upsert(task_id, attrs) when is_binary(task_id) and is_map(attrs) do
    GenServer.call(shard_server(task_id), {:upsert, task_id, attrs})
  end

  def add_finding(task_id, finding) when is_binary(task_id) do
    GenServer.call(shard_server(task_id), {:add_finding, task_id, finding})
  end

  def set_status(task_id, status) when is_binary(task_id) do
    GenServer.call(shard_server(task_id), {:set_status, task_id, status})
  end

  def get(task_id) when is_binary(task_id) do
    GenServer.call(shard_server(task_id), {:get, task_id})
  end

  def list do
    shard_pids()
    |> Enum.flat_map(&GenServer.call(&1, :list))
  end

  def clear do
    shard_pids()
    |> Enum.each(&GenServer.call(&1, :clear))

    :ok
  end

  def stats do
    shard_pids()
    |> Enum.map(&GenServer.call(&1, :stats))
    |> Enum.reduce(%{entries: 0, cleaned_entries: 0}, fn shard_stats, acc ->
      %{
        entries: acc.entries + Map.get(shard_stats, :entries, 0),
        cleaned_entries: acc.cleaned_entries + Map.get(shard_stats, :cleaned_entries, 0)
      }
    end)
    |> Map.put(:shards, shard_count())
  end

  def run_cleanup do
    deleted =
      shard_pids()
      |> Enum.reduce(0, fn pid, acc ->
        case GenServer.call(pid, :run_cleanup) do
          {:ok, n} -> acc + n
          _ -> acc
        end
      end)

    {:ok, deleted}
  end

  @impl true
  def init(_opts) do
    ensure_partition_supervisor()
    {:ok, %{}}
  end

  defp ensure_partition_supervisor do
    if Process.whereis(@partition_name) == nil do
      partitions = shard_count()

      case PartitionSupervisor.start_link(
             child_spec: {SCR.AgentContext.Shard, []},
             name: @partition_name,
             partitions: partitions
           ) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} -> raise "failed to start agent context partitions: #{inspect(reason)}"
      end
    else
      :ok
    end
  end

  defp shard_server(task_id) do
    {:via, PartitionSupervisor, {@partition_name, task_id}}
  end

  defp shard_pids do
    @partition_name
    |> Supervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  rescue
    _ -> []
  end

  defp shard_count do
    SCR.ConfigCache.get(:agent_context, [])
    |> Keyword.get(:shards, @default_shards)
  end
end
