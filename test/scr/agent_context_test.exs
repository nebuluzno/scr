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
    original_cfg = Application.get_env(:scr, :agent_context, [])

    on_exit(fn ->
      Application.put_env(:scr, :agent_context, original_cfg)
      SCR.ConfigCache.refresh(:agent_context)
    end)

    Application.put_env(:scr, :agent_context, Keyword.merge(original_cfg, retention_ms: 1))
    SCR.ConfigCache.refresh(:agent_context)

    assert :ok =
             SCR.AgentContext.upsert("ctx-stale", %{
               status: :completed,
               findings: []
             })

    Process.sleep(5)

    assert {:ok, deleted} = SCR.AgentContext.run_cleanup()
    assert deleted >= 0

    stats = SCR.AgentContext.stats()
    assert is_map(stats)
    assert Map.has_key?(stats, :entries)
    assert Map.has_key?(stats, :cleaned_entries)
  end
end
