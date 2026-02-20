defmodule SCR.AgentContextTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    :ok = SCR.AgentContext.clear()
    :ok
  end

  test "upsert, add_finding and get context by task id" do
    task_id = "ctx-1"

    assert :ok =
             SCR.AgentContext.upsert(task_id, %{
               description: "test task",
               status: :queued
             })

    assert :ok = SCR.AgentContext.add_finding(task_id, %{agent_id: "worker_1", summary: "done"})
    assert :ok = SCR.AgentContext.set_status(task_id, :completed)

    assert {:ok, context} = SCR.AgentContext.get(task_id)
    assert context.task_id == task_id
    assert context.status == :completed
    assert length(context.findings) == 1
  end
end
