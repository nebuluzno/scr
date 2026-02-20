defmodule SCR.Agents.MemoryAgentSQLiteTest do
  use ExUnit.Case, async: false

  alias SCR.Agents.MemoryAgent
  alias SCR.Message

  setup do
    if is_nil(System.find_executable("sqlite3")) do
      {:ok, %{sqlite_available: false}}
    else
      original = Application.get_env(:scr, :memory_storage)
      unique = System.unique_integer([:positive])
      dir = Path.join(System.tmp_dir!(), "scr_memory_sqlite_test_#{unique}")
      path = Path.join(dir, "scr_memory.sqlite3")
      File.rm_rf(dir)
      File.mkdir_p!(dir)

      Application.put_env(:scr, :memory_storage, backend: :sqlite, path: path)

      on_exit(fn ->
        Application.put_env(:scr, :memory_storage, original)
        File.rm_rf(dir)
      end)

      {:ok, %{path: path, sqlite_available: true}}
    end
  end

  test "restores persisted tasks from sqlite on restart", %{sqlite_available: sqlite_available} do
    if not sqlite_available do
      assert true
    else
      agent_id = "memory_sqlite_test_#{System.unique_integer([:positive])}"
      task_id = "task_sqlite_#{System.unique_integer([:positive])}"

      assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

      msg =
        Message.task("test_sender", agent_id, %{
          task_id: task_id,
          description: "persist me sqlite"
        })

      SCR.Agent.send_message(agent_id, msg)

      assert_eventually(fn ->
        MemoryAgent.get_task(task_id) ==
          {:ok, %{task_id: task_id, description: "persist me sqlite"}}
      end)

      :ok = SCR.Agent.stop(agent_id)

      assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

      assert {:ok, %{task_id: ^task_id, description: "persist me sqlite"}} =
               MemoryAgent.get_task(task_id)

      :ok = SCR.Agent.stop(agent_id)
    end
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
