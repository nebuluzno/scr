defmodule SCR.Distributed.CapacityTunerTest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.CapacityTuner
  alias SCR.TaskQueue

  test "increases queue max_size when rejection ratio is high" do
    queue = :"capacity_tuner_queue_#{System.unique_integer([:positive])}"
    tuner = :"capacity_tuner_#{System.unique_integer([:positive])}"

    {:ok, _queue_pid} = start_supervised({TaskQueue, name: queue, max_size: 2})

    {:ok, _tuner_pid} =
      start_supervised(
        {CapacityTuner,
         [
           name: tuner,
           enabled: false,
           queue_server: queue,
           update_constraints: false,
           min_queue_size: 2,
           max_queue_size: 20,
           up_step: 5,
           down_step: 2,
           high_rejection_ratio: 0.1,
           low_rejection_ratio: 0.0
         ]}
      )

    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "a"}, :normal, queue)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "b"}, :normal, queue)
    assert {:error, :queue_full} = TaskQueue.enqueue(%{task_id: "c"}, :normal, queue)

    send(tuner, :tick)
    Process.sleep(25)

    assert TaskQueue.stats(queue).max_size == 7
    state = GenServer.call(tuner, :status)
    assert state.last_decision == :increased
  end

  test "increases queue max_size when estimated latency exceeds SLO" do
    queue = :"capacity_tuner_latency_queue_#{System.unique_integer([:positive])}"
    tuner = :"capacity_tuner_latency_#{System.unique_integer([:positive])}"

    {:ok, _queue_pid} = start_supervised({TaskQueue, name: queue, max_size: 20})

    {:ok, _tuner_pid} =
      start_supervised(
        {CapacityTuner,
         [
           name: tuner,
           enabled: false,
           queue_server: queue,
           update_constraints: false,
           min_queue_size: 10,
           max_queue_size: 50,
           up_step: 5,
           down_step: 2,
           high_rejection_ratio: 0.9,
           low_rejection_ratio: 0.0,
           target_latency_ms: 100,
           avg_service_ms: 50
         ]}
      )

    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "a"}, :normal, queue)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "b"}, :normal, queue)
    assert {:ok, _} = TaskQueue.enqueue(%{task_id: "c"}, :normal, queue)

    send(tuner, :tick)
    Process.sleep(25)

    state = GenServer.call(tuner, :status)
    assert state.last_decision == :increased
    assert state.last_reason == :latency_slo_breach
  end
end
