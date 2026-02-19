# Test environment configuration
import Config

# Use mock LLM in tests to avoid external dependencies
config :scr, :llm,
  provider: :mock,
  timeout: 5_000

config :logger,
  level: :warn
