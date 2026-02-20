defmodule SCR.Distributed.NodeWatchdogTest do
  use ExUnit.Case, async: false

  alias SCR.Distributed.NodeWatchdog

  setup do
    server = :"node_watchdog_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      NodeWatchdog.start_link(
        name: server,
        config: [
          enabled: true,
          watchdog_enabled: true,
          flap_window_ms: 100,
          flap_threshold: 2,
          quarantine_ms: 200
        ]
      )

    %{server: server}
  end

  test "quarantines flapping node after threshold", %{server: server} do
    node = :"flap@127.0.0.1"

    NodeWatchdog.note_node_down(node, server)
    NodeWatchdog.note_node_down(node, server)
    Process.sleep(10)

    assert NodeWatchdog.quarantined?(node, server)
  end

  test "filter_healthy removes quarantined nodes", %{server: server} do
    bad = :"bad@127.0.0.1"
    good = :"good@127.0.0.1"

    NodeWatchdog.quarantine(bad, 500, server)
    Process.sleep(10)

    healthy = NodeWatchdog.filter_healthy([bad, good], server)
    assert good in healthy
    refute bad in healthy
  end

  test "quarantine expires after ttl", %{server: server} do
    node = :"temp@127.0.0.1"
    NodeWatchdog.quarantine(node, 50, server)
    Process.sleep(80)

    refute NodeWatchdog.quarantined?(node, server)
  end
end
