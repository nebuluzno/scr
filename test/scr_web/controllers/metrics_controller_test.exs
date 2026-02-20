defmodule SCRWeb.MetricsControllerTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint SCRWeb.Endpoint

  test "GET /metrics/prometheus exposes Prometheus text metrics" do
    :telemetry.execute(
      [:scr, :task_queue, :enqueue],
      %{count: 1, queue_size: 1},
      %{priority: :normal, result: :accepted, task_type: "test"}
    )

    :telemetry.execute(
      [:scr, :tools, :rate_limit],
      %{count: 1},
      %{tool: "calculator", result: :rejected}
    )

    :telemetry.execute(
      [:scr, :mcp, :server, :status],
      %{healthy: 1, failures: 0, circuit_open: 0},
      %{server: "filesystem"}
    )

    conn = get(build_conn(), "/metrics/prometheus")

    assert conn.status == 200
    assert Enum.any?(get_resp_header(conn, "content-type"), &String.contains?(&1, "text/plain"))
    assert conn.resp_body =~ "scr_task_queue_enqueue_total"
    assert conn.resp_body =~ "scr_tools_rate_limit_total"
    assert conn.resp_body =~ "scr_mcp_server_healthy"
  end
end
