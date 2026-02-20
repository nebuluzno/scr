# Production environment configuration
import Config

log_format = System.get_env("SCR_LOG_FORMAT", "text")
otel_enabled = System.get_env("SCR_OTEL_ENABLED", "false") == "true"
distributed_enabled = System.get_env("SCR_DISTRIBUTED_ENABLED", "false") == "true"
distributed_peers = System.get_env("SCR_DISTRIBUTED_PEERS", "")

distributed_peer_hosts =
  distributed_peers
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.map(&String.to_atom/1)

llm_failover_mode =
  case System.get_env("SCR_LLM_FAILOVER_MODE", "fail_closed") do
    "fail_open" -> :fail_open
    _ -> :fail_closed
  end

# LLM configuration for production
# Override these with environment variables in production!
config :scr, :llm,
  # Can be :openai, :anthropic in production
  provider: :ollama,
  failover_enabled: System.get_env("SCR_LLM_FAILOVER_ENABLED", "true") == "true",
  failover_mode: llm_failover_mode,
  failover_providers:
    System.get_env("SCR_LLM_FAILOVER_PROVIDERS", "ollama,openai,anthropic")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1),
  failover_errors: [:connection_error, :timeout, :http_error, :api_error],
  failover_cooldown_ms:
    String.to_integer(System.get_env("SCR_LLM_FAILOVER_COOLDOWN_MS", "30000")),
  failover_fail_open_provider:
    System.get_env("SCR_LLM_FAILOVER_FAIL_OPEN_PROVIDER", "mock") |> String.to_atom(),
  failover_retry_budget: [
    max_retries: String.to_integer(System.get_env("SCR_LLM_FAILOVER_RETRY_BUDGET_MAX", "50")),
    window_ms:
      String.to_integer(System.get_env("SCR_LLM_FAILOVER_RETRY_BUDGET_WINDOW_MS", "60000"))
  ],
  base_url:
    System.get_env("LLM_BASE_URL") || System.get_env("OPENAI_BASE_URL") ||
      System.get_env("ANTHROPIC_BASE_URL") ||
      "http://localhost:11434",
  default_model:
    System.get_env("LLM_MODEL") || System.get_env("OPENAI_MODEL") ||
      System.get_env("ANTHROPIC_MODEL") || "llama2",
  api_key: System.get_env("OPENAI_API_KEY") || System.get_env("ANTHROPIC_API_KEY"),
  anthropic_api_version: System.get_env("ANTHROPIC_API_VERSION") || "2023-06-01",
  timeout: 60_000,
  temperature: 0.7,
  max_retries: 3

task_queue_backend =
  case System.get_env("SCR_TASK_QUEUE_BACKEND", "memory") do
    "dets" -> :dets
    _ -> :memory
  end

memory_storage_backend =
  case System.get_env("SCR_MEMORY_BACKEND", "ets") do
    "dets" -> :dets
    "sqlite" -> :sqlite
    "postgres" -> :postgres
    _ -> :ets
  end

config :logger,
  level: :info

if log_format == "json" do
  config :logger, :console,
    format: {SCR.Logging.JSONFormatter, :format},
    metadata: :all
end

config :scr, SCR.Observability.OTelBridge, enabled: otel_enabled

config :scr, :task_queue,
  backend: task_queue_backend,
  dets_path: System.get_env("SCR_TASK_QUEUE_DETS_PATH", "tmp/task_queue.dets"),
  fairness: [
    enabled: System.get_env("SCR_TASK_QUEUE_FAIRNESS_ENABLED", "true") == "true",
    class_weights: %{}
  ]

config :scr, :memory_storage,
  backend: memory_storage_backend,
  path:
    System.get_env(
      "SCR_MEMORY_PATH",
      if(memory_storage_backend == :sqlite,
        do: "tmp/memory/scr_memory.sqlite3",
        else: "tmp/memory"
      )
    ),
  postgres: [
    url: System.get_env("SCR_MEMORY_POSTGRES_URL"),
    hostname: System.get_env("SCR_MEMORY_POSTGRES_HOST"),
    port: String.to_integer(System.get_env("SCR_MEMORY_POSTGRES_PORT", "5432")),
    username: System.get_env("SCR_MEMORY_POSTGRES_USER"),
    password: System.get_env("SCR_MEMORY_POSTGRES_PASSWORD"),
    database: System.get_env("SCR_MEMORY_POSTGRES_DB"),
    ssl: System.get_env("SCR_MEMORY_POSTGRES_SSL", "false") == "true"
  ]

