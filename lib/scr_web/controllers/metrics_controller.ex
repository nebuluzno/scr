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
end
