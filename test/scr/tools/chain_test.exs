defmodule SCR.Tools.ChainTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.Chain
  alias SCR.Tools.ExecutionContext

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "executes chained tool calls using previous output" do
    chain = [
      %{tool: "calculator", params: %{"operation" => "add", "a" => 2, "b" => 3}},
      %{tool: "calculator", params: %{"operation" => "multiply", "a" => "__input__", "b" => 10}}
    ]

    ctx = ExecutionContext.new(%{mode: :strict, trace_id: "chain_trace_1", task_id: "t_chain"})

    assert {:ok, result} = Chain.execute(chain, nil, ctx)
    assert result.output == 50
    assert length(result.steps) == 2
    assert Enum.at(result.steps, 0).tool == "calculator"
  end

  test "returns step-indexed error when a step fails" do
    chain = [
      %{tool: "calculator", params: %{"operation" => "add", "a" => 1, "b" => 1}},
      %{tool: "missing_tool", params: %{}}
    ]

    assert {:error, %{step: 2}} = Chain.execute(chain, nil, ExecutionContext.new())
  end
end
