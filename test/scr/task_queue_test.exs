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

  test "emits telemetry events for enqueue and dequeue", %{server: server} do
    handler_id = "task-queue-telemetry-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [[:scr, :task_queue, :enqueue], [:scr, :task_queue, :dequeue]],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "event-1"}, :normal, server)
    assert {:ok, %{task_id: "event-1"}} = TaskQueue.dequeue(server)

    assert_receive {:telemetry_event, [:scr, :task_queue, :enqueue], %{count: 1},
                    %{priority: :normal, result: :accepted, task_type: "unknown"}}

    assert_receive {:telemetry_event, [:scr, :task_queue, :dequeue], %{count: 1},
                    %{priority: :normal, result: :ok, task_type: "unknown"}}
  end

  test "replays persisted tasks from dets backend" do
    path = "/tmp/scr_task_queue_test_#{System.unique_integer([:positive])}.dets"
    server1 = :"task_queue_dets_1_#{System.unique_integer([:positive])}"
    server2 = :"task_queue_dets_2_#{System.unique_integer([:positive])}"

    {:ok, pid1} =
      start_supervised(%{
        id: {:task_queue_dets, server1},
        start:
          {TaskQueue, :start_link,
           [[name: server1, max_size: 10, backend: :dets, dets_path: path]]}
      })

    on_exit(fn -> File.rm(path) end)

    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "persist-1"}, :high, server1)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "persist-2"}, :normal, server1)

    GenServer.stop(pid1)

    {:ok, _pid2} =
      start_supervised(%{
        id: {:task_queue_dets, server2},
        start:
          {TaskQueue, :start_link,
           [[name: server2, max_size: 10, backend: :dets, dets_path: path]]}
      })

    assert {:ok, %{task_id: "persist-1"}} = TaskQueue.dequeue(server2)
    assert {:ok, %{task_id: "persist-2"}} = TaskQueue.dequeue(server2)
    assert :empty = TaskQueue.dequeue(server2)
  end
end
