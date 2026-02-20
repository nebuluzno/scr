defmodule SCR.MixProject do
  use Mix.Project

  def project do
    [
      app: :scr,
      version: "0.5.0-alpha",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {SCR, []}
    ]
  end

  defp deps do
    [
      # Core
      {:elixir_uuid, "~> 1.2"},
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:gettext, "~> 0.24"},

      # Phoenix
      {:phoenix, "~> 1.7.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 0.20.0"},
      {:floki, "~> 0.36", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.0"},

      # Server (Cowboy)
      {:plug_cowboy, "~> 2.6"},

      # Tailwind (for styling)
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # PubSub for real-time
      {:phoenix_pubsub, "~> 2.1"},

      # Telemetry + Prometheus metrics
      {:telemetry_poller, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus, "~> 1.1"},

      # OpenTelemetry export bridge
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.8"},

      # Distributed node discovery
      {:libcluster, "~> 3.4"},

      # Optional durable memory backend (Postgres)
      {:postgrex, "~> 0.20"}
    ]
  end
end
