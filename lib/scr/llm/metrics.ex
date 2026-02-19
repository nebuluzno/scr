defmodule SCR.LLM.Metrics do
  @moduledoc """
  LLM Token Counting and Cost Tracking.
  
  Tracks token usage and calculates costs for LLM calls.
  Supports multiple providers with different pricing models.
  
  ## Pricing Models
  
  ### Ollama (Local)
  - Free (no API costs)
  - Still tracks tokens for analytics
  
  ### OpenAI (Future)
  - GPT-4: $0.03/1k input, $0.06/1k output
  - GPT-3.5 Turbo: $0.001/1k input, $0.002/1k output
  
  ### Anthropic (Future)
  - Claude 3 Opus: $0.015/1k input, $0.075/1k output
  - Claude 3 Sonnet: $0.003/1k input, $0.015/1k output
  
  ## Usage
  
      # Track a completion
      SCR.LLM.Metrics.track(\n        model: \"llama2\",\n        provider: :ollama,\n        prompt_tokens: 100,\n        completion_tokens: 50\n      )\n      
      # Get current session stats\n      SCR.LLM.Metrics.stats()
      #=> %{total_calls: 10, total_tokens: 1500, total_cost: 0.0, ...}\n      
      # Reset metrics\n      SCR.LLM.Metrics.reset()
  """

  use GenServer
  require Logger

  # Pricing constants (per 1k tokens)
  @pricing %{
    # Ollama (local - free)
    "ollama" => %{input: 0.0, output: 0.0},
    
    # OpenAI models
    "gpt-4" => %{input: 0.03, output: 0.06},
    "gpt-4-32k" => %{input: 0.06, output: 0.12},
    "gpt-3.5-turbo" => %{input: 0.001, output: 0.002},
    "gpt-3.5-turbo-16k" => %{input: 0.003, output: 0.004},
    
    # Anthropic models
    "claude-3-opus" => %{input: 0.015, output: 0.075},
    "claude-3-sonnet" => %{input: 0.003, output: 0.015},
    "claude-3-haiku" => %{input: 0.00025, output: 0.00125},
    
    # Google AI
    "gemini-pro" => %{input: 0.00125, output: 0.005},
    "gemini-ultra" => %{input: 0.01, output: 0.07}
  }

  # Client API

  @doc """
  Start the metrics server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Track an LLM call with token counts.
  """
  def track(options \\ []) do
    GenServer.cast(__MODULE__, {:track, options})
  end

  @doc """
  Track a call with pre-calculated token counts from the response.
  """
  def track_response(response, options \\ []) do
    # Extract tokens from response if available
    prompt_tokens = get_in(response, [:usage, :prompt_tokens]) || 
                     get_in(response, [:raw, :usage, :prompt_tokens]) || 0
    completion_tokens = get_in(response, [:usage, :completion_tokens]) ||
                        get_in(response, [:raw, :usage, :completion_tokens]) || 0
    
    Keyword.merge(options, [
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens
    ])
  end

  @doc """
  Get current metrics statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Get statistics for a specific model.
  """
  def model_stats(model) do
    GenServer.call(__MODULE__, {:model_stats, model})
  end

  @doc """
  Reset all metrics.
  """
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  @doc """
  Calculate the cost for a given model and token counts.
  """
  def calculate_cost(model, prompt_tokens, completion_tokens) do
    pricing = Map.get(@pricing, String.downcase(model), %{input: 0.0, output: 0.0})
    
    input_cost = (prompt_tokens / 1000) * pricing.input
    output_cost = (completion_tokens / 1000) * pricing.output
    
    input_cost + output_cost
  end

  @doc """
  Estimate tokens for a string (rough approximation).
  """
  def estimate_tokens(text) when is_binary(text) do
    # Rough estimate: ~4 characters per token on average
    ceil(String.length(text) / 4)
  end

  @doc """
  List supported models and their pricing.
  """
  def supported_pricing do
    @pricing
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    state = %{
      total_calls: 0,
      total_prompt_tokens: 0,
      total_completion_tokens: 0,
      total_cost: 0.0,
      by_model: %{},
      start_time: :erlang.system_time(:second)
    }

    Logger.info("[LLM Metrics] Started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:track, options}, state) do
    model = Keyword.get(options, :model, "unknown")
    provider = Keyword.get(options, :provider, :unknown)
    prompt_tokens = Keyword.get(options, :prompt_tokens, 0)
    completion_tokens = Keyword.get(options, :completion_tokens, 0)
    
    # Calculate cost
    cost = calculate_cost(model, prompt_tokens, completion_tokens)
    
    # Update model-specific stats
    model_key = "#{provider}:#{model}"
    model_stats = Map.get(state.by_model, model_key, %{
      calls: 0,
      prompt_tokens: 0,
      completion_tokens: 0,
      cost: 0.0
    })
    
    new_model_stats = %{
      model_stats |
      calls: model_stats.calls + 1,
      prompt_tokens: model_stats.prompt_tokens + prompt_tokens,
      completion_tokens: model_stats.completion_tokens + completion_tokens,
      cost: model_stats.cost + cost
    }
    
    new_state = %{state |
      total_calls: state.total_calls + 1,
      total_prompt_tokens: state.total_prompt_tokens + prompt_tokens,
      total_completion_tokens: state.total_completion_tokens + completion_tokens,
      total_cost: state.total_cost + cost,
      by_model: Map.put(state.by_model, model_key, new_model_stats)
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset, _state) do
    state = %{
      total_calls: 0,
      total_prompt_tokens: 0,
      total_completion_tokens: 0,
      total_cost: 0.0,
      by_model: %{},
      start_time: :erlang.system_time(:second)
    }
    
    Logger.info("[LLM Metrics] Reset")
    {:noreply, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_tokens = state.total_prompt_tokens + state.total_completion_tokens
    
    stats = %{
      total_calls: state.total_calls,
      total_prompt_tokens: state.total_prompt_tokens,
      total_completion_tokens: state.total_completion_tokens,
      total_tokens: total_tokens,
      total_cost: state.total_cost,
      avg_tokens_per_call: if(state.total_calls > 0, do: div(total_tokens, state.total_calls), else: 0),
      avg_cost_per_call: if(state.total_calls > 0, do: state.total_cost / state.total_calls, else: 0.0),
      by_model: state.by_model,
      uptime_seconds: :erlang.system_time(:second) - state.start_time
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:model_stats, model}, _from, state) do
    stats = Map.get(state.by_model, model, %{calls: 0, prompt_tokens: 0, completion_tokens: 0, cost: 0.0})
    {:reply, stats, state}
  end
end
