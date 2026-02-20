defmodule SCR.Agents.PlannerAgentTest do
  use ExUnit.Case, async: true

  alias SCR.Agents.PlannerAgent

  test "normalize_agent_type uses allowlist and defaults unknown to worker" do
    assert PlannerAgent.normalize_agent_type("researcher") == :researcher
    assert PlannerAgent.normalize_agent_type("WRITER") == :writer
    assert PlannerAgent.normalize_agent_type("totally_unknown") == :worker
    assert PlannerAgent.normalize_agent_type(:validator) == :validator
    assert PlannerAgent.normalize_agent_type(:unknown_atom) == :worker
  end
end
