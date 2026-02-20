defmodule SCR.Telemetry.StreamTest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "captures recent telemetry events" do
    :ok = SCR.TaskQueue.clear()
    assert {:ok, _} = SCR.TaskQueue.enqueue(%{task_id: "stream_evt_1"}, :normal)
    assert {:ok, _} = SCR.TaskQueue.dequeue()

    events = SCR.Telemetry.Stream.recent(20)
    assert is_list(events)
    assert Enum.any?(events, fn e -> e.event == [:scr, :task_queue, :enqueue] end)
    assert Enum.any?(events, fn e -> e.event == [:scr, :task_queue, :dequeue] end)
  end
end
