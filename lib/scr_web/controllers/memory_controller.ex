defmodule SCRWeb.MemoryController do
  use SCRWeb, :controller

  def index(conn, _params) do
    # Handle case where MemoryAgent isn't started (ETS tables don't exist)
    tasks = safe_list_tasks()
    agents = safe_list_agents()

    render(conn, :index,
      tasks: tasks,
      agents: agents
    )
  end

  # Safely list tasks, returning empty list if table doesn't exist
  defp safe_list_tasks do
    try do
      SCR.Agents.MemoryAgent.list_tasks()
    rescue
      ArgumentError -> []
    end
  end

  # Safely list agents, returning empty list if table doesn't exist
  defp safe_list_agents do
    try do
      SCR.Agents.MemoryAgent.list_agents()
    rescue
      ArgumentError -> []
    end
  end
end
