defmodule SCR.LLM.Client do
  @moduledoc """
  Unified LLM Client with provider abstraction.

  This module provides a single entry point for all LLM operations,
  automatically routing to the configured provider.

  ## Features
  - Automatic caching of responses
  - Token counting and cost tracking
  - Automatic retry on failures
  - Tool use capabilities (function calling)

  ## Configuration

  Configure the LLM provider in config.exs:

      config :scr, :llm,
        provider: :ollama,  # or :openai, :anthropic, etc.
        base_url: "http://localhost:11434",
        default_model: "llama2",
        api_key: nil,  # For cloud providers

  ## Usage

      # Simple completion
      {:ok, result} = SCR.LLM.Client.complete("Explain Elixir in one sentence")
      
      # Chat completion
      {:ok, result} = SCR.LLM.Client.chat([
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "What is pattern matching?"}
      ])
      
      # Chat with tools
      {:ok, result} = SCR.LLM.Client.chat_with_tools([
        %{role: "user", content: "What is 5 + 7?"}
      ], [SCR.Tools.Calculator])
      
      # Check metrics
      SCR.LLM.Metrics.stats()
      
      # Check cache
      SCR.LLM.Cache.stats()
  """

  alias SCR.LLM.{Ollama, OpenAI, Anthropic, Mock, Cache, Metrics}
  alias SCR.Tools.Registry
  alias SCR.Tools.ExecutionContext

  @type provider :: :ollama | :openai | :anthropic | :custom
  @type result :: {:ok, map()} | {:error, term()}

  @doc """
  Returns the current provider configuration.
  """
  def config do
    %{
      provider: provider(),
      adapter: adapter(),
      cache: Cache.stats(),
      metrics: Metrics.stats()
    }
  end

  @doc """
  Returns the current provider atom.
  """
  def provider do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:provider, :ollama)
  end

  @doc """
  Generate a completion from a prompt.

  Uses caching and tracks metrics automatically.
  """
  def complete(prompt, options \\ []) do
    # Check cache first
    case Cache.get(prompt, options) do
      {:hit, cached_response} ->
        {:ok, Map.put(cached_response, :cached, true)}

      {:miss, _} ->
        # Make the actual LLM call
        result = adapter().complete(prompt, options)

        # Track metrics
        track_metrics(result, options)

        # Cache successful responses
        case result do
          {:ok, response} ->
            Cache.put(prompt, options, response)
            result

          _ ->
            result
        end
    end
  end

  @doc """
  Generate a chat completion from messages.

  Uses caching and tracks metrics automatically.
  """
  def chat(messages, options \\ []) do
    # Create a cache key from messages
    prompt = Jason.encode!(messages)

    # Check cache first
    case Cache.get(prompt, options) do
      {:hit, cached_response} ->
        {:ok, Map.put(cached_response, :cached, true)}

      {:miss, _} ->
        # Make the actual LLM call
        result = adapter().chat(messages, options)

        # Track metrics
        track_metrics(result, options)

        # Cache successful responses
        case result do
          {:ok, response} ->
            Cache.put(prompt, options, response)
            result

          _ ->
            result
        end
    end
  end

  @doc """
  Generate embeddings for text.
  """
  def embed(text, options \\ []) do
    adapter().embed(text, options)
  end

  @doc """
  Stream a completion, calling the callback for each chunk.

  Note: Streaming responses are not cached.
  """
  def stream(prompt, callback, options \\ []) do
    if function_exported?(adapter(), :stream, 3) do
      adapter().stream(prompt, callback, options)
    else
      # Fall back to non-streaming if adapter doesn't support it
      complete(prompt, options)
    end
  end

  @doc """
  Stream a chat completion.

  Note: Streaming responses are not cached.
  """
  def chat_stream(messages, callback, options \\ []) do
    if function_exported?(adapter(), :chat_stream, 3) do
      adapter().chat_stream(messages, callback, options)
    else
      case chat(messages, options) do
        {:ok, %{content: content} = response} ->
          callback.(content)
          {:ok, Map.put(response, :streamed, true)}

        error ->
          error
      end
    end
  end

  @doc """
  Check if the LLM service is available.
  """
  def ping, do: adapter().ping()

  @doc """
  List available models from the provider.
  """
  def list_models, do: adapter().list_models()

  @doc """
  Enable response caching.
  """
  def enable_cache, do: Cache.enable()

  @doc """
  Disable response caching.
  """
  def disable_cache, do: Cache.disable()

  @doc """
  Clear the response cache.
  """
  def clear_cache, do: Cache.clear()

  @doc """
  Get cache statistics.
  """
  def cache_stats, do: Cache.stats()

  @doc """
  Get metrics statistics.
  """
  def metrics_stats, do: Metrics.stats()

  @doc """
  Reset metrics.
  """
  def reset_metrics, do: Metrics.reset()

  @doc """
  Execute a task with automatic retry on failure.

  ## Options
    - :retries - Number of retries (default: 3)
    - :delay - Delay between retries in ms (default: 1000)
  """
  def execute_with_retry(fun, options \\ []) do
    retries = Keyword.get(options, :retries, 3)
    delay = Keyword.get(options, :delay, 1000)

    attempt(fun, retries, delay)
  end

  # Private functions

  defp adapter do
    case provider() do
      :mock -> Mock
      :openai -> OpenAI
      :anthropic -> Anthropic
      _ -> Ollama
    end
  end

  defp track_metrics(result, options) do
    llm_cfg = Application.get_env(:scr, :llm, [])
    model = Keyword.get(options, :model, Keyword.get(llm_cfg, :default_model, "llama2"))
    provider = Keyword.get(options, :provider, provider())

    case result do
      {:ok, response} ->
        # Extract tokens from response if available
        prompt_tokens =
          get_in(response, [:usage, :prompt_tokens]) ||
            get_in(response, [:raw, :prompt_tokens]) ||
            Metrics.estimate_tokens(Keyword.get(options, :prompt, ""))

        completion_tokens =
          get_in(response, [:usage, :completion_tokens]) ||
            get_in(response, [:raw, :completion_tokens]) ||
            Metrics.estimate_tokens(response[:content] || "")

        Metrics.track(
          model: model,
          provider: provider,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens
        )

      {:error, _} ->
        # Track failed call
        Metrics.track(
          model: model,
          provider: provider,
          prompt_tokens: 0,
          completion_tokens: 0
        )
    end
  end

  defp attempt(_fun, 0, _delay) do
    {:error, %{type: :max_retries_exceeded, message: "LLM request failed after all retries"}}
  end

  defp attempt(fun, retries, delay) do
    case fun.() do
      {:ok, _} = result ->
        result

      {:error, %{type: type}} when type in [:connection_error, :timeout] ->
        # Retry on connection errors
        Process.sleep(delay)
        attempt(fun, retries - 1, delay * 2)

      {:error, _} = error ->
        error
    end
  end

  # Helper to format messages for different providers
  @doc """
  Format messages for a specific provider.
  """
  def format_messages(messages, :ollama) do
    Enum.map(messages, fn
      %{role: role, content: content} -> %{role: role, content: content}
      other -> other
    end)
  end

  def format_messages(messages, :openai) do
    Enum.map(messages, fn
      %{role: role, content: content} -> %{role: role, content: content}
      other -> other
    end)
  end

  def format_messages(messages, _provider), do: messages

  @doc """
  Generate a chat completion with tool support.

  This sends tool definitions to the LLM and handles tool calls.
  The tools parameter accepts a list of tool modules.

  ## Options
    - :max_tool_calls - Maximum tool calls to execute (default: 5)
  """
  def chat_with_tools(messages, tools \\ [], options \\ []) do
    max_calls = Keyword.get(options, :max_tool_calls, 5)

    execution_context =
      options
      |> Keyword.get(:execution_context, ExecutionContext.new())
      |> normalize_execution_context()

    # Get tool definitions
    tool_definitions = Enum.map(tools, &to_tool_definition/1)

    # Make initial call with tools
    result = adapter().chat_with_tools(messages, tool_definitions, options)

    case result do
      {:ok, response} ->
        # Check if there are tool calls
        tool_calls = extract_tool_calls(response)

        if tool_calls == [] or length(tool_calls) > max_calls do
          {:ok, response}
        else
          # Execute tool calls and continue conversation
          execute_tool_calls(
            messages ++ [response],
            tool_calls,
            tools,
            options,
            execution_context,
            1,
            max_calls
          )
        end

      error ->
        error
    end
  end

  @doc """
  Execute a tool call and continue the conversation.
  """
  def execute_tool_calls(messages, tool_calls, tools, options, current, max) do
    execute_tool_calls(messages, tool_calls, tools, options, ExecutionContext.new(), current, max)
  end

  def execute_tool_calls(messages, tool_calls, tools, options, execution_context, current, max) do
    # Build tool results as messages
    tool_results =
      Enum.map(tool_calls, fn call ->
        %{
          role: "tool",
          tool_call_id: call.id,
          content: execute_single_tool(call, tools, execution_context)
        }
      end)

    # Add tool results to messages
    new_messages = messages ++ tool_results

    # Make another call to get final response
    result = adapter().chat(new_messages, options)

    case result do
      {:ok, response} ->
        # Check if there are more tool calls
        more_calls = extract_tool_calls(response)

        if more_calls == [] or current >= max do
          {:ok, response}
        else
          execute_tool_calls(
            new_messages ++ [response],
            more_calls,
            tools,
            options,
            execution_context,
            current + 1,
            max
          )
        end

      error ->
        error
    end
  end

  # Make execute_single_tool public for testing
  def execute_single_tool(call, tools, execution_context \\ ExecutionContext.new()) do
    execute_single_tool_internal(call, tools, normalize_execution_context(execution_context))
  end

  defp execute_single_tool_internal(call, _tools, execution_context) do
    # Parse the arguments
    case Jason.decode(call.function.arguments) do
      {:ok, params} ->
        # Find and execute the tool
        tool_name = call.function.name

        case Registry.execute_tool(tool_name, params, execution_context) do
          {:ok, result} ->
            Jason.encode!(%{success: true, result: result})

          {:error, reason} ->
            Jason.encode!(%{success: false, error: reason})
        end

      {:error, reason} ->
        Jason.encode!(%{success: false, error: "Failed to parse arguments: #{reason}"})
    end
  end

  # Make extract_tool_calls public for testing
  def extract_tool_calls(response) do
    extract_tool_calls_private(response)
  end

  defp extract_tool_calls_private(response) do
    # First try standard tool_calls format
    tool_calls =
      get_in(response, [:message, :tool_calls]) ||
        get_in(response, [:choices, Access.at(0), :message, :tool_calls])

    if tool_calls && tool_calls != [] do
      tool_calls
    else
      # Ollama returns tool calls in content as JSON
      # Format: {"name": "tool_name", "arguments": {...}}
      content =
        get_in(response, ["message", "content"]) ||
          get_in(response, [:message, :content]) ||
          get_in(response, ["content"]) ||
          get_in(response, [:content]) || ""

      if content != "" && String.starts_with?(content, "{") do
        case Jason.decode(content) do
          {:ok, %{"name" => name, "arguments" => args}} when is_map(args) ->
            [
              %{
                id: "call_#{:rand.uniform(99999)}",
                type: "function",
                function: %{
                  name: name,
                  arguments: Jason.encode!(args)
                }
              }
            ]

          _ ->
            []
        end
      else
        []
      end
    end
  end

  defp to_tool_definition(%{type: "function"} = definition), do: definition
  defp to_tool_definition(%{"type" => "function"} = definition), do: definition
  defp to_tool_definition(tool) when is_atom(tool), do: apply(tool, :to_openai_format, [])
  defp to_tool_definition(tool), do: tool

  defp normalize_execution_context(%ExecutionContext{} = context), do: context

  defp normalize_execution_context(context) when is_map(context),
    do: ExecutionContext.new(context)

  defp normalize_execution_context(_), do: ExecutionContext.new()
end
