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
  @default_backend :memory
  @default_dets_path "tmp/task_queue.dets"

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
  Update the queue max size at runtime.
  """
  def set_max_size(max_size, server \\ __MODULE__) when is_integer(max_size) and max_size > 0 do
    GenServer.call(server, {:set_max_size, max_size})
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
    cfg = SCR.ConfigCache.get(:task_queue, [])

    max_size =
      opts
      |> Keyword.get(:max_size)
      |> case do
        nil -> Keyword.get(cfg, :max_size, 100)
        value -> value
      end

    backend = Keyword.get(opts, :backend, Keyword.get(cfg, :backend, @default_backend))
    fairness_cfg = Keyword.get(cfg, :fairness, [])

    base_state = %{
      high: :queue.new(),
      normal: :queue.new(),
      low: :queue.new(),
      size: 0,
      max_size: max_size,
      accepted: 0,
      rejected: 0,
      paused: false,
      backend: backend,
      dets_table: nil,
      next_id: 1,
      fairness_enabled: Keyword.get(fairness_cfg, :enabled, true),
      fairness_weights: Keyword.get(fairness_cfg, :class_weights, %{}),
      class_served_counts: %{}
    }

    {:ok, maybe_init_persistence(base_state, cfg, opts)}
  end

  @impl true
  def handle_call({:enqueue, _task, priority}, _from, %{size: size, max_size: max_size} = state)
      when size >= max_size do
    Logger.warning("queue.enqueue.rejected reason=queue_full")
    emit_enqueue_event(priority, :rejected, state.size, %{})
    next_state = %{state | rejected: state.rejected + 1}
    {:reply, {:error, :queue_full}, next_state}
  end

  def handle_call({:enqueue, task, priority}, _from, state) do
    Trace.put_metadata(Trace.from_task(task))
    Logger.info("queue.enqueue.accepted priority=#{priority}")
    item = %{id: state.next_id, task: task}
    queue = Map.fetch!(state, priority)
    next_queue = :queue.in(item, queue)

    next_state =
      state
      |> Map.put(priority, next_queue)
      |> increment_size()
      |> increment_next_id()
      |> persist_enqueue(priority, item)

    emit_enqueue_event(priority, :accepted, next_state.size, task)

    broadcast({:task_created, %{task: task, priority: priority, queued_at: DateTime.utc_now()}})

    {:reply, {:ok, %{size: next_state.size}}, next_state}
  end

  def handle_call(:dequeue, _from, state) do
    case pop_next(state) do
      {:ok, item, priority, next_state} ->
        next_state = persist_dequeue(next_state, item)
        emit_dequeue_event(priority, :ok, next_state.size, item.task)
        {:reply, {:ok, item.task}, next_state}

      :empty ->
        emit_dequeue_event(:none, :empty, state.size, %{})
        {:reply, :empty, state}
    end
  end

  def handle_call(:size, _from, state), do: {:reply, state.size, state}
  def handle_call(:paused?, _from, state), do: {:reply, state.paused, state}

  def handle_call({:set_max_size, max_size}, _from, state) do
    {:reply, :ok, %{state | max_size: max_size}}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      size: state.size,
      max_size: state.max_size,
      accepted: state.accepted,
      rejected: state.rejected,
      paused: state.paused,
      backend: state.backend,
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
        size: 0,
        class_served_counts: %{}
    }

    next_state = persist_clear(next_state)
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
        size: 0,
        class_served_counts: %{}
    }

    next_state = persist_clear(next_state)
    broadcast({:queue_drained, %{count: length(tasks), at: DateTime.utc_now()}})
    {:reply, {:ok, tasks}, next_state}
  end

  @impl true
  def terminate(_reason, %{backend: :dets, dets_table: dets_table}) when is_atom(dets_table) do
    :dets.close(dets_table)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp pop_next(state) do
    with :empty <- out_queue(:high, state, state.fairness_enabled),
         :empty <- out_queue(:normal, state, state.fairness_enabled),
         :empty <- out_queue(:low, state, state.fairness_enabled) do
      :empty
    end
  end

  defp out_queue(priority, state, false) do
    case :queue.out(Map.fetch!(state, priority)) do
      {{:value, item}, rest} ->
        task_class = task_class(item.task)

        next_state =
          state
          |> Map.put(priority, rest)
          |> decrement_size()
          |> increment_served(task_class)

        emit_fairness_event(priority, task_class, :fifo)
        {:ok, item, priority, next_state}

      {:empty, _} ->
        :empty
    end
  end

  defp out_queue(priority, state, true) do
    queue = Map.fetch!(state, priority)
    items = :queue.to_list(queue)

    case items do
      [] ->
        :empty

      _ ->
        {selected_idx, selected_item, selected_class} =
          pick_fair_item(items, state.class_served_counts, state.fairness_weights)

        rebuilt =
          items
          |> List.delete_at(selected_idx)
          |> :queue.from_list()

        next_state =
          state
          |> Map.put(priority, rebuilt)
          |> decrement_size()
          |> increment_served(selected_class)

        emit_fairness_event(priority, selected_class, :weighted_pick)
        {:ok, selected_item, priority, next_state}
    end
  end

  defp pick_fair_item(items, served_counts, class_weights) do
    class_stats =
      items
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {%{task: task}, idx}, acc ->
        klass = task_class(task)
        served = Map.get(served_counts, klass, 0)
        weight = class_weight(klass, class_weights)
        score = served / max(weight, 1.0)

        case Map.get(acc, klass) do
          nil ->
            Map.put(acc, klass, %{first_idx: idx, score: score})

          existing ->
            if idx < existing.first_idx do
              Map.put(acc, klass, %{existing | first_idx: idx})
            else
              acc
            end
        end
      end)

    {selected_class, %{first_idx: selected_idx}} =
      class_stats
      |> Enum.min_by(fn {_klass, data} -> {data.score, data.first_idx} end)

    selected_item = Enum.at(items, selected_idx)
    {selected_idx, selected_item, selected_class}
  end

  defp increment_size(state) do
    %{state | size: state.size + 1, accepted: state.accepted + 1}
  end

  defp decrement_size(state) do
    %{state | size: max(state.size - 1, 0)}
  end

  defp drain_tasks(state) do
    (queue_to_list(state.high) ++ queue_to_list(state.normal) ++ queue_to_list(state.low))
    |> Enum.map(fn
      %{task: task} -> task
      other -> other
    end)
  end

  defp increment_served(state, task_class) do
    served = Map.get(state.class_served_counts, task_class, 0) + 1
    %{state | class_served_counts: Map.put(state.class_served_counts, task_class, served)}
  end

  defp task_class(task) when is_map(task) do
    Map.get(task, :workload_class) ||
      Map.get(task, "workload_class") ||
      Map.get(task, :agent_type) ||
      Map.get(task, "agent_type") ||
      Map.get(task, :type) ||
      Map.get(task, "type") ||
      "default"
  end

  defp task_class(_), do: "default"

  defp class_weight(task_class, class_weights) when is_map(class_weights) do
    value = Map.get(class_weights, task_class) || Map.get(class_weights, to_string(task_class))

    case value do
      n when is_integer(n) and n > 0 -> n * 1.0
      n when is_float(n) and n > 0 -> n
      _ -> 1.0
    end
  end

  defp queue_to_list(queue) do
    :queue.to_list(queue)
  end

  defp broadcast(payload) do
    Phoenix.PubSub.broadcast(SCR.PubSub, "tasks", payload)
  rescue
    _ -> :ok
  end

  defp emit_enqueue_event(priority, result, queue_size, task) do
    :telemetry.execute(
      [:scr, :task_queue, :enqueue],
      %{count: 1, queue_size: queue_size},
      %{
        priority: priority,
        result: result,
        task_type: Map.get(task, :type, "unknown")
      }
    )
  end

  defp emit_dequeue_event(priority, result, queue_size, task) do
    task_class = task_class(task)

    :telemetry.execute(
      [:scr, :task_queue, :dequeue],
      %{count: 1, queue_size: queue_size},
      %{
        priority: priority,
        result: result,
        task_type: Map.get(task, :type, "unknown"),
        task_class: task_class
      }
    )
  end

  defp emit_fairness_event(priority, task_class, reason) do
    :telemetry.execute(
      [:scr, :task_queue, :fairness],
      %{count: 1},
      %{priority: priority, task_class: task_class, reason: reason}
    )
  end

  defp increment_next_id(state), do: %{state | next_id: state.next_id + 1}

  defp maybe_init_persistence(state, _cfg, _opts) when state.backend != :dets, do: state

  defp maybe_init_persistence(state, cfg, opts) do
    dets_path = Keyword.get(opts, :dets_path, Keyword.get(cfg, :dets_path, @default_dets_path))
    dets_table = dets_table_name(opts)
    _ = File.mkdir_p(Path.dirname(dets_path))

    case :dets.open_file(dets_table, type: :set, file: String.to_charlist(dets_path)) do
      {:ok, _} ->
        entries =
          :dets.foldl(
            fn {id, priority, task}, acc ->
              [%{id: id, priority: normalize_priority(priority), task: task} | acc]
            end,
            [],
            dets_table
          )
          |> Enum.sort_by(& &1.id)

        restored =
          Enum.reduce(entries, %{state | dets_table: dets_table}, fn entry, acc ->
            queue = Map.fetch!(acc, entry.priority)
            next_queue = :queue.in(%{id: entry.id, task: entry.task}, queue)

            %{
              acc
              | high: if(entry.priority == :high, do: next_queue, else: acc.high),
                normal: if(entry.priority == :normal, do: next_queue, else: acc.normal),
                low: if(entry.priority == :low, do: next_queue, else: acc.low),
                size: acc.size + 1
            }
          end)

        max_id = entries |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)
        %{restored | next_id: max_id + 1}

      {:error, _} ->
        %{state | backend: :memory, dets_table: nil}
    end
  end

  defp dets_table_name(opts) do
    key = Keyword.get(opts, :name, __MODULE__) |> inspect()
    String.to_atom("scr_task_queue_store_#{:erlang.phash2(key)}")
  end

  defp persist_enqueue(state, _priority, _item) when state.backend != :dets, do: state

  defp persist_enqueue(state, priority, item) do
    _ = :dets.insert(state.dets_table, {item.id, priority, item.task})
    state
  end

  defp persist_dequeue(state, _item) when state.backend != :dets, do: state

  defp persist_dequeue(state, item) do
    _ = :dets.delete(state.dets_table, item.id)
    state
  end

  defp persist_clear(state) when state.backend != :dets, do: state

  defp persist_clear(state) do
    _ = :dets.delete_all_objects(state.dets_table)
    state
  end
end
