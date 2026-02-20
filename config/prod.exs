# Production environment configuration
import Config

# LLM configuration for production
# Override these with environment variables in production!
config :scr, :llm,
  # Can be :openai, :anthropic in production
  provider: :ollama,
  base_url:
    System.get_env("LLM_BASE_URL") || System.get_env("OPENAI_BASE_URL") ||
      "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || System.get_env("OPENAI_MODEL") || "llama2",
  api_key: System.get_env("OPENAI_API_KEY"),
  timeout: 60_000,
  temperature: 0.7,
  max_retries: 3

config :logger,
  level: :info
