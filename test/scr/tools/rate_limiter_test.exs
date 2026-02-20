defmodule SCR.Tools.RateLimiterTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.RateLimiter

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    :ok = RateLimiter.clear()
    :ok
  end

  test "stats reflects limiter entries after checks" do
    assert :ok = RateLimiter.check_rate("calculator", 10, 60_000)
    assert :ok = RateLimiter.check_rate("calculator", 10, 60_000)

    stats = RateLimiter.stats()
    assert is_map(stats)
    assert stats.entries >= 1
    assert Map.has_key?(stats, :cleaned_entries)
  end
end
