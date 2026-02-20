# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.

import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:trace_id, :task_id, :parent_task_id, :subtask_id, :agent_id]

# Default LLM configuration (Ollama for local development)
# To use OpenAI, change provider to :openai and add your API key
config :scr, :llm,
  provider: :ollama,
  base_url:
    System.get_env("LLM_BASE_URL") || System.get_env("OPENAI_BASE_URL") ||
      "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || System.get_env("OPENAI_MODEL") || "llama2",
  api_key: System.get_env("OPENAI_API_KEY"),
  timeout: 60_000

config :scr, :tools,
  safety_mode: :strict,
  fallback_to_native: false,
  workspace_root: System.get_env("SCR_WORKSPACE_ROOT") || File.cwd!(),
  max_params_bytes: 20_000,
  max_result_bytes: 100_000,
  strict_native_allowlist: [],
  sandbox: [
    file_operations: [
      strict_allow_writes: false,
      demo_allow_writes: true,
      allowed_write_prefixes: [],
      max_write_bytes: 100_000
    ],
    code_execution: [
      max_code_bytes: 4_000,
      blocked_patterns: []
    ]
  ],
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
  auto_heal: true,
  stale_heartbeat_ms: 30_000

config :scr, :tool_rate_limit,
  enabled: true,
  default_max_calls: 60,
  default_window_ms: 60_000,
  cleanup_interval_ms: 60_000,
  per_tool: %{}

config :scr, :agent_context,
  retention_ms: 3_600_000,
  cleanup_interval_ms: 300_000

config :scr, :memory_storage,
  backend: :ets,
  path: System.get_env("SCR_MEMORY_PATH") || "tmp/memory"

config :scr, SCR.Telemetry, poller_interval_ms: 10_000

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
