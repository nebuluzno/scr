defmodule SCR.Distributed.PlacementHistoryTest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.PlacementHistory

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "capture_now/0 returns placement snapshot shape" do
    snapshot = PlacementHistory.capture_now()

    assert is_map(snapshot)
    assert Map.has_key?(snapshot, :captured_at)
    assert Map.has_key?(snapshot, :placement_report)
    assert Map.has_key?(snapshot, :pressure_report)
    assert Map.has_key?(snapshot, :watchdog)
    assert Map.has_key?(snapshot, :best_node)
  end

  test "recent/1 returns bounded history list" do
    _ = PlacementHistory.capture_now()
    _ = PlacementHistory.capture_now()

    recent = PlacementHistory.recent(2)
    assert is_list(recent)
    assert length(recent) <= 2
  end
end
