defmodule SCR.HealthCheckTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "check_health returns not_found for unknown agent" do
    assert {:error, :not_found} = SCR.HealthCheck.check_health("missing_agent")
  end

  test "heal_agent returns unknown spec for non-registered agent" do
    assert {:error, :unknown_agent_spec} = SCR.HealthCheck.heal_agent("missing_agent")
  end
end
