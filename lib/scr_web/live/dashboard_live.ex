defmodule SCRWeb.DashboardLive do
  use SCRWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SCR.PubSub, "agents")
      Phoenix.PubSub.subscribe(SCR.PubSub, "tasks")
      Phoenix.PubSub.subscribe(SCR.PubSub, "metrics")
      
      # Schedule periodic updates
      :timer.send_interval(5000, :refresh_stats)
    end
    
    socket = assign(socket, 
      agents: get_agents(),
      agent_count: get_agent_count(),
      cache_stats: get_cache_stats(),
      metrics_stats: get_metrics_stats(),
      recent_tasks: get_recent_tasks(),
      tools: get_tools()
    )
    
    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply, assign(socket,
      agent_count: get_agent_count(),
      cache_stats: get_cache_stats(),
      metrics_stats: get_metrics_stats()
    )}
  end

  @impl true
  def handle_info({:agent_started, agent}, socket) do
    agents = [agent | socket.assigns.agents]
    {:noreply, assign(socket, agents: agents, agent_count: length(agents))}
  end

  @impl true
  def handle_info({:agent_stopped, agent_id}, socket) do
    agents = Enum.reject(socket.assigns.agents, fn a -> a.agent_id == agent_id end)
    {:noreply, assign(socket, agents: agents, agent_count: length(agents))}
  end

  @impl true
  def handle_info({:agent_status, agent_id, status}, socket) do
    agents = Enum.map(socket.assigns.agents, fn a ->
      if a.agent_id == agent_id, do: Map.put(a, :status, status), else: a
    end)
    {:noreply, assign(socket, agents: agents)}
  end

  @impl true
  def handle_info({:task_created, task}, socket) do
    tasks = [task | socket.assigns.recent_tasks] |> Enum.take(5)
    {:noreply, assign(socket, recent_tasks: tasks)}
  end

  @impl true
  def handle_info({:metrics_updated, _metrics}, socket) do
    {:noreply, assign(socket, metrics_stats: get_metrics_stats())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container fade-in">
      <div class="dashboard">
        <div class="dashboard-header">
          <h1>Supervised Cognitive Runtime</h1>
          <p class="subtitle">Multi-agent cognition runtime on BEAM</p>
          <div class="live-indicator">
            <span class="live-dot pulse"></span>
            <span>Live</span>
          </div>
        </div>
        
        <div class="stats-grid">
          <div class="stat-card">
            <div class="stat-icon">👥</div>
            <div class="stat-value" id="agent-count"><%= @agent_count %></div>
            <div class="stat-label">Active Agents</div>
          </div>
          
          <div class="stat-card">
            <div class="stat-icon">💾</div>
            <div class="stat-value" id="cache-size"><%= @cache_stats.size %></div>
            <div class="stat-label">Cached Responses</div>
          </div>
          
          <div class="stat-card">
            <div class="stat-icon">📊</div>
            <div class="stat-value" id="llm-calls"><%= @metrics_stats.total_calls %></div>
            <div class="stat-label">LLM Calls</div>
          </div>
          
          <div class="stat-card">
            <div class="stat-icon">💰</div>
            <div class="stat-value" id="total-cost">$<%= :erlang.float_to_binary(@metrics_stats.total_cost, [{:decimals, 4}]) %></div>
            <div class="stat-label">Total Cost</div>
          </div>
        </div>
        
        <div class="dashboard-grid">
          <div class="card">
            <div class="card-header">
              <h3 class="card-title">🤖 Active Agents</h3>
              <a href="/agents" class="btn btn-secondary btn-sm">View All</a>
            </div>
            <div class="card-body" id="agents-list">
              <%= if @agents == [] do %>
                <div class="empty-state">
                  <div class="empty-state-icon">👻</div>
                  <p>No agents running</p>
                  <a href="/tasks/new" class="btn btn-primary btn-sm">Start a Task</a>
                </div>
              <% else %>
                <div class="agent-list">
                  <%= for agent <- @agents do %>
                    <div class="agent-item" id={"agent-#{agent.agent_id}"}>
                      <div class="agent-info">
                        <span class="agent-icon"><%= agent_type_icon(Map.get(agent, :agent_type, :unknown)) %></span>
                        <span class="agent-id"><%= agent.agent_id %></span>
                        <span class={"agent-type badge #{agent_type_badge(Map.get(agent, :agent_type, :unknown))}"}><%= to_string(Map.get(agent, :agent_type, "unknown")) %></span>
                      </div>
                      <span class={"badge #{status_badge(agent.status)}"}>
                        <%= status_text(agent.status) %>
                      </span>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
          
          <div class="card">
            <div class="card-header">
              <h3 class="card-title">🔧 Quick Tools</h3>
              <a href="/tools" class="btn btn-secondary btn-sm">View All</a>
            </div>
            <div class="card-body">
              <div class="quick-tools">
                <%= for tool <- @tools |> Enum.take(4) do %>
                  <a href="/tools" class="quick-tool-item">
                    <span class="tool-icon"><%= tool_icon(tool.name) %></span>
                    <span><%= format_tool_name(tool.name) %></span>
                  </a>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        
        <div class="actions-bar">
          <a href="/tasks/new" class="btn btn-primary">
            <span>➕</span> Submit New Task
          </a>
          <a href="/metrics" class="btn btn-secondary">
            <span>📈</span> View Metrics
          </a>
          <a href="/memory" class="btn btn-secondary">
            <span>💾</span> Memory
          </a>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_agents do
    SCR.Supervisor.list_agents()
    |> Enum.map(fn agent_id ->
      case SCR.Agent.get_status(agent_id) do
        {:ok, status} -> Map.put(status, :agent_id, agent_id)
        _ -> %{agent_id: agent_id, status: :unknown, agent_type: :unknown}
      end
    end)
  end

  defp get_agent_count, do: length(SCR.Supervisor.list_agents())

  defp get_cache_stats, do: SCR.LLM.Cache.stats()

  defp get_metrics_stats, do: SCR.LLM.Metrics.stats()

  defp get_recent_tasks do
    # Check if ETS table exists before accessing (MemoryAgent may not be started yet)
    if ets_table_exists?(:scr_tasks) do
      SCR.Agents.MemoryAgent.list_tasks()
      |> Enum.take(5)
    else
      []
    end
  end
  
  # Safely check if an ETS table exists
  defp ets_table_exists?(table_name) do
    case :ets.whereis(table_name) do
      :undefined -> false
      _ref -> true
    end
  rescue
    ArgumentError -> false
  end

  defp get_tools do
    SCR.Tools.Registry.list_tools()
    |> Enum.map(fn name ->
      case SCR.Tools.Registry.get_tool(name) do
        {:ok, module} -> %{name: name, description: apply(module, :description, [])}
        _ -> %{name: name, description: "Unknown"}
      end
    end)
  end

  defp status_badge(:running), do: "badge-success"
  defp status_badge(:idle), do: "badge-info"
  defp status_badge(:processing), do: "badge-warning"
  defp status_badge(_), do: "badge-error"

  defp status_text(:running), do: "● Running"
  defp status_text(:idle), do: "○ Idle"
  defp status_text(:processing), do: "◐ Processing"
  defp status_text(other), do: "○ " <> to_string(other)

  # Agent type icons
  defp agent_type_icon(:planner), do: "🧠"
  defp agent_type_icon(:worker), do: "⚙️"
  defp agent_type_icon(:critic), do: "🔍"
  defp agent_type_icon(:memory), do: "💾"
  defp agent_type_icon(:researcher), do: "🔬"
  defp agent_type_icon(:writer), do: "✍️"
  defp agent_type_icon(:validator), do: "✅"
  defp agent_type_icon(_), do: "🤖"

  # Agent type badges
  defp agent_type_badge(:planner), do: "badge-primary"
  defp agent_type_badge(:worker), do: "badge-info"
  defp agent_type_badge(:critic), do: "badge-warning"
  defp agent_type_badge(:memory), do: "badge-secondary"
  defp agent_type_badge(:researcher), do: "badge-success"
  defp agent_type_badge(:writer), do: "badge-info"
  defp agent_type_badge(:validator), do: "badge-success"
  defp agent_type_badge(_), do: "badge-secondary"

  defp tool_icon("calculator"), do: "🧮"
  defp tool_icon("http_request"), do: "🌐"
  defp tool_icon("search"), do: "🔍"
  defp tool_icon("file_operations"), do: "📁"
  defp tool_icon("time"), do: "⏰"
  defp tool_icon("weather"), do: "🌤️"
  defp tool_icon("code_execution"), do: "💻"
  defp tool_icon(_), do: "🔧"

  defp format_tool_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
