defmodule SCRWeb.AgentController do
  use SCRWeb, :controller

  def index(conn, _params) do
    agents = SCR.Supervisor.list_agents()

    agent_statuses =
      Enum.map(agents, fn agent_id ->
        case SCR.Supervisor.get_agent_status(agent_id) do
          {:ok, status} -> status
          _ -> %{agent_id: agent_id, status: "unknown", agent_type: "unknown"}
        end
      end)

    render(conn, :index, agents: agent_statuses)
  end

  def show(conn, %{"id" => agent_id}) do
    case SCR.Supervisor.get_agent_status(agent_id) do
      {:ok, status} ->
        render(conn, :show, agent: status)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Agent not found")
        |> redirect(to: ~p"/agents")
    end
  end
end
