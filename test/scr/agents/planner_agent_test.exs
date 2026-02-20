defmodule SCR.Agents.PlannerAgentTest do
  use ExUnit.Case, async: false

  alias SCR.Agents.PlannerAgent
  alias SCR.Message
  alias SCR.TaskQueue

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    original = Application.get_env(:scr, :task_queue, [])
    original_distributed = Application.get_env(:scr, :distributed, [])
    server = :"planner_queue_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({TaskQueue, name: server, max_size: 1})
    Application.put_env(:scr, :task_queue, Keyword.put(original, :server, server))

    on_exit(fn ->
      Application.put_env(:scr, :task_queue, original)
      Application.put_env(:scr, :distributed, original_distributed)
    end)

    %{server: server, original_distributed: original_distributed}
  end

  test "normalize_agent_type uses allowlist and defaults unknown to worker" do
    assert PlannerAgent.normalize_agent_type("researcher") == :researcher
    assert PlannerAgent.normalize_agent_type("WRITER") == :writer
    assert PlannerAgent.normalize_agent_type("totally_unknown") == :worker
    assert PlannerAgent.normalize_agent_type(:validator) == :validator
    assert PlannerAgent.normalize_agent_type(:unknown_atom) == :worker
  end

  test "task messages are enqueued and respect queue backpressure", %{server: server} do
    {:ok, internal_state} =
      PlannerAgent.init(%{agent_id: "planner_test"})

    busy_state = %{internal_state | status: :planning, current_task: %{task_id: "running"}}

    first_msg = Message.task("web", "planner_test", %{task_id: "t1", description: "one"})
    second_msg = Message.task("web", "planner_test", %{task_id: "t2", description: "two"})

    assert {:noreply, _} =
             PlannerAgent.handle_message(first_msg, %{
               agent_id: "planner_test",
               agent_state: busy_state
             })

    assert {:noreply, _} =
             PlannerAgent.handle_message(second_msg, %{
               agent_id: "planner_test",
               agent_state: busy_state
             })

    stats = TaskQueue.stats(server)
    assert stats.size == 1
    assert stats.rejected == 1
  end

  test "task messages are throttled when cluster backpressure is active", %{
    server: server,
    original_distributed: original_distributed
  } do
    Application.put_env(
      :scr,
      :distributed,
      Keyword.merge(original_distributed,
        enabled: true,
        backpressure: [
          enabled: true,
          cluster_saturation_threshold: 0.0,
          max_node_utilization: 1.0
        ]
      )
    )

    {:ok, internal_state} = PlannerAgent.init(%{agent_id: "planner_test"})
    msg = Message.task("web", "planner_test", %{task_id: "bp1", description: "throttle me"})

    assert {:noreply, _} =
             PlannerAgent.handle_message(msg, %{
               agent_id: "planner_test",
               agent_state: internal_state
             })

    stats = TaskQueue.stats(server)
    assert stats.size == 0
    assert stats.rejected == 0
  end
end
