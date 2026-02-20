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

    # Create supervisor tree
    children = [
      # Start PubSub for real-time updates
      {Phoenix.PubSub, name: SCR.PubSub},
      # Start LLM Cache and Metrics
      {SCR.LLM.Cache, [enabled: true]},
      {SCR.LLM.Metrics, []},
      # Start Tools Registry with default tools
      {SCR.Tools.Registry, default_tools: @default_tools},
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

    Supervisor.start_link(children, strategy: :one_for_one, name: SCR.Supervisor.Tree)
  end
end
