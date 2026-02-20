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

    socket =
      assign(socket,
        agents: get_agents(),
        agent_count: get_agent_count(),
        cache_stats: get_cache_stats(),
        metrics_stats: get_metrics_stats(),
        queue_stats: get_queue_stats(),
        recent_tasks: get_recent_tasks(),
        tools: get_tools()
      )

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply,
     assign(socket,
       agent_count: get_agent_count(),
       cache_stats: get_cache_stats(),
       metrics_stats: get_metrics_stats(),
       queue_stats: get_queue_stats()
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
    agents =
      Enum.map(socket.assigns.agents, fn a ->
        if a.agent_id == agent_id, do: Map.put(a, :status, status), else: a
      end)

    {:noreply, assign(socket, agents: agents)}
  end

  @impl true
  def handle_info({:task_created, task}, socket) do
    tasks = [task | socket.assigns.recent_tasks] |> Enum.take(5)
    {:noreply, assign(socket, recent_tasks: tasks, queue_stats: get_queue_stats())}
  end

  @impl true
  def handle_info({:metrics_updated, _metrics}, socket) do
    {:noreply, assign(socket, metrics_stats: get_metrics_stats())}
  end

  @impl true
  def handle_info({:queue_paused, _payload}, socket) do
    {:noreply, assign(socket, queue_stats: get_queue_stats())}
  end

  @impl true
  def handle_info({:queue_resumed, _payload}, socket) do
    {:noreply, assign(socket, queue_stats: get_queue_stats())}
  end

  @impl true
  def handle_info({:queue_drained, _payload}, socket) do
    {:noreply, assign(socket, queue_stats: get_queue_stats())}
  end

  @impl true
  def handle_event("pause_queue", _params, socket) do
    :ok = SCR.TaskQueue.pause()

    {:noreply,
     socket |> assign(queue_stats: get_queue_stats()) |> put_flash(:info, "Queue paused")}
  end

  @impl true
  def handle_event("resume_queue", _params, socket) do
    :ok = SCR.TaskQueue.resume()

    dispatch_msg = SCR.Message.status("dashboard", "planner_1", %{action: :dispatch_next})
    _ = SCR.Supervisor.send_to_agent("planner_1", dispatch_msg)

    {:noreply,
     socket |> assign(queue_stats: get_queue_stats()) |> put_flash(:info, "Queue resumed")}
  end

  @impl true
  def handle_event("clear_queue", _params, socket) do
    :ok = SCR.TaskQueue.clear()

    {:noreply,
     socket |> assign(queue_stats: get_queue_stats()) |> put_flash(:info, "Queue cleared")}
  end

  @impl true
  def handle_event("drain_queue", _params, socket) do
    {:ok, drained_tasks} = SCR.TaskQueue.drain()

    Enum.each(drained_tasks, fn task ->
      task_id = Map.get(task, :task_id, "") |> to_string()
      _ = SCR.AgentContext.set_status(task_id, :drained)
    end)

    {:noreply,
     socket
     |> assign(queue_stats: get_queue_stats())
     |> put_flash(:info, "Queue drained (#{length(drained_tasks)} tasks)")}
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

          <div class="stat-card">
            <div class="stat-icon">📥</div>
            <div class="stat-value" id="queue-size"><%= @queue_stats.size %></div>
            <div class="stat-label">Queued Tasks</div>
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

          <div class="card">
            <div class="card-header">
              <h3 class="card-title">🧵 Queue Control</h3>
            </div>
            <div class="card-body">
              <p>
                Status:
                <span class={"badge #{if @queue_stats.paused, do: "badge-warning", else: "badge-success"}"}>
                  <%= if @queue_stats.paused, do: "Paused", else: "Running" %>
                </span>
              </p>
              <p>High: <strong><%= @queue_stats.high %></strong> | Normal: <strong><%= @queue_stats.normal %></strong> | Low: <strong><%= @queue_stats.low %></strong></p>
              <p>Rejected: <strong><%= @queue_stats.rejected %></strong></p>
              <div class="actions-bar" style="margin-top: 1rem;">
                <button class="btn btn-secondary btn-sm" phx-click="pause_queue" disabled={@queue_stats.paused}>Pause</button>
                <button class="btn btn-secondary btn-sm" phx-click="resume_queue" disabled={!@queue_stats.paused}>Resume</button>
                <button class="btn btn-secondary btn-sm" phx-click="clear_queue">Clear</button>
                <button class="btn btn-secondary btn-sm" phx-click="drain_queue">Drain</button>
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

  defp get_queue_stats do
    SCR.TaskQueue.stats()
  rescue
    _ ->
      %{size: 0, max_size: 0, accepted: 0, rejected: 0, high: 0, normal: 0, low: 0, paused: false}
  end

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
    SCR.Tools.Registry.list_tools(descriptors: true)
    |> Enum.map(fn descriptor ->
      %{name: descriptor.name, description: descriptor.description, source: descriptor.source}
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
