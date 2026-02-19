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
