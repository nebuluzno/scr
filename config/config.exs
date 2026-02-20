# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.

import Config

# Default LLM configuration (Ollama for local development)
# To use OpenAI, change provider to :openai and add your API key
config :scr, :llm,
  provider: :ollama,
  base_url: System.get_env("LLM_BASE_URL") || "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || "llama2",
  timeout: 60_000

config :scr, :tools,
  safety_mode: :strict,
  fallback_to_native: false,
  workspace_root: System.get_env("SCR_WORKSPACE_ROOT") || File.cwd!(),
  max_params_bytes: 20_000,
  max_result_bytes: 100_000,
  strict_native_allowlist: [],
  mcp: [
    enabled: false,
    startup_timeout_ms: 5_000,
    call_timeout_ms: 10_000,
    refresh_interval_ms: 60_000,
    max_failures: 3,
    servers: %{}
  ]

config :scr, :task_queue, max_size: 100

config :scr, :health_check,
  interval_ms: 15_000,
  auto_heal: true

config :scr, :tool_rate_limit,
  enabled: true,
  default_max_calls: 60,
  default_window_ms: 60_000,
  per_tool: %{}

# Import environment-specific config
if config_env() == :dev do
  import_config "dev.exs"
end

if config_env() == :test do
  import_config "test.exs"
end

if config_env() == :prod do
  import_config "prod.exs"
end
