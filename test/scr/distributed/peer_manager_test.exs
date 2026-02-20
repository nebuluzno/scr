defmodule SCR.Distributed.PeerManagerTest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.PeerManager

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    original_state = :sys.get_state(PeerManager)

    on_exit(fn ->
      :sys.replace_state(PeerManager, fn _ -> original_state end)
    end)

    :ok
  end

  test "status exposes expected keys" do
    status = PeerManager.status()

    assert Map.has_key?(status, :enabled)
    assert Map.has_key?(status, :configured_peers)
    assert Map.has_key?(status, :connected_peers)
    assert Map.has_key?(status, :last_connect_results)
  end

  test "connect_now attempts configured peers when enabled" do
    :sys.replace_state(PeerManager, fn state ->
      %{state | enabled: true, peers: [Node.self()], reconnect_interval_ms: 5_000}
    end)

    results = PeerManager.connect_now()

    assert Map.has_key?(results, Node.self())
    assert Map.get(results, Node.self()) in [:ignored, true, false, :node_not_alive]
  end

  test "failed peer connections increase backoff interval up to max cap" do
    :sys.replace_state(PeerManager, fn state ->
      %{
        state
        | enabled: true,
          peers: [:"missing@127.0.0.1"],
          reconnect_interval_ms: 10,
          current_reconnect_interval_ms: 10,
          max_reconnect_interval_ms: 40,
          backoff_multiplier: 2.0,
          consecutive_failures: 0
      }
    end)

    _ = PeerManager.connect_now()
    status_1 = PeerManager.status()
    assert status_1.current_reconnect_interval_ms == 20
    assert status_1.consecutive_failures == 1

    _ = PeerManager.connect_now()
    status_2 = PeerManager.status()
    assert status_2.current_reconnect_interval_ms == 40
    assert status_2.consecutive_failures == 2

    _ = PeerManager.connect_now()
    status_3 = PeerManager.status()
    assert status_3.current_reconnect_interval_ms == 40
    assert status_3.consecutive_failures == 3
  end
end
