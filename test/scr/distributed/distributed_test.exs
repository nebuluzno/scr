defmodule SCR.DistributedTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "cluster nodes include local node" do
    assert Node.self() in SCR.Distributed.list_cluster_nodes()
  end

  test "list_agents_on/1 returns local agents on current node" do
    case SCR.Distributed.list_agents_on(Node.self()) do
      {:ok, agents} ->
        assert is_list(agents)

      {:error, {:rpc_failed, {:noproc, _}}} ->
        assert true
    end
  end

  test "start_agent_on/6 and stop_agent_on/3 work on current node" do
    agent_id = "distributed_worker_#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             SCR.Distributed.start_agent_on(
               Node.self(),
               agent_id,
               :worker,
               SCR.Agents.WorkerAgent,
               %{agent_id: agent_id}
             )

    assert {:ok, status} = SCR.Distributed.get_agent_status_on(Node.self(), agent_id)
    assert status.agent_id == agent_id

    assert :ok = SCR.Distributed.stop_agent_on(Node.self(), agent_id)
  end

  test "list_cluster_agents/1 returns per-node data" do
    assert {:ok, agents_by_node} = SCR.Distributed.list_cluster_agents(1_000)
    assert is_map(agents_by_node)
    assert Map.has_key?(agents_by_node, Node.self())
  end

  test "remote RPC errors are normalized" do
    assert {:error, {:rpc_failed, :nodedown}} =
             SCR.Distributed.list_agents_on(:"missing@127.0.0.1", 100)
  end

  test "pick_start_node excludes quarantined nodes" do
    if Process.whereis(SCR.Distributed.NodeWatchdog) do
      SCR.Distributed.NodeWatchdog.quarantine(Node.self(), 500)
      Process.sleep(10)

      assert {:error, :no_healthy_nodes} = SCR.Distributed.pick_start_node([Node.self()])

      assert {:error, :no_healthy_nodes} =
               SCR.Distributed.start_agent("x", :worker, SCR.Agents.WorkerAgent, %{})

      SCR.Distributed.NodeWatchdog.note_node_up(Node.self())
    end
  end

  test "placement_report returns scored node entries" do
    assert {:ok, report} = SCR.Distributed.placement_report([Node.self()], 1_000)
    assert is_list(report)
    assert length(report) == 1
    entry = hd(report)
    assert entry.node == Node.self()
    assert is_number(entry.score)
    assert Map.has_key?(entry, :queue_size)
    assert Map.has_key?(entry, :agent_count)
    assert Map.has_key?(entry, :unhealthy_count)
  end

  test "handoff_agent/3 rejects same-node handoff" do
    agent_id = "distributed_handoff_worker_#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             SCR.Distributed.start_agent_on(
               Node.self(),
               agent_id,
               :worker,
               SCR.Agents.WorkerAgent,
               %{agent_id: agent_id}
             )

    assert {:error, :same_node} = SCR.Distributed.handoff_agent(agent_id, Node.self(), 1_000)
    assert :ok = SCR.Distributed.stop_agent_on(Node.self(), agent_id)
  end

  test "remote health checks work for local node and missing agent" do
    agent_id = "distributed_health_worker_#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             SCR.Distributed.start_agent_on(
               Node.self(),
               agent_id,
               :worker,
               SCR.Agents.WorkerAgent,
               %{agent_id: agent_id}
             )

    assert :ok = SCR.Distributed.check_agent_health_on(Node.self(), agent_id)
    assert {:error, :not_found} = SCR.Distributed.check_agent_health_on(Node.self(), "missing")

    assert {:ok, summary} = SCR.Distributed.check_cluster_health(1_000)
    assert is_map(summary)
    assert Map.has_key?(summary, Node.self())
    assert is_boolean(summary[Node.self()].ok)

    assert :ok = SCR.Distributed.stop_agent_on(Node.self(), agent_id)
  end
end
