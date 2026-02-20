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
  failover_enabled: true,
  failover_mode: :fail_closed,
  failover_providers: [:ollama, :openai, :anthropic],
  failover_errors: [:connection_error, :timeout, :http_error, :api_error],
  failover_cooldown_ms: 30_000,
  failover_fail_open_provider: :mock,
  failover_retry_budget: [max_retries: 50, window_ms: 60_000],
  base_url:
    System.get_env("LLM_BASE_URL") || System.get_env("OPENAI_BASE_URL") ||
      System.get_env("ANTHROPIC_BASE_URL") ||
      "http://localhost:11434",
  default_model:
    System.get_env("LLM_MODEL") || System.get_env("OPENAI_MODEL") ||
      System.get_env("ANTHROPIC_MODEL") || "llama2",
  api_key: System.get_env("OPENAI_API_KEY") || System.get_env("ANTHROPIC_API_KEY"),
  anthropic_api_version: System.get_env("ANTHROPIC_API_VERSION") || "2023-06-01",
  timeout: 60_000

config :scr, :tools,
  safety_mode: :strict,
  policy_profile: :strict,
  fallback_to_native: false,
  workspace_root: System.get_env("SCR_WORKSPACE_ROOT") || File.cwd!(),
  max_params_bytes: 20_000,
  max_result_bytes: 100_000,
  strict_native_allowlist: [],
  audit: [
    backend: :ets,
    path: "tmp/tool_audit_log.dets",
    max_entries: 200
  ],
  tool_overrides: %{},
  profiles: %{
    :strict => [
      strict_native_allowlist: [],
      tool_overrides: %{}
    ],
    :balanced => [
      strict_native_allowlist: ["code_execution"],
      tool_overrides: %{
        "code_execution" => [enabled: true, max_params_bytes: 10_000, max_result_bytes: 120_000]
      }
    ],
    :research => [
      strict_native_allowlist: ["code_execution"],
      tool_overrides: %{
        "code_execution" => [enabled: true, max_params_bytes: 12_000, max_result_bytes: 150_000],
        "search" => [enabled: true]
      }
    ]
  },
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

config :scr, :task_queue,
  max_size: 100,
  backend: :memory,
  dets_path: System.get_env("SCR_TASK_QUEUE_DETS_PATH") || "tmp/task_queue.dets",
  fairness: [
    enabled: true,
    class_weights: %{}
  ]

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
  # :ets | :dets | :sqlite | :postgres
  backend: :ets,
  path: System.get_env("SCR_MEMORY_PATH") || "tmp/memory",
  postgres: [
    url: System.get_env("SCR_MEMORY_POSTGRES_URL"),
    hostname: System.get_env("SCR_MEMORY_POSTGRES_HOST"),
    port:
      case System.get_env("SCR_MEMORY_POSTGRES_PORT") do
        nil -> 5432
        value -> String.to_integer(value)
      end,
    username: System.get_env("SCR_MEMORY_POSTGRES_USER"),
    password: System.get_env("SCR_MEMORY_POSTGRES_PASSWORD"),
    database: System.get_env("SCR_MEMORY_POSTGRES_DB"),
    ssl: System.get_env("SCR_MEMORY_POSTGRES_SSL", "false") == "true"
  ]

config :scr, SCR.Telemetry, poller_interval_ms: 10_000

config :scr, SCR.Observability.OTelBridge, enabled: false

config :scr, :distributed,
  enabled: false,
  cluster_registry: true,
  handoff_enabled: true,
  watchdog_enabled: true,
  peers: [],
  reconnect_interval_ms: 5_000,
  max_reconnect_interval_ms: 60_000,
  backoff_multiplier: 2.0,
  flap_window_ms: 60_000,
  flap_threshold: 3,
  quarantine_ms: 120_000,
  placement_weights: [
    queue_depth_weight: 1.0,
    queue_utilization_weight: 30.0,
    queue_growth_weight: 10.0,
    agent_count_weight: 1.0,
    agent_growth_weight: 5.0,
    unhealthy_weight: 15.0,
    down_event_weight: 5.0,
    saturated_penalty: 40.0,
    constraint_penalty: 500.0,
    local_bias: 2.0
  ],
  placement_constraints: [
    max_agents_per_node: nil,
    max_queue_per_node: nil
  ],
  backpressure: [
    enabled: true,
    cluster_saturation_threshold: 0.85,
    max_node_utilization: 0.98
  ],
  routing: [
    enabled: false,
    at_least_once: true,
    dedupe_enabled: true,
    dedupe_ttl_ms: 300_000,
    max_attempts: 3,
    retry_delay_ms: 100,
    rpc_timeout_ms: 5_000
  ],
  placement_observability: [
    enabled: true,
    interval_ms: 5_000,
    history_size: 120
  ],
  workload_routing: [
    enabled: false,
    strict: false,
    classes: %{
      "cpu" => ["cpu"],
      "io" => ["io"],
      "external_api" => ["external_api"]
    },
    node_capabilities: %{}
  ],
  capacity_tuning: [
    enabled: false,
    interval_ms: 10_000,
    min_queue_size: 50,
    max_queue_size: 500,
    up_step: 25,
    down_step: 10,
    high_rejection_ratio: 0.08,
    low_rejection_ratio: 0.01,
    target_latency_ms: 1_000,
    avg_service_ms: 50
  ],
  rpc_timeout_ms: 5_000

config :libcluster,
  topologies: []

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
