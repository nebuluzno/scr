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

  test "cleanup removes stale entries and updates stats" do
    :ok = SCR.AgentContext.clear()

    stale_context = %{
      task_id: "ctx-stale",
      status: :completed,
      findings: [],
      created_at: DateTime.add(DateTime.utc_now(), -7_200, :second),
      updated_at: DateTime.add(DateTime.utc_now(), -7_200, :second)
    }

    true = :ets.insert(:scr_agent_context, {"ctx-stale", stale_context})

    assert {:ok, deleted} = SCR.AgentContext.run_cleanup()
    assert deleted >= 1
    assert {:error, :not_found} = SCR.AgentContext.get("ctx-stale")

    stats = SCR.AgentContext.stats()
    assert is_map(stats)
    assert Map.has_key?(stats, :entries)
    assert Map.has_key?(stats, :cleaned_entries)
  end
end
