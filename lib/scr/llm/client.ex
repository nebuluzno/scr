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
  @default_failover_cooldown_ms 30_000
  @default_failover_errors [:connection_error, :timeout, :http_error, :api_error]
  @default_failover_mode :fail_closed
  @default_retry_budget [max_retries: 50, window_ms: 60_000]
  @provider_state_key :scr_llm_failover_state
  @retry_budget_state_key :scr_llm_failover_retry_budget

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
    llm_config()
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
        result = call_with_failover(:complete, [prompt, options], options)

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
        result = call_with_failover(:chat, [messages, options], options)

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
    call_with_failover(:embed, [text, options], options)
  end

  @doc """
  Stream a completion, calling the callback for each chunk.

  Note: Streaming responses are not cached.
  """
  def stream(prompt, callback, options \\ []) do
    adapter = adapter(provider(), llm_config())

    if function_exported?(adapter, :stream, 3) do
      call_with_failover(:stream, [prompt, callback, options], options)
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
    adapter = adapter(provider(), llm_config())

    if function_exported?(adapter, :chat_stream, 3) do
      call_with_failover(:chat_stream, [messages, callback, options], options)
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
  def ping, do: call_with_failover(:ping, [], [])

  @doc """
  List available models from the provider.
  """
  def list_models, do: call_with_failover(:list_models, [], [])

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
  Clears provider failover cooldown state.
  """
  def clear_failover_state do
    cfg = llm_config()

    cfg
    |> Keyword.get(:failover_providers, [])
    |> Enum.each(fn provider ->
      if is_atom(provider), do: clear_provider_cooldown(provider)
    end)

    :persistent_term.put(@provider_state_key, %{})
    :persistent_term.put(@retry_budget_state_key, %{window_started_ms: 0, spent: 0})
    :ok
  end

  @doc """
  Returns current failover policy/circuit/budget state.
  """
  def failover_state do
    cfg = llm_config()
    now_ms = System.system_time(:millisecond)
    mode = failover_mode(cfg)
    providers = candidate_providers(cfg, nil)
    provider_state = :persistent_term.get(@provider_state_key, %{})
    retry_budget = current_retry_budget(cfg)

    provider_entries =
      Enum.map(providers, fn provider ->
        state = Map.get(provider_state, provider, %{})
        circuit_open_until = Map.get(state, :circuit_open_until, 0)

        %{
          provider: provider,
          failures: Map.get(state, :failures, 0),
          successes: Map.get(state, :successes, 0),
          last_error: Map.get(state, :last_error),
          circuit_open_until: circuit_open_until,
          circuit_open: circuit_open_until > now_ms
        }
      end)

    %{
      enabled: failover_enabled?(cfg),
      mode: mode,
      providers: provider_entries,
      retry_budget: retry_budget
    }
  end

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
    adapter(provider(), llm_config())
  end

  defp adapter(provider, cfg) do
    overrides = Keyword.get(cfg, :adapter_overrides, %{})

    Map.get(overrides, provider) ||
      case provider do
        :mock -> Mock
        :openai -> OpenAI
        :anthropic -> Anthropic
        _ -> Ollama
      end
  end

  defp track_metrics(result, options) do
    llm_cfg = llm_config()
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
    result = call_with_failover(:chat_with_tools, [messages, tool_definitions, options], options)

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
    result = call_with_failover(:chat, [new_messages, options], options)

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

  defp llm_config, do: SCR.ConfigCache.get(:llm, [])

  defp call_with_failover(operation, args, options) do
    cfg = llm_config()
    pinned_provider = Keyword.get(options, :provider)
    providers = candidate_providers(cfg, pinned_provider)
    cooldown_ms = Keyword.get(cfg, :failover_cooldown_ms, @default_failover_cooldown_ms)
    allowed_errors = Keyword.get(cfg, :failover_errors, @default_failover_errors)

    run_with_providers(operation, args, providers, cooldown_ms, allowed_errors, cfg, nil)
  end

  defp run_with_providers(operation, args, [], _cooldown_ms, _allowed_errors, cfg, last_error) do
    case failover_mode(cfg) do
      :fail_open ->
        fail_open_response(
          operation,
          args,
          cfg,
          last_error || {:error, %{type: :no_provider_available}}
        )

      _ ->
        last_error || {:error, %{type: :no_provider_available}}
    end
  end

  defp run_with_providers(
         operation,
         args,
         [provider | rest],
         cooldown_ms,
         allowed_errors,
         cfg,
         _last_error
       ) do
    if provider_cooldown_active?(provider) do
      run_with_providers(
        operation,
        args,
        rest,
        cooldown_ms,
        allowed_errors,
        cfg,
        {:error, %{type: :provider_cooldown, provider: provider}}
      )
    else
      adapter = adapter(provider, cfg)

      result =
        case apply(adapter, operation, args) do
          {:ok, response} when is_map(response) ->
            {:ok, Map.put(response, :provider, provider)}

          other ->
            other
        end

      case result do
        {:ok, _} = ok ->
          mark_provider_success(provider)
          ok

        {:error, reason} = error ->
          if failover_enabled?(cfg) and failover_error?(reason, allowed_errors) and rest != [] do
            mark_provider_failed(provider, cooldown_ms, reason)

            if consume_retry_budget(cfg) do
              run_with_providers(operation, args, rest, cooldown_ms, allowed_errors, cfg, error)
            else
              budget_error =
                {:error,
                 %{
                   type: :failover_retry_budget_exhausted,
                   message: "Failover retry budget exhausted",
                   provider: provider
                 }}

              case failover_mode(cfg) do
                :fail_open -> fail_open_response(operation, args, cfg, budget_error)
                _ -> budget_error
              end
            end
          else
            case failover_mode(cfg) do
              :fail_open -> fail_open_response(operation, args, cfg, error)
              _ -> error
            end
          end
      end
    end
  end

  defp candidate_providers(cfg, pinned_provider) do
    providers =
      cond do
        not is_nil(pinned_provider) -> [pinned_provider]
        failover_enabled?(cfg) -> Keyword.get(cfg, :failover_providers, [provider()])
        true -> [provider()]
      end

    providers
    |> Enum.uniq()
    |> Enum.filter(&is_atom/1)
  end

  defp failover_enabled?(cfg), do: Keyword.get(cfg, :failover_enabled, false)
  defp failover_mode(cfg), do: Keyword.get(cfg, :failover_mode, @default_failover_mode)

  defp failover_error?(%{type: type}, allowed), do: type in allowed
  defp failover_error?(type, allowed) when is_atom(type), do: type in allowed
  defp failover_error?(_, _), do: false

  defp provider_cooldown_active?(provider) do
    until_ms =
      :persistent_term.get(@provider_state_key, %{})
      |> Map.get(provider, %{})
      |> Map.get(:circuit_open_until, 0)

    until_ms > System.system_time(:millisecond)
  end

  defp mark_provider_failed(provider, cooldown_ms, reason) do
    now_ms = System.system_time(:millisecond)
    state = :persistent_term.get(@provider_state_key, %{})
    entry = Map.get(state, provider, %{})

    next_entry =
      entry
      |> Map.put(:circuit_open_until, now_ms + cooldown_ms)
      |> Map.put(:last_error, reason)
      |> Map.update(:failures, 1, &(&1 + 1))

    :persistent_term.put(@provider_state_key, Map.put(state, provider, next_entry))
  end

  defp clear_provider_cooldown(provider) do
    state = :persistent_term.get(@provider_state_key, %{})
    entry = Map.get(state, provider, %{})
    next = Map.put(entry, :circuit_open_until, 0)
    :persistent_term.put(@provider_state_key, Map.put(state, provider, next))
  end

  defp mark_provider_success(provider) do
    state = :persistent_term.get(@provider_state_key, %{})
    entry = Map.get(state, provider, %{})

    next_entry =
      entry
      |> Map.put(:circuit_open_until, 0)
      |> Map.update(:successes, 1, &(&1 + 1))

    :persistent_term.put(@provider_state_key, Map.put(state, provider, next_entry))
  end

  defp current_retry_budget(cfg) do
    budget_cfg = Keyword.get(cfg, :failover_retry_budget, @default_retry_budget)
    now_ms = System.system_time(:millisecond)
    max_retries = Keyword.get(budget_cfg, :max_retries, 50)
    window_ms = Keyword.get(budget_cfg, :window_ms, 60_000)
    state = :persistent_term.get(@retry_budget_state_key, %{window_started_ms: 0, spent: 0})
    elapsed = now_ms - Map.get(state, :window_started_ms, 0)
    stale_window = Map.get(state, :window_started_ms, 0) == 0 or elapsed > window_ms
    effective_spent = if stale_window, do: 0, else: Map.get(state, :spent, 0)

    %{
      max_retries: max_retries,
      window_ms: window_ms,
      spent: effective_spent,
      remaining: max(max_retries - effective_spent, 0)
    }
  end

  defp consume_retry_budget(cfg) do
    budget_cfg = Keyword.get(cfg, :failover_retry_budget, @default_retry_budget)
    now_ms = System.system_time(:millisecond)
    max_retries = Keyword.get(budget_cfg, :max_retries, 50)
    window_ms = Keyword.get(budget_cfg, :window_ms, 60_000)
    state = :persistent_term.get(@retry_budget_state_key, %{window_started_ms: 0, spent: 0})

    next_state =
      if Map.get(state, :window_started_ms, 0) == 0 or
           now_ms - state.window_started_ms > window_ms do
        %{window_started_ms: now_ms, spent: 0}
      else
        state
      end

    if max_retries <= 0 do
      true
    else
      spent = Map.get(next_state, :spent, 0)

      if spent < max_retries do
        :persistent_term.put(@retry_budget_state_key, %{next_state | spent: spent + 1})
        true
      else
        false
      end
    end
  end

  defp fail_open_response(operation, args, cfg, original_error) do
    fallback_provider = Keyword.get(cfg, :failover_fail_open_provider, :mock)

    fallback_result =
      if is_atom(fallback_provider) do
        adapter = adapter(fallback_provider, cfg)

        case apply(adapter, operation, args) do
          {:ok, response} when is_map(response) ->
            {:ok,
             response
             |> Map.put(:provider, fallback_provider)
             |> Map.put(:degraded, true)
             |> Map.put(:fail_open, true)}

          _ ->
            synthetic_fail_open_response(operation, original_error)
        end
      else
        synthetic_fail_open_response(operation, original_error)
      end

    fallback_result
  rescue
    _ -> synthetic_fail_open_response(operation, original_error)
  end

  defp synthetic_fail_open_response(:embed, original_error) do
    {:ok,
     %{
       embedding: [],
       provider: :fail_open,
       degraded: true,
       fail_open: true,
       original_error: inspect(original_error)
     }}
  end

  defp synthetic_fail_open_response(:ping, _original_error) do
    {:ok, %{status: "degraded", provider: :fail_open, degraded: true, fail_open: true}}
  end

  defp synthetic_fail_open_response(:list_models, _original_error), do: {:ok, []}

  defp synthetic_fail_open_response(_operation, original_error) do
    {:ok,
     %{
       content: "LLM unavailable; fail-open fallback response.",
       provider: :fail_open,
       degraded: true,
       fail_open: true,
       original_error: inspect(original_error)
     }}
  end
end
