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

  test "execution metadata includes propagated context identifiers" do
    ctx =
      ExecutionContext.new(%{
        mode: :strict,
        agent_id: "worker_ctx",
        task_id: "task_main_1",
        parent_task_id: "parent_1",
        subtask_id: "subtask_1",
        trace_id: "trace_ctx_1"
      })

    assert {:ok, payload} =
             Registry.execute_tool("calculator", %{"operation" => "add", "a" => 1, "b" => 1}, ctx)

    assert payload.meta.trace_id == "trace_ctx_1"
    assert payload.meta.task_id == "task_main_1"
    assert payload.meta.parent_task_id == "parent_1"
    assert payload.meta.subtask_id == "subtask_1"
    assert payload.meta.agent_id == "worker_ctx"
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

  test "emits telemetry for successful and failed tool executions" do
    handler_id = "tools-telemetry-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:scr, :tools, :execute],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, _} =
             Registry.execute_tool("calculator", %{"operation" => "add", "a" => 10, "b" => 5})

    assert {:error, :not_found} = Registry.execute_tool("missing_tool", %{})

    assert_receive {:telemetry_event, [:scr, :tools, :execute],
                    %{count: 1, duration_ms: duration_ok},
                    %{tool: "calculator", source: :native, result: :ok}}

    assert duration_ok >= 0

    assert_receive {:telemetry_event, [:scr, :tools, :execute],
                    %{count: 1, duration_ms: duration_error},
                    %{tool: "missing_tool", result: :not_found}}

    assert duration_error >= 0
  end

  test "records denied decisions in audit log with reason code" do
    ctx = ExecutionContext.new(%{mode: :strict})

    assert {:error, :tool_not_allowed} =
             Registry.execute_tool("code_execution", %{"code" => "1 + 1"}, ctx)

    decisions = SCR.Tools.AuditLog.recent(10)

    assert Enum.any?(decisions, fn d ->
             d.tool == "code_execution" and d.decision == :denied and
               d.reason == :tool_not_allowed
           end)
  end
end
