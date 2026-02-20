defmodule SCR.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.Registry

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
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
end
