defmodule SCR.Distributed.SpecRegistryTest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.SpecRegistry

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    original = SpecRegistry.all()

    on_exit(fn ->
      Enum.each(SpecRegistry.all(), fn entry ->
        SpecRegistry.remove(entry.agent_id)
      end)

      Enum.each(original, fn entry ->
        SpecRegistry.upsert(
          entry.agent_id,
          entry.agent_type,
          entry.module,
          entry.init_arg,
          entry.owner_node
        )
      end)
    end)

    :ok
  end

  test "upsert/get/remove lifecycle" do
    agent_id = "spec_registry_#{System.unique_integer([:positive])}"

    SpecRegistry.upsert(
      agent_id,
      :worker,
      SCR.Agents.WorkerAgent,
      %{agent_id: agent_id},
      Node.self()
    )

    Process.sleep(10)

    entry = SpecRegistry.get(agent_id)
    assert entry.agent_id == agent_id
    assert entry.agent_type == :worker

    SpecRegistry.claim(agent_id, :other_node)
    Process.sleep(10)
    claimed = SpecRegistry.get(agent_id)
    assert claimed.owner_node == :other_node

    SpecRegistry.remove(agent_id)
    Process.sleep(10)
    assert SpecRegistry.get(agent_id) == nil
  end
end
