# Production environment configuration
import Config

# LLM configuration for production
# Override these with environment variables in production!
config :scr, :llm,
  provider: :ollama,  # Can be :openai, :anthropic in production
  base_url: System.get_env("LLM_BASE_URL") || "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || "llama2",
  timeout: 60_000,
  temperature: 0.7,
  max_retries: 3

config :logger,
  level: :info
