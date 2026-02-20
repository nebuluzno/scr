defmodule SCR.HealthCheckTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "check_health returns not_found for unknown agent" do
    assert {:error, :not_found} = SCR.HealthCheck.check_health("missing_agent")
  end

  test "deep probe returns map and check_health passes for running worker" do
    agent_id = "health_probe_worker_1"

    assert {:ok, _} =
             SCR.Supervisor.start_agent(agent_id, :worker, SCR.Agents.WorkerAgent, %{
               agent_id: agent_id
             })

    probe = SCR.Agent.health_check(agent_id)
    assert is_map(probe)
    assert probe.agent_id == agent_id
    assert Map.has_key?(probe, :completed_count)
    assert :ok = SCR.HealthCheck.check_health(agent_id)

    _ = SCR.Supervisor.stop_agent(agent_id)
  end

  test "heal_agent returns unknown spec for non-registered agent" do
    assert {:error, :unknown_agent_spec} = SCR.HealthCheck.heal_agent("missing_agent")
  end
end
