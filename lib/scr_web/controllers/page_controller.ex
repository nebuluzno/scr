defmodule SCRWeb.PageController do
  use SCRWeb, :controller

  def home(conn, _params) do
    # Get system status
    agents = SCR.Supervisor.list_agents()
    agent_statuses = Enum.map(agents, fn agent_id ->
      case SCR.Supervisor.get_agent_status(agent_id) do
        {:ok, status} -> status
        _ -> %{agent_id: agent_id, status: "unknown"}
      end
    end)

    cache_stats = SCR.LLM.Cache.stats()
    metrics_stats = SCR.LLM.Metrics.stats()

    render(conn, :home, 
      agents: agent_statuses,
      agent_count: length(agents),
      cache_stats: cache_stats,
      metrics_stats: metrics_stats
    )
  end
end
