# Production environment configuration
import Config

log_format = System.get_env("SCR_LOG_FORMAT", "text")
otel_enabled = System.get_env("SCR_OTEL_ENABLED", "false") == "true"

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

config :logger,
  level: :info

if log_format == "json" do
  config :logger, :console,
    format: {SCR.Logging.JSONFormatter, :format},
    metadata: :all
end

config :scr, SCR.Observability.OTelBridge, enabled: otel_enabled

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
