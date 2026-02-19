# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.

import Config

# Default LLM configuration (Ollama for local development)
# To use OpenAI, change provider to :openai and add your API key
config :scr, :llm,
  provider: :ollama,
  base_url: System.get_env("LLM_BASE_URL") || "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || "llama2",
  timeout: 60_000

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
