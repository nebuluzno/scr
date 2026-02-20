defmodule SCR.ConfigCache do
  @moduledoc """
  Persistent-term backed cache for hot-path SCR config lookups.
  """

  @app :scr
  @key_prefix :scr_config_cache
  @cached_keys [
    :tools,
    :tool_rate_limit,
    :distributed,
    :task_queue,
    :agent_context,
    :health_check,
    :llm,
    :memory_storage
  ]

  def get(key, default \\ []) do
    if Mix.env() == :test do
      Application.get_env(@app, key, default)
    else
      do_get(key, default)
    end
  end

  defp do_get(key, default) do
    cache_key = cache_key(key)

    case :persistent_term.get(cache_key, :missing) do
      :missing ->
        value = Application.get_env(@app, key, default)
        :persistent_term.put(cache_key, value)
        value

      value ->
        value
    end
  end

  def refresh(key) do
    value = Application.get_env(@app, key, [])
    :persistent_term.put(cache_key(key), value)
    value
  end

  def refresh_all do
    Enum.each(@cached_keys, &refresh/1)
    :ok
  end

  def clear do
    Enum.each(@cached_keys, fn key ->
      :persistent_term.erase(cache_key(key))
    end)

    :ok
  end

  defp cache_key(key), do: {@key_prefix, key}
end
