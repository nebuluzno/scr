defmodule SCRWeb.TaskController do
  use SCRWeb, :controller

  def index(conn, _params) do
    tasks = list_context_tasks()
    render(conn, :index, tasks: tasks)
  end

  def new(conn, _params) do
    render(conn, :new, csrf_token: get_csrf_token())
  end

  def create(conn, %{"task" => task_params}) do
    description = Map.get(task_params, "description", "")

    if description == "" do
      conn
      |> put_flash(:error, "Task description cannot be empty")
      |> redirect(to: ~p"/tasks/new")
    else
      # Generate a task ID
      task_id = UUID.uuid4()
      trace_id = UUID.uuid4()
      priority = SCR.TaskQueue.normalize_priority(Map.get(task_params, "priority", "normal"))

      # Ensure MemoryAgent is running (ignore if already started)
      case SCR.Supervisor.start_agent("memory_1", :memory, SCR.Agents.MemoryAgent, %{}) do
        {:ok, _} -> :ok
        {:error, :already_started} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      # Ensure PlannerAgent is running (ignore if already started)
      case SCR.Supervisor.start_agent("planner_1", :planner, SCR.Agents.PlannerAgent, %{}) do
        {:ok, _} -> :ok
        {:error, :already_started} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      task_data = %{
        task_id: task_id,
        description: description,
        type: parse_task_type(Map.get(task_params, "type", "general")),
        priority: priority,
        max_workers: parse_max_workers(Map.get(task_params, "max_workers", "2")),
        trace_id: trace_id
      }

      _ =
        SCR.AgentContext.upsert(to_string(task_id), %{
          description: description,
          status: :queued,
          source: :web,
          trace_id: trace_id
        })

      queue_server =
        Application.get_env(:scr, :task_queue, []) |> Keyword.get(:server, SCR.TaskQueue)

      case SCR.TaskQueue.enqueue(task_data, priority, queue_server) do
        {:ok, _} ->
          dispatch_msg = SCR.Message.status("web", "planner_1", %{action: :dispatch_next})
          _ = SCR.Supervisor.send_to_agent("planner_1", dispatch_msg)

          conn
          |> put_flash(:info, "Task submitted successfully!")
          |> redirect(to: ~p"/tasks")

        {:error, :queue_full} ->
          _ = SCR.AgentContext.set_status(to_string(task_id), :rejected_queue_full)

          conn
          |> put_flash(:error, "Task queue is full. Please retry in a moment.")
          |> redirect(to: ~p"/tasks/new")
      end
    end
  end

  defp parse_task_type("research"), do: :research
  defp parse_task_type("analysis"), do: :analysis
  defp parse_task_type("computation"), do: :computation
  defp parse_task_type(_), do: :general

  defp parse_max_workers(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 2
    end
  end

  defp parse_max_workers(value) when is_integer(value) and value > 0, do: value
  defp parse_max_workers(_), do: 2

  defp list_context_tasks do
    SCR.AgentContext.list()
    |> Enum.map(fn ctx ->
      %{
        task_id: Map.get(ctx, :task_id),
        description: Map.get(ctx, :description, ""),
        status: Map.get(ctx, :status, :unknown),
        trace_id: Map.get(ctx, :trace_id),
        parent_task_id: Map.get(ctx, :parent_task_id),
        subtask_id: Map.get(ctx, :subtask_id),
        updated_at: Map.get(ctx, :updated_at)
      }
    end)
    |> Enum.sort_by(&sort_timestamp(&1.updated_at), {:desc, DateTime})
  rescue
    _ -> []
  end

  defp sort_timestamp(%DateTime{} = ts), do: ts
  defp sort_timestamp(_), do: DateTime.from_unix!(0)
end
