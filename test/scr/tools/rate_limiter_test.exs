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

  test "emits telemetry events for allowed and rejected checks" do
    handler_id = "rate-limiter-telemetry-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:scr, :tools, :rate_limit],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = RateLimiter.check_rate("calculator", 1, 60_000)
    assert {:error, :rate_limited} = RateLimiter.check_rate("calculator", 1, 60_000)

    assert_receive {:telemetry_event, [:scr, :tools, :rate_limit], %{count: 1},
                    %{tool: "calculator", result: :allowed}}

    assert_receive {:telemetry_event, [:scr, :tools, :rate_limit], %{count: 1},
                    %{tool: "calculator", result: :rejected}}
  end
end
