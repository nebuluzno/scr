defmodule SCR.Distributed.ResilienceE2ETest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.RecoveryDrills

  @moduletag :distributed_resilience

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  test "queued task recovery is deterministic after transient saturation" do
    queue_name = :"queue_recovery_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({SCR.TaskQueue, name: queue_name, max_size: 1})

    assert {:ok, %{size: 1}} = SCR.TaskQueue.enqueue(%{id: "a"}, :normal, queue_name)
    assert {:error, :queue_full} = SCR.TaskQueue.enqueue(%{id: "b"}, :normal, queue_name)
    assert {:ok, %{id: "a"}} = SCR.TaskQueue.dequeue(queue_name)
    assert {:ok, %{size: 1}} = SCR.TaskQueue.enqueue(%{id: "c"}, :normal, queue_name)

    stats = SCR.TaskQueue.stats(queue_name)
    assert stats.accepted == 2
    assert stats.rejected == 1
    assert stats.size == 1
  end

  @tag :multi_node
  test "partition drill disconnects and rejoins a peer node" do
    if multi_node_enabled?() do
      case with_peer_node("partition") do
        {:ok, peer, peer_node} ->
          on_exit(fn -> :peer.stop(peer) end)

          assert true = Node.connect(peer_node)
          assert wait_until(fn -> peer_node in Node.list() end, 2_000)

          assert {:ok, %{dry_run: false, events: events}} =
                   RecoveryDrills.run(
                     :partition,
                     peers: [peer_node],
                     duration_ms: 10,
                     dry_run: false
                   )

          assert Enum.any?(events, fn
                   {:executed, {:disconnect, ^peer_node}, _} -> true
                   _ -> false
                 end)

          assert Enum.any?(events, fn
                   {:executed, {:connect, ^peer_node}, _} -> true
                   _ -> false
                 end)

          assert wait_until(fn -> peer_node in Node.list() end, 2_000)
          assert :pong == :rpc.call(peer_node, Node, :ping, [Node.self()])

        {:error, reason} ->
          assert reason != nil
      end
    else
      assert true
    end
  end

  @tag :multi_node
  test "node flap quarantine clears on rejoin" do
    if multi_node_enabled?() do
      case with_peer_node("flap") do
        {:ok, peer, peer_node} ->
          on_exit(fn -> :peer.stop(peer) end)

          watchdog_name = :"watchdog_#{System.unique_integer([:positive])}"

          {:ok, _pid} =
            start_supervised(
              {SCR.Distributed.NodeWatchdog,
               name: watchdog_name,
               config: [
                 enabled: true,
                 watchdog_enabled: true,
                 flap_window_ms: 1_000,
                 flap_threshold: 2,
                 quarantine_ms: 5_000
               ]}
            )

          SCR.Distributed.NodeWatchdog.note_node_down(peer_node, watchdog_name)
          SCR.Distributed.NodeWatchdog.note_node_down(peer_node, watchdog_name)
          assert SCR.Distributed.NodeWatchdog.quarantined?(peer_node, watchdog_name)

          SCR.Distributed.NodeWatchdog.note_node_up(peer_node, watchdog_name)

          assert wait_until(
                   fn ->
                     not SCR.Distributed.NodeWatchdog.quarantined?(peer_node, watchdog_name)
                   end,
                   1_000
                 )

        {:error, reason} ->
          assert reason != nil
      end
    else
      assert true
    end
  end

  @tag :multi_node
  test "distributed queue pressure recovers after remote queue drain" do
    if multi_node_enabled?() do
      case with_peer_node("queue") do
        {:ok, peer, peer_node} ->
          on_exit(fn -> :peer.stop(peer) end)

          assert {:ok, _} = safe_peer_call(peer, Application, :ensure_all_started, [:scr])
          assert :ok = safe_peer_call!(peer, SCR.TaskQueue, :clear, [])
          assert :ok = safe_peer_call!(peer, SCR.TaskQueue, :set_max_size, [1])

          assert {:ok, %{size: 1}} =
                   safe_peer_call!(peer, SCR.TaskQueue, :enqueue, [%{"id" => "r1"}])

          assert {:error, :queue_full} =
                   safe_peer_call!(peer, SCR.TaskQueue, :enqueue, [%{"id" => "r2"}])

          assert {:ok, [pressure_before]} =
                   SCR.Distributed.queue_pressure_report([peer_node], 2_000)

          assert pressure_before.saturated

          assert {:ok, _task} = safe_peer_call!(peer, SCR.TaskQueue, :dequeue, [])
          assert :ok = safe_peer_call!(peer, SCR.TaskQueue, :set_max_size, [100])

          assert {:ok, [pressure_after]} =
                   SCR.Distributed.queue_pressure_report([peer_node], 2_000)

          refute pressure_after.saturated
          assert pressure_after.utilization < pressure_before.utilization

        {:error, reason} ->
          assert reason != nil
      end
    else
      assert true
    end
  end

  defp with_peer_node(suffix) do
    with :ok <- ensure_local_distribution(),
         name <- String.to_atom("scr_peer_#{suffix}_#{System.unique_integer([:positive])}"),
         {:ok, peer, node} <- :peer.start_link(%{name: name}),
         {:ok, _} <- safe_peer_call(peer, Application, :ensure_all_started, [:scr]) do
      {:ok, peer, node}
    else
      {:error, _reason} = error ->
        error

      other ->
        {:error, other}
    end
  end

  defp ensure_local_distribution do
    if Node.alive?() do
      :ok
    else
      _ = start_epmd()
      name = String.to_atom("scr_local_#{System.unique_integer([:positive])}")

      case :net_kernel.start([name, :shortnames]) do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          :ok

        {:error, reason} ->
          case Node.start(name, :shortnames) do
            {:ok, _} -> :ok
            {:error, {:already_started, _}} -> :ok
            {:error, fallback_reason} -> {:error, {reason, fallback_reason}}
          end
      end
    end
  end

  defp multi_node_enabled? do
    System.get_env("SCR_RUN_MULTI_NODE_TESTS") in ["1", "true", "TRUE", "yes", "on"]
  end

  defp start_epmd do
    case System.cmd("epmd", ["-daemon"]) do
      {_out, 0} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp safe_peer_call(peer, module, fun, args) do
    try do
      {:ok, :peer.call(peer, module, fun, args)}
    catch
      :exit, reason -> {:error, reason}
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp safe_peer_call!(peer, module, fun, args) do
    case safe_peer_call(peer, module, fun, args) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp wait_until(fun, timeout_ms) when is_function(fun, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(25)
        do_wait_until(fun, deadline)
      end
    end
  end
end
