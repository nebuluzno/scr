# Test environment configuration
import Config

# Use mock LLM in tests to avoid external dependencies
config :scr, :llm,
  provider: :mock,
  timeout: 5_000

config :scr, SCRWeb.Endpoint,
  server: false,
  secret_key_base: "test_secret_key_base_at_least_64_bytes_long_for_phoenix_security_12345678",
  live_view: [signing_salt: "test_signing_salt"]

config :logger,
  level: :warning
