# Development environment configuration
import Config

# Configure tailwind version
config :tailwind, :version, "3.4.0"

# LLM configuration for development
# Uses Ollama running locally - no API costs!
config :scr, :llm,
  provider: :ollama,
  base_url: System.get_env("LLM_BASE_URL") || "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || "llama2",
  timeout: 120_000,
  temperature: 0.7

# MCP (dev-only, env-driven)
# Example:
#   export SCR_MCP_ENABLED=true
#   export SCR_WORKSPACE_ROOT="$PWD"
#   export SCR_MCP_SERVER_NAME=filesystem
#   export SCR_MCP_SERVER_COMMAND=npx
#   export SCR_MCP_SERVER_ARGS="-y,@modelcontextprotocol/server-filesystem,$SCR_WORKSPACE_ROOT"
#   export SCR_MCP_ALLOWED_TOOLS="read_file,list_directory"
mcp_enabled = System.get_env("SCR_MCP_ENABLED", "false") == "true"
workspace_root = System.get_env("SCR_WORKSPACE_ROOT") || File.cwd!()
mcp_server_name = System.get_env("SCR_MCP_SERVER_NAME", "dev_mcp")
mcp_server_command = System.get_env("SCR_MCP_SERVER_COMMAND", "")

mcp_server_args =
  System.get_env("SCR_MCP_SERVER_ARGS", "")
  |> String.split(",", trim: true)

mcp_allowed_tools =
  System.get_env("SCR_MCP_ALLOWED_TOOLS", "")
  |> String.split(",", trim: true)

mcp_server_enabled = mcp_enabled and mcp_server_command != ""

config :scr, :tools,
  safety_mode: :strict,
  mcp: [
    enabled: mcp_enabled,
    startup_timeout_ms: 10_000,
    call_timeout_ms: 15_000,
    refresh_interval_ms: 60_000,
    servers: %{
      mcp_server_name => %{
        command: mcp_server_command,
        args: mcp_server_args,
        env: %{},
        cwd: workspace_root,
        allowed_tools: mcp_allowed_tools,
        enabled: mcp_server_enabled
      }
    }
  ]

# Phoenix configuration
config :scr, SCRWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_at_least_64_bytes_long_for_phoenix_security_12345678",
  live_view: [signing_salt: "GJXJH1F8Xc4Zw2hKmPqRsT"],
  watchers: [
    tailwind: {Tailwind, :install_and_run, [:default, []]}
  ]

# Import development specific config
import_config "dev.secret.exs"