policy_profile =
  case System.get_env("SCR_TOOLS_POLICY_PROFILE", "strict") do
    "balanced" -> :balanced
    "research" -> :research
    _ -> :strict
  end

tool_audit_backend =
  case System.get_env("SCR_TOOLS_AUDIT_BACKEND", "ets") do
    "dets" -> :dets
    _ -> :ets
  end

config :scr, :tools,
  policy_profile: policy_profile,
  audit: [
    backend: tool_audit_backend,
    path: System.get_env("SCR_TOOLS_AUDIT_PATH", "tmp/tool_audit_log.dets"),
    max_entries: String.to_integer(System.get_env("SCR_TOOLS_AUDIT_MAX_ENTRIES", "200"))
  ]

config :scr, :distributed,
  enabled: distributed_enabled,
  cluster_registry: true,
  handoff_enabled: true,
  watchdog_enabled: true,
  peers: distributed_peers,
  reconnect_interval_ms:
    String.to_integer(System.get_env("SCR_DISTRIBUTED_RECONNECT_MS", "5000")),
  max_reconnect_interval_ms:
    String.to_integer(System.get_env("SCR_DISTRIBUTED_MAX_RECONNECT_MS", "60000")),
  backoff_multiplier:
    String.to_float(System.get_env("SCR_DISTRIBUTED_BACKOFF_MULTIPLIER", "2.0")),
  flap_window_ms: String.to_integer(System.get_env("SCR_DISTRIBUTED_FLAP_WINDOW_MS", "60000")),
  flap_threshold: String.to_integer(System.get_env("SCR_DISTRIBUTED_FLAP_THRESHOLD", "3")),
  quarantine_ms: String.to_integer(System.get_env("SCR_DISTRIBUTED_QUARANTINE_MS", "120000")),
  placement_weights: [
    queue_depth_weight: String.to_float(System.get_env("SCR_DISTRIBUTED_QUEUE_WEIGHT", "1.0")),
    queue_utilization_weight:
      String.to_float(System.get_env("SCR_DISTRIBUTED_UTILIZATION_WEIGHT", "30.0")),
    queue_growth_weight:
      String.to_float(System.get_env("SCR_DISTRIBUTED_QUEUE_GROWTH_WEIGHT", "10.0")),
    agent_count_weight: String.to_float(System.get_env("SCR_DISTRIBUTED_AGENT_WEIGHT", "1.0")),
    agent_growth_weight:
      String.to_float(System.get_env("SCR_DISTRIBUTED_AGENT_GROWTH_WEIGHT", "5.0")),
    unhealthy_weight: String.to_float(System.get_env("SCR_DISTRIBUTED_UNHEALTHY_WEIGHT", "15.0")),
    down_event_weight: String.to_float(System.get_env("SCR_DISTRIBUTED_DOWN_WEIGHT", "5.0")),
    saturated_penalty:
      String.to_float(System.get_env("SCR_DISTRIBUTED_SATURATED_PENALTY", "40.0")),
    constraint_penalty:
      String.to_float(System.get_env("SCR_DISTRIBUTED_CONSTRAINT_PENALTY", "500.0")),
    local_bias: String.to_float(System.get_env("SCR_DISTRIBUTED_LOCAL_BIAS", "2.0"))
  ],
  placement_constraints: [
    max_agents_per_node:
      case System.get_env("SCR_DISTRIBUTED_MAX_AGENTS_PER_NODE") do
        nil -> nil
        "" -> nil
        value -> String.to_integer(value)
      end,
    max_queue_per_node:
      case System.get_env("SCR_DISTRIBUTED_MAX_QUEUE_PER_NODE") do
        nil -> nil
        "" -> nil
        value -> String.to_integer(value)
      end
  ],
  backpressure: [
    enabled: System.get_env("SCR_DISTRIBUTED_BACKPRESSURE_ENABLED", "true") == "true",
    cluster_saturation_threshold:
      String.to_float(System.get_env("SCR_DISTRIBUTED_CLUSTER_SAT_THRESHOLD", "0.85")),
    max_node_utilization:
      String.to_float(System.get_env("SCR_DISTRIBUTED_MAX_NODE_UTILIZATION", "0.98"))
  ],
  routing: [
    enabled: System.get_env("SCR_DISTRIBUTED_ROUTING_ENABLED", "false") == "true",
    at_least_once: System.get_env("SCR_DISTRIBUTED_AT_LEAST_ONCE", "true") == "true",
    dedupe_enabled: System.get_env("SCR_DISTRIBUTED_DEDUPE_ENABLED", "true") == "true",
    dedupe_ttl_ms: String.to_integer(System.get_env("SCR_DISTRIBUTED_DEDUPE_TTL_MS", "300000")),
    max_attempts: String.to_integer(System.get_env("SCR_DISTRIBUTED_ROUTING_MAX_ATTEMPTS", "3")),
    retry_delay_ms:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_ROUTING_RETRY_DELAY_MS", "100")),
    rpc_timeout_ms:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_ROUTING_RPC_TIMEOUT_MS", "5000"))
  ],
  placement_observability: [
    enabled: System.get_env("SCR_DISTRIBUTED_PLACEMENT_OBS_ENABLED", "true") == "true",
    interval_ms:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_PLACEMENT_OBS_INTERVAL_MS", "5000")),
    history_size:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_PLACEMENT_OBS_HISTORY_SIZE", "120"))
  ],
  workload_routing: [
    enabled: System.get_env("SCR_DISTRIBUTED_WORKLOAD_ROUTING_ENABLED", "false") == "true",
    strict: System.get_env("SCR_DISTRIBUTED_WORKLOAD_ROUTING_STRICT", "false") == "true",
    classes: %{
      "cpu" =>
        System.get_env("SCR_DISTRIBUTED_WORKLOAD_CPU_REQ", "cpu")
        |> String.split(",", trim: true),
      "io" =>
        System.get_env("SCR_DISTRIBUTED_WORKLOAD_IO_REQ", "io")
        |> String.split(",", trim: true),
      "external_api" =>
        System.get_env("SCR_DISTRIBUTED_WORKLOAD_EXTERNAL_API_REQ", "external_api")
        |> String.split(",", trim: true)
    },
    local_capabilities:
      System.get_env("SCR_DISTRIBUTED_LOCAL_CAPABILITIES", "")
      |> String.split(",", trim: true),
    node_capabilities: %{}
  ],
  capacity_tuning: [
    enabled: System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_ENABLED", "false") == "true",
    interval_ms:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_INTERVAL_MS", "10000")),
    min_queue_size:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_MIN_QUEUE", "50")),
    max_queue_size:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_MAX_QUEUE", "500")),
    up_step: String.to_integer(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_UP_STEP", "25")),
    down_step:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_DOWN_STEP", "10")),
    high_rejection_ratio:
      String.to_float(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_HIGH_REJECT", "0.08")),
    low_rejection_ratio:
      String.to_float(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_LOW_REJECT", "0.01")),
    target_latency_ms:
      String.to_integer(
        System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_TARGET_LATENCY_MS", "1000")
      ),
    avg_service_ms:
      String.to_integer(System.get_env("SCR_DISTRIBUTED_CAPACITY_TUNING_AVG_SERVICE_MS", "50"))
  ],
  rpc_timeout_ms: String.to_integer(System.get_env("SCR_DISTRIBUTED_RPC_TIMEOUT_MS", "5000"))

config :libcluster,
  topologies: if(distributed_enabled and distributed_peer_hosts != []) do
  [
    scr_epmd: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: distributed_peer_hosts]
    ]
  ]
else
  []
end

if otel_enabled do
  config :opentelemetry,
    resource: [
      service: [
        name: System.get_env("OTEL_SERVICE_NAME", "scr-runtime"),
        namespace: System.get_env("OTEL_SERVICE_NAMESPACE", "scr")
      ]
    ]

  config :opentelemetry_exporter,
    otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"),
    otlp_protocol: :http_protobuf
end
