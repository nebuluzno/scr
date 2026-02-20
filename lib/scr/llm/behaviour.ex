defmodule SCR.LLM.Behaviour do
  @moduledoc """
  Behaviour (interface) for LLM adapters.

  This module defines the contract that all LLM providers must implement.
  Currently supported adapters:
  - SCR.LLM.Ollama (local development)

  Future adapters can be added:
  - SCR.LLM.OpenAI
  - SCR.LLM.Anthropic
  - SCR.LLM.GoogleAI
  """

  @doc """
  Generate a completion from a prompt.

  ## Parameters
    - prompt: String prompt for the LLM
    - options: Keyword list of options (model, temperature, max_tokens, etc.)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  @callback complete(prompt :: String.t(), options :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Generate a chat completion from messages.

  ## Parameters
    - messages: List of message maps with :role and :content keys
    - options: Keyword list of options (model, temperature, max_tokens, etc.)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  @callback chat(
              messages :: [%{optional(:role) => String.t(), optional(:content) => String.t()}],
              options :: keyword()
            ) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Generate embeddings for text.

  ## Parameters
    - text: String or list of strings to embed
    - options: Keyword list of options (model, etc.)

  ## Returns
    - {:ok, embeddings} on success
    - {:error, reason} on failure
  """
  @callback embed(text :: String.t() | [String.t()], options :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Check if the LLM service is available and responding.

  ## Returns
    - {:ok, model_info} if available
    - {:error, reason} if unavailable
  """
  @callback ping() :: {:ok, map()} | {:error, term()}

  @doc """
  List available models from the provider.

  ## Returns
    - {:ok, models} on success
    - {:error, reason} on failure
  """
  @callback list_models() :: {:ok, [map()]} | {:error, term()}

  @doc """
  Stream a completion, calling the callback for each chunk.

  ## Parameters
    - prompt: String prompt for the LLM
    - callback: Function to call with each chunk of the response
    - options: Keyword list of options (model, temperature, max_tokens, etc.)

  ## Returns
    - {:ok, final_response} on success
    - {:error, reason} on failure
  """
  @callback stream(prompt :: String.t(), callback :: (String.t() -> term()), options :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Generate a chat completion with tool calling support.

  ## Parameters
    - messages: List of message maps with :role and :content keys
    - tool_definitions: List of tool definitions in OpenAI format
    - options: Keyword list of options (model, temperature, max_tokens, etc.)

  ## Returns
    - {:ok, response} on success - response may contain tool_calls
    - {:error, reason} on failure
  """
  @callback chat_with_tools(
              messages :: [%{optional(:role) => String.t(), optional(:content) => String.t()}],
              tool_definitions :: [map()],
              options :: keyword()
            ) :: {:ok, map()} | {:error, term()}

  # Default options
  @default_options [
    temperature: 0.7,
    max_tokens: 2048,
    timeout: 30_000
  ]

  @doc """
  Returns default options for LLM calls.
  """
  def default_options, do: @default_options

  @doc """
  Merges user options with defaults.
  """
  def merge_options(user_options) do
    Keyword.merge(@default_options, user_options)
  end
end
