defmodule SCR.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.Registry
  alias SCR.Tools.RateLimiter

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    original = Application.get_env(:scr, :tool_rate_limit)
    :ok = RateLimiter.clear()

    on_exit(fn ->
      Application.put_env(:scr, :tool_rate_limit, original)
      :ok = RateLimiter.clear()
    end)

    :ok
  end

  test "execute_tool/2 stays backward compatible and returns normalized metadata" do
    assert {:ok, payload} =
             Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 3})

    assert is_map(payload)
    assert payload.data == 5
    assert payload.meta.source == :native
    assert payload.meta.tool == "calculator"
  end

  test "strict mode blocks code execution by default" do
    ctx = ExecutionContext.new(%{mode: :strict})

    assert {:error, :tool_not_allowed} =
             Registry.execute_tool("code_execution", %{"code" => "1 + 1"}, ctx)
  end

  test "tool definitions are provided by registry" do
    defs = Registry.get_tool_definitions(ExecutionContext.new(%{mode: :strict}))

    assert is_list(defs)
    assert Enum.any?(defs, fn d -> get_in(d, [:function, :name]) == "calculator" end)
  end

  test "tool execution is rate limited when configured" do
    Application.put_env(:scr, :tool_rate_limit,
      enabled: true,
      default_max_calls: 100,
      default_window_ms: 60_000,
      per_tool: %{"calculator" => %{max_calls: 1, window_ms: 60_000}}
    )

    assert {:ok, _} =
             Registry.execute_tool("calculator", %{"operation" => "add", "a" => 1, "b" => 2})

    assert {:error, :rate_limited} =
             Registry.execute_tool("calculator", %{"operation" => "add", "a" => 2, "b" => 3})
  end
end
