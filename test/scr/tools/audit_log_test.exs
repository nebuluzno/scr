defmodule SCR.Tools.AuditLogTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.AuditLog

  setup do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "records and returns recent decision entries" do
    AuditLog.record(%{
      decision: :allowed,
      reason: :authorized,
      tool: "calculator",
      source: :native
    })

    AuditLog.record(%{
      decision: :denied,
      reason: :tool_not_allowed,
      tool: "code_execution",
      source: :native
    })

    recent = AuditLog.recent(2)
    assert length(recent) == 2
    assert Enum.any?(recent, &(&1.tool == "calculator"))
    assert Enum.any?(recent, &(&1.reason == :tool_not_allowed))
  end
end
