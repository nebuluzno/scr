defmodule SCR.Distributed.RecoveryDrillsTest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.RecoveryDrills

  test "node_flap drill returns planned events in dry_run mode" do
    assert {:ok, %{dry_run: true, events: events}} =
             RecoveryDrills.run(:node_flap, node: Node.self(), cycles: 2, dry_run: true)

    assert length(events) > 0
    assert Enum.all?(events, fn {mode, _step} -> mode == :planned end)
  end

  test "partition drill returns planned events in dry_run mode" do
    assert {:ok, %{dry_run: true, events: events}} =
             RecoveryDrills.run(:partition, peers: [:"node1@127.0.0.1"], dry_run: true)

    assert length(events) == 3
  end
end
