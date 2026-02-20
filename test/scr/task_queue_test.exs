defmodule SCR.TaskQueueTest do
  use ExUnit.Case, async: false

  alias SCR.TaskQueue

  setup do
    server = :"task_queue_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({TaskQueue, name: server, max_size: 2})
    %{server: server}
  end

  test "dequeues by priority order", %{server: server} do
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "low"}, :low, server)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "high"}, :high, server)

    assert {:ok, %{task_id: "high"}} = TaskQueue.dequeue(server)
    assert {:ok, %{task_id: "low"}} = TaskQueue.dequeue(server)
    assert :empty = TaskQueue.dequeue(server)
  end

  test "applies backpressure when queue is full", %{server: server} do
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "1"}, :normal, server)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "2"}, :normal, server)
    assert {:error, :queue_full} = TaskQueue.enqueue(%{task_id: "3"}, :normal, server)

    stats = TaskQueue.stats(server)
    assert stats.size == 2
    assert stats.rejected == 1
  end

  test "pause and resume toggle queue state", %{server: server} do
    assert false == TaskQueue.paused?(server)
    assert :ok = TaskQueue.pause(server)
    assert true == TaskQueue.paused?(server)
    assert :ok = TaskQueue.resume(server)
    assert false == TaskQueue.paused?(server)
  end

  test "drain empties queue and returns tasks", %{server: server} do
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "h"}, :high, server)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "n"}, :normal, server)

    assert {:ok, tasks} = TaskQueue.drain(server)
    assert Enum.map(tasks, & &1.task_id) == ["h", "n"]
    assert 0 == TaskQueue.size(server)
  end
end
