defmodule SCR.Agents.MemoryAgentPostgresTest do
  use ExUnit.Case, async: false

  alias SCR.Agents.MemoryAgent
  alias SCR.Message

  setup do
    original = Application.get_env(:scr, :memory_storage)

    on_exit(fn ->
      Application.put_env(:scr, :memory_storage, original)
    end)

    :ok
  end

  test "falls back to ets when postgres backend is selected without config" do
    Application.put_env(:scr, :memory_storage, backend: :postgres, postgres: [])

    agent_id = "memory_pg_fallback_#{System.unique_integer([:positive])}"
    task_id = "task_pg_fallback_#{System.unique_integer([:positive])}"

    assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

    msg =
      Message.task("test_sender", agent_id, %{
        task_id: task_id,
        description: "fallback to ets"
      })

    SCR.Agent.send_message(agent_id, msg)

    assert_eventually(fn ->
      MemoryAgent.get_task(task_id) == {:ok, %{task_id: task_id, description: "fallback to ets"}}
    end)

    assert :ok = SCR.Agent.stop(agent_id)
  end

  test "restores persisted tasks from postgres when SCR_TEST_POSTGRES_URL is set" do
    url = System.get_env("SCR_TEST_POSTGRES_URL")

    if is_nil(url) or url == "" do
      assert true
    else
      Application.put_env(:scr, :memory_storage, backend: :postgres, postgres: [url: url])

      agent_id = "memory_pg_test_#{System.unique_integer([:positive])}"
      task_id = "task_pg_#{System.unique_integer([:positive])}"

      assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

      msg =
        Message.task("test_sender", agent_id, %{
          task_id: task_id,
          description: "persist me postgres"
        })

      SCR.Agent.send_message(agent_id, msg)

      assert_eventually(fn ->
        MemoryAgent.get_task(task_id) ==
          {:ok, %{task_id: task_id, description: "persist me postgres"}}
      end)

      :ok = SCR.Agent.stop(agent_id)

      assert {:ok, _pid} = MemoryAgent.start_link(agent_id, %{agent_id: agent_id})

      assert {:ok, %{task_id: ^task_id, description: "persist me postgres"}} =
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
