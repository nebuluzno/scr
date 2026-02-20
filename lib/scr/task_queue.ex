defmodule SCR.TaskQueue do
  @moduledoc """
  Priority task queue with backpressure.

  Priority order: `:high` -> `:normal` -> `:low`.
  """

  use GenServer
  require Logger
  alias SCR.Trace

  @type priority :: :high | :normal | :low
  @type task :: map()

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Enqueue a task with priority.
  Returns `{:error, :queue_full}` when max size is reached.
  """
  def enqueue(task, priority \\ :normal, server \\ __MODULE__) when is_map(task) do
    GenServer.call(server, {:enqueue, task, normalize_priority(priority)})
  end

  @doc """
  Dequeue next task using priority order.
  """
  def dequeue(server \\ __MODULE__) do
    GenServer.call(server, :dequeue)
  end

  @doc """
  Current queue stats.
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  Current queue size.
  """
  def size(server \\ __MODULE__) do
    GenServer.call(server, :size)
  end

  @doc """
  Clear all queued tasks.
  """
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  def paused?(server \\ __MODULE__) do
    GenServer.call(server, :paused?)
  end

  def drain(server \\ __MODULE__) do
    GenServer.call(server, :drain)
  end

  def normalize_priority(value) when is_atom(value) do
    if value in [:high, :normal, :low], do: value, else: :normal
  end

  def normalize_priority(value) when is_binary(value) do
    value
    |> String.downcase()
    |> case do
      "high" -> :high
      "low" -> :low
      _ -> :normal
    end
  end

  def normalize_priority(value) when is_integer(value) do
    cond do
      value <= 1 -> :high
      value >= 4 -> :low
      true -> :normal
    end
  end

  def normalize_priority(_), do: :normal

  # GenServer callbacks

  @impl true
  def init(opts) do
    max_size =
      opts
      |> Keyword.get(:max_size)
      |> case do
        nil -> Application.get_env(:scr, :task_queue, []) |> Keyword.get(:max_size, 100)
        value -> value
      end

    {:ok,
     %{
       high: :queue.new(),
       normal: :queue.new(),
       low: :queue.new(),
       size: 0,
       max_size: max_size,
       accepted: 0,
       rejected: 0,
       paused: false
     }}
  end

  @impl true
  def handle_call({:enqueue, _task, _priority}, _from, %{size: size, max_size: max_size} = state)
      when size >= max_size do
    Logger.warning("queue.enqueue.rejected reason=queue_full")
    next_state = %{state | rejected: state.rejected + 1}
    {:reply, {:error, :queue_full}, next_state}
  end

  def handle_call({:enqueue, task, priority}, _from, state) do
    Trace.put_metadata(Trace.from_task(task))
    Logger.info("queue.enqueue.accepted priority=#{priority}")
    queue = Map.fetch!(state, priority)
    next_queue = :queue.in(task, queue)
    next_state = state |> Map.put(priority, next_queue) |> increment_size()

    broadcast({:task_created, %{task: task, priority: priority, queued_at: DateTime.utc_now()}})

    {:reply, {:ok, %{size: next_state.size}}, next_state}
  end

  def handle_call(:dequeue, _from, state) do
    case pop_next(state) do
      {:ok, task, next_state} ->
        {:reply, {:ok, task}, next_state}

      :empty ->
        {:reply, :empty, state}
    end
  end

  def handle_call(:size, _from, state), do: {:reply, state.size, state}
  def handle_call(:paused?, _from, state), do: {:reply, state.paused, state}

  def handle_call(:stats, _from, state) do
    stats = %{
      size: state.size,
      max_size: state.max_size,
      accepted: state.accepted,
      rejected: state.rejected,
      paused: state.paused,
      high: :queue.len(state.high),
      normal: :queue.len(state.normal),
      low: :queue.len(state.low)
    }

    {:reply, stats, state}
  end

  def handle_call(:clear, _from, state) do
    next_state = %{
      state
      | high: :queue.new(),
        normal: :queue.new(),
        low: :queue.new(),
        size: 0
    }

    {:reply, :ok, next_state}
  end

  def handle_call(:pause, _from, state) do
    Logger.warning("queue.paused")
    next_state = %{state | paused: true}
    broadcast({:queue_paused, %{at: DateTime.utc_now()}})
    {:reply, :ok, next_state}
  end

  def handle_call(:resume, _from, state) do
    Logger.info("queue.resumed")
    next_state = %{state | paused: false}
    broadcast({:queue_resumed, %{at: DateTime.utc_now()}})
    {:reply, :ok, next_state}
  end

  def handle_call(:drain, _from, state) do
    tasks = drain_tasks(state)
    Logger.warning("queue.drained count=#{length(tasks)}")

    next_state = %{
      state
      | high: :queue.new(),
        normal: :queue.new(),
        low: :queue.new(),
        size: 0
    }

    broadcast({:queue_drained, %{count: length(tasks), at: DateTime.utc_now()}})
    {:reply, {:ok, tasks}, next_state}
  end

  defp pop_next(state) do
    with :empty <- out_queue(:high, state),
         :empty <- out_queue(:normal, state),
         :empty <- out_queue(:low, state) do
      :empty
    end
  end

  defp out_queue(priority, state) do
    case :queue.out(Map.fetch!(state, priority)) do
      {{:value, task}, rest} ->
        next_state =
          state
          |> Map.put(priority, rest)
          |> decrement_size()

        {:ok, task, next_state}

      {:empty, _} ->
        :empty
    end
  end

  defp increment_size(state) do
    %{state | size: state.size + 1, accepted: state.accepted + 1}
  end

  defp decrement_size(state) do
    %{state | size: max(state.size - 1, 0)}
  end

  defp drain_tasks(state) do
    queue_to_list(state.high) ++ queue_to_list(state.normal) ++ queue_to_list(state.low)
  end

  defp queue_to_list(queue) do
    :queue.to_list(queue)
  end

  defp broadcast(payload) do
    Phoenix.PubSub.broadcast(SCR.PubSub, "tasks", payload)
  rescue
    _ -> :ok
  end
end
