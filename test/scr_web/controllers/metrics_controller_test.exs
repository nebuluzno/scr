defmodule SCRWeb.MetricsControllerTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint SCRWeb.Endpoint

  test "GET /metrics/prometheus exposes Prometheus text metrics" do
    :telemetry.execute(
      [:scr, :task_queue, :enqueue],
      %{count: 1, queue_size: 1},
      %{priority: :normal, result: :accepted}
    )

    conn = get(build_conn(), "/metrics/prometheus")

    assert conn.status == 200
    assert Enum.any?(get_resp_header(conn, "content-type"), &String.contains?(&1, "text/plain"))
    assert conn.resp_body =~ "scr_task_queue_enqueue_total"
  end
end
