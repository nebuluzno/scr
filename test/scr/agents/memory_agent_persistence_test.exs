defmodule SCR.Agents.MemoryAgentPersistenceTest do
  use ExUnit.Case, async: false

  alias SCR.Agents.MemoryAgent
  alias SCR.Message

  setup do
    original = Application.get_env(:scr, :memory_storage)
    unique = System.unique_integer([:positive])
    path = Path.join(System.tmp_dir!(), "scr_memory_test_#{unique}")
    File.rm_rf(path)
    File.mkdir_p!(path)

    Application.put_env(:scr, :memory_storage, backend: :dets, path: path)

    on_exit(fn ->
      Application.put_env(:scr, :memory_storage, original)
      File.rm_rf(path)
    end)

    :ok
  end

  test "restores persisted tasks from dets on restart" do
    agent_id = "memory_persist_test_#{System.unique_integer([:positive])}"
    task_id = "task_#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

    msg =
      Message.task("test_sender", agent_id, %{
        task_id: task_id,
        description: "persist me"
      })

    SCR.Agent.send_message(agent_id, msg)

    assert_eventually(fn ->
      MemoryAgent.get_task(task_id) == {:ok, %{task_id: task_id, description: "persist me"}}
    end)

    :ok = SCR.Agent.stop(agent_id)

    assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

    assert {:ok, %{task_id: ^task_id, description: "persist me"}} = MemoryAgent.get_task(task_id)

    :ok = SCR.Agent.stop(agent_id)
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("Condition did not become true in time")
end
