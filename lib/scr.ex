defmodule SCR do
  @moduledoc """
  Supervised Cognitive Runtime (SCR) - Multi-agent cognition runtime on BEAM.

  A fault-tolerant, persistent multi-agent system built on OTP principles.
  """

  use Application

  @default_tools [
    SCR.Tools.Calculator,
    SCR.Tools.HTTPRequest,
    SCR.Tools.Search,
    SCR.Tools.FileOperations,
    SCR.Tools.Time,
    SCR.Tools.Weather,
    SCR.Tools.CodeExecution
  ]

  def start(_type, _args) do
    IO.puts("\n🔧 Starting SCR Application...")
    :ok = SCR.ConfigCache.refresh_all()

    # Create supervisor tree
    children =
      [
        # Start PubSub for real-time updates
        {Phoenix.PubSub, name: SCR.PubSub},
        # Optional libcluster node discovery
        cluster_supervisor_child(),
        # Telemetry poller + Prometheus reporter
        {SCR.Telemetry, []},
        # Runtime telemetry event stream
        {SCR.Telemetry.Stream, []},
        # Optional OpenTelemetry export bridge
        {SCR.Observability.OTelBridge, []},
        # Start LLM Cache and Metrics
        {SCR.LLM.Cache, [enabled: true]},
        {SCR.LLM.Metrics, []},
        # Start Tools Registry with default tools
        {SCR.Tools.Registry, default_tools: @default_tools},
        # Distributed spec replication + handoff
        {SCR.Distributed.SpecRegistry, []},
        {SCR.Distributed.NodeWatchdog, []},
        {SCR.Distributed.HandoffManager, []},
        # Distributed peer connectivity manager (no-op unless enabled in config)
        {SCR.Distributed.PeerManager, []},
        # Start MCP server manager (no-op unless enabled in config)
        {SCR.Tools.MCP.ServerManager, []},
        # Tool call rate limiting
        {SCR.Tools.RateLimiter, []},
        # Start priority task queue with backpressure
        {SCR.TaskQueue, []},
        # Shared multi-agent task context
        {SCR.AgentContext, []},
        # Start Phoenix endpoint
        SCRWeb.Endpoint,
        # Start the main SCR supervisor
        {SCR.Supervisor, []},
        # Periodic health checks + self-healing hooks
        {SCR.HealthCheck, []}
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: SCR.Supervisor.Tree)
  end

  defp cluster_supervisor_child do
    topologies = Application.get_env(:libcluster, :topologies, [])

    if topologies != [] and Code.ensure_loaded?(Cluster.Supervisor) do
      {Cluster.Supervisor, [topologies, [name: SCR.ClusterSupervisor]]}
    else
      nil
    end
  end
end
