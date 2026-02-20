defmodule Mix.Tasks.Scr.Memory.Verify do
  @shortdoc "Verifies SCR memory backend integrity and consistency"
  @moduledoc """
  Verifies memory backend records and reports consistency findings.

  ## Usage

      mix scr.memory.verify --backend dets --path tmp/memory
      mix scr.memory.verify --backend sqlite --path tmp/memory/scr_memory.sqlite3
      mix scr.memory.verify --backend postgres --url postgres://user:pass@localhost:5432/scr
  """

  use Mix.Task

  alias SCR.Memory.Storage

  @switches [backend: :string, path: :string, url: :string]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)

    cfg = Application.get_env(:scr, :memory_storage, [])

    backend =
      parse_backend(Keyword.get(opts, :backend) || to_string(Keyword.get(cfg, :backend, :ets)))

    if is_nil(backend) do
      Mix.raise("Invalid --backend value. Supported: ets|dets|sqlite|postgres")
    end

    backend_opts = backend_opts(backend, opts, cfg)

    with {:ok, data} <- Storage.read_backend(backend, backend_opts) do
      report = Storage.verify_data(data)
      counts = report.counts

      Mix.shell().info(
        "Verify report (#{backend}): tasks=#{counts.scr_tasks}, results=#{counts.scr_memory}, agent_states=#{counts.scr_agent_states}"
      )

      Enum.each(report.warnings, &Mix.shell().info("warning: " <> &1))

      if report.errors == [] do
        Mix.shell().info("verify: ok")
      else
        Enum.each(report.errors, &Mix.shell().error("error: " <> &1))
        Mix.raise("verify failed with #{length(report.errors)} error(s)")
      end
    else
      {:error, reason} ->
        Mix.raise("Verify failed: #{inspect(reason)}")
    end
  end

  defp parse_backend("ets"), do: :ets
  defp parse_backend("dets"), do: :dets
  defp parse_backend("sqlite"), do: :sqlite
  defp parse_backend("postgres"), do: :postgres
  defp parse_backend(_), do: nil

  defp backend_opts(:ets, _opts, _cfg), do: []

  defp backend_opts(:dets, opts, cfg) do
    [path: Keyword.get(opts, :path) || Keyword.get(cfg, :path, "tmp/memory")]
  end

  defp backend_opts(:sqlite, opts, cfg) do
    [
      path:
        Keyword.get(opts, :path) ||
          Keyword.get(cfg, :path, Path.join("tmp/memory", "scr_memory.sqlite3"))
    ]
  end

  defp backend_opts(:postgres, opts, cfg) do
    url = Keyword.get(opts, :url)
    postgres_cfg = Keyword.get(cfg, :postgres, [])

    if is_binary(url) and url != "" do
      [url: url]
    else
      postgres_cfg
    end
  end
end
