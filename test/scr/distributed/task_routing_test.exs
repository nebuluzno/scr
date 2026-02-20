defmodule SCR.Distributed.TaskRoutingTest do
  use ExUnit.Case, async: false

  alias SCR.Message

  defmodule TrackingAgent do
    @behaviour SCR.Agent

    def init(init_arg) do
      {:ok, %{test_pid: Map.fetch!(init_arg, :test_pid)}}
    end

    def handle_message(message, %{agent_state: state}) do
      send(state.test_pid, {:tracked_message, message})
      {:noreply, state}
    end

    def handle_heartbeat(state), do: {:noreply, state}
    def terminate(_reason, _state), do: :ok
    def handle_health_check(_state), do: %{healthy: true}
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    original_distributed = Application.get_env(:scr, :distributed, [])

    Application.put_env(
      :scr,
      :distributed,
      Keyword.merge(original_distributed,
        enabled: true,
        routing: [
          enabled: true,
          at_least_once: true,
          dedupe_enabled: true,
          dedupe_ttl_ms: 60_000,
          max_attempts: 2,
          retry_delay_ms: 10,
          rpc_timeout_ms: 500
        ]
      )
    )

    if :ets.whereis(:scr_routing_dedupe) != :undefined do
      :ets.delete_all_objects(:scr_routing_dedupe)
    end

    on_exit(fn ->
      Application.put_env(:scr, :distributed, original_distributed)
    end)

    :ok
  end

  test "route_inbound returns agent_not_found for unknown agent" do
    assert {:error, :agent_not_found} =
             SCR.Supervisor.route_inbound(
               "missing_agent",
               Message.task("a", "b", %{task_id: "t"})
             )
  end

  test "dedupe key prevents duplicate task handling on repeated inbound delivery" do
    agent_id = "routing_test_agent_#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             SCR.Supervisor.start_agent(agent_id, :worker, TrackingAgent, %{test_pid: self()})

    first = Message.task("sender", agent_id, %{task_id: "task_1", dedupe_key: "dedupe_1"})
    second = Message.task("sender", agent_id, %{task_id: "task_1", dedupe_key: "dedupe_1"})

    assert :ok = SCR.Supervisor.route_inbound(agent_id, first)
    assert :ok = SCR.Supervisor.route_inbound(agent_id, second)

    assert_receive {:tracked_message, _msg}, 500
    refute_receive {:tracked_message, _msg}, 200

    assert :ok = SCR.Supervisor.stop_agent(agent_id)
  end
end
