defmodule SCRWeb.MemoryController do
  use SCRWeb, :controller

  def index(conn, _params) do
    tasks = list_task_rows()
    agents = list_agent_rows()

    render(conn, :index,
      tasks: tasks,
      agents: agents
    )
  end

  defp list_task_rows do
    try do
      SCR.Agents.MemoryAgent.list_tasks()
      |> Enum.map(&build_task_row/1)
      |> Enum.sort_by(&sort_timestamp(&1.updated_at), {:desc, DateTime})
    rescue
      ArgumentError -> []
    end
  end

  defp build_task_row(task_id) do
    id = to_string(task_id)

    task_data =
      case SCR.Agents.MemoryAgent.get_task(task_id) do
        {:ok, data} -> data
        _ -> %{}
      end

    context =
      case SCR.AgentContext.get(id) do
        {:ok, ctx} -> ctx
        _ -> %{}
      end

    %{
      task_id: id,
      description: Map.get(task_data, :description, Map.get(context, :description, "")),
      type: Map.get(task_data, :type, :task),
      status: Map.get(context, :status, :unknown),
      trace_id: Map.get(context, :trace_id),
      parent_task_id: Map.get(context, :parent_task_id),
      subtask_id: Map.get(context, :subtask_id),
      updated_at: Map.get(context, :updated_at, Map.get(context, :created_at)),
      has_result: has_result?(task_id)
    }
  end

  defp has_result?(task_id) do
    match?({:ok, _}, SCR.Agents.MemoryAgent.get_result(task_id))
  rescue
    _ -> false
  end

  defp list_agent_rows do
    try do
      SCR.Agents.MemoryAgent.list_agents()
      |> Enum.map(&build_agent_row/1)
      |> Enum.sort_by(& &1.agent_id)
    rescue
      ArgumentError -> []
    end
  end

  defp build_agent_row(agent_id) do
    state =
      case SCR.Agents.MemoryAgent.get_agent_state(agent_id) do
        {:ok, data} -> data
        _ -> %{}
      end

    %{
      agent_id: to_string(agent_id),
      status: Map.get(state, :status, :unknown),
      agent_type: Map.get(state, :agent_type, :unknown)
    }
  end

  defp sort_timestamp(%DateTime{} = ts), do: ts
  defp sort_timestamp(_), do: DateTime.from_unix!(0)
end
