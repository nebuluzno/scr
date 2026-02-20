defmodule SCR.LLM.Cache do
  @moduledoc """
  LLM Response Cache using ETS.

  Caches LLM responses to improve performance and reduce API calls.
  Uses content hashing for cache keys to ensure cache hits for identical prompts.

  ## Usage

      # Enable caching globally
      SCR.LLM.Cache.enable()
      
      # Make an LLM call (will use cache if available)
      {:ok, response} = SCR.LLM.Client.complete("Hello world")
      
      # Check cache stats
      SCR.LLM.Cache.stats()
      #=> %{hits: 5, misses: 10, size: 3}
      
      # Clear cache
      SCR.LLM.Cache.clear()
      
      # Disable caching
      SCR.LLM.Cache.disable()
  """

  use GenServer
  require Logger

  # Cache configuration
  @cache_table :scr_llm_cache
  # 1 hour in milliseconds
  @default_ttl 3600 * 1000
  @max_entries 1000

  # Client API

  @doc """
  Start the cache server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enable the cache.
  """
  def enable do
    GenServer.cast(__MODULE__, :enable)
  end

  @doc """
  Disable the cache.
  """
  def disable do
    GenServer.cast(__MODULE__, :disable)
  end

  @doc """
  Check if caching is enabled.
  """
  def enabled? do
    GenServer.call(__MODULE__, :enabled?)
  end

  @doc """
  Get a cached response for the given prompt and options.
  Returns nil if not found or cache is disabled.
  """
  def get(prompt, options \\ []) do
    if enabled?() do
      key = cache_key(prompt, options)

      case :ets.lookup(@cache_table, key) do
        [{^key, value, timestamp}] ->
          # Check if entry has expired
          ttl = Keyword.get(options, :cache_ttl, @default_ttl)
          age = :erlang.system_time(:millisecond) - timestamp

          if age < ttl do
            Logger.debug("[LLM Cache] Cache hit for key: #{String.slice(key, 0, 20)}...")
            GenServer.cast(__MODULE__, :increment_hits)
            {:hit, value}
          else
            Logger.debug("[LLM Cache] Cache expired for key: #{String.slice(key, 0, 20)}...")
            :ets.delete(@cache_table, key)
            {:miss, :expired}
          end

        [] ->
          {:miss, :not_found}
      end
    else
      {:miss, :disabled}
    end
  end

  @doc """
  Store a response in the cache.
  """
  def put(prompt, options \\ [], response) do
    if enabled?() do
      key = cache_key(prompt, options)
      timestamp = :erlang.system_time(:millisecond)

      # Check if we need to evict old entries
      :ets.insert(@cache_table, {key, response, timestamp})

      # Cleanup if table is too large
      if :ets.info(@cache_table, :size) > @max_entries do
        GenServer.cast(__MODULE__, :cleanup)
      end

      Logger.debug("[LLM Cache] Cached response for key: #{String.slice(key, 0, 20)}...")
      :ok
    else
      :disabled
    end
  end

  @doc """
  Clear all cached entries.
  """
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @doc """
  Get cache statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Generate a cache key from prompt and options.
  """
  def cache_key(prompt, options) do
    # Include relevant options in the key
    relevant_opts = [
      Keyword.get(options, :model, "default"),
      Keyword.get(options, :temperature, 0.7),
      Keyword.get(options, :max_tokens, 2048)
    ]

    content = "#{prompt}|#{inspect(relevant_opts)}"
    :crypto.hash(:sha256, content) |> Base.encode16()
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    # Create ETS table
    :ets.new(@cache_table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    state = %{
      enabled: Keyword.get(opts, :enabled, true),
      hits: 0,
      misses: 0
    }

    Logger.info("[LLM Cache] Started with max entries: #{@max_entries}")
    {:ok, state}
  end

  @impl true
  def handle_cast(:enable, state) do
    Logger.info("[LLM Cache] Enabled")
    {:noreply, %{state | enabled: true}}
  end

  @impl true
  def handle_cast(:disable, state) do
    Logger.info("[LLM Cache] Disabled")
    {:noreply, %{state | enabled: false}}
  end

  @impl true
  def handle_cast(:increment_hits, state) do
    {:noreply, %{state | hits: state.hits + 1}}
  end

  @impl true
  def handle_cast(:increment_misses, state) do
    {:noreply, %{state | misses: state.misses + 1}}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@cache_table)
    Logger.info("[LLM Cache] Cleared")
    {:noreply, %{state | hits: 0, misses: 0}}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    # Delete oldest 10% of entries
    entries = :ets.tab2list(@cache_table)
    count = length(entries)
    to_delete = div(count, 10)

    if to_delete > 0 do
      sorted = Enum.sort_by(entries, fn {_, _, ts} -> ts end)
      to_remove = Enum.take(sorted, to_delete)

      Enum.each(to_remove, fn {key, _, _} ->
        :ets.delete(@cache_table, key)
      end)

      Logger.info("[LLM Cache] Cleaned up #{to_delete} old entries")
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      hits: state.hits,
      misses: state.misses,
      size: :ets.info(@cache_table, :size),
      max_entries: @max_entries
    }

    {:reply, stats, state}
  end
end
