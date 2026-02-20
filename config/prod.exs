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

# LLM configuration for production
# Override these with environment variables in production!
config :scr, :llm,
  # Can be :openai, :anthropic in production
  provider: :ollama,
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
  dets_path: System.get_env("SCR_TASK_QUEUE_DETS_PATH", "tmp/task_queue.dets")

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
