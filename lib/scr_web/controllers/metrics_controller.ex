defmodule SCRWeb.MetricsController do
  use SCRWeb, :controller

  def index(conn, _params) do
    cache_stats = SCR.LLM.Cache.stats()
    metrics_stats = SCR.LLM.Metrics.stats()

    render(conn, :index,
      cache_stats: cache_stats,
      metrics_stats: metrics_stats
    )
  end

  def prometheus(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, SCR.Telemetry.scrape())
  end
end
