defmodule Mix.Tasks.Scr.Memory.Migrate do
  @shortdoc "Migrates SCR memory records between backends"
  @moduledoc """
  Migrates memory records (`scr_tasks`, `scr_memory`, `scr_agent_states`) from one backend to another.

  ## Usage

      mix scr.memory.migrate --from dets --to sqlite --from-path tmp/memory --to-path tmp/memory/scr_memory.sqlite3

  Supported backends: `ets`, `dets`, `sqlite`, `postgres`.
  """

  use Mix.Task

  alias SCR.Memory.Storage

  @switches [
    from: :string,
    to: :string,
    from_path: :string,
    to_path: :string,
    from_url: :string,
    to_url: :string,
    merge: :boolean
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)

    from = parse_backend(Keyword.get(opts, :from))
    to = parse_backend(Keyword.get(opts, :to))
    merge = Keyword.get(opts, :merge, false)

    if is_nil(from) or is_nil(to) do
      Mix.raise("Both --from and --to are required. Backends: ets|dets|sqlite|postgres")
    end

    from_opts = backend_opts(opts, :from, from)
    to_opts = backend_opts(opts, :to, to)

    with {:ok, source_data} <- Storage.read_backend(from, from_opts),
         :ok <- maybe_clear_target(to, to_opts, merge),
         :ok <- Storage.write_backend(to, source_data, to_opts) do
      counts = Storage.verify_data(source_data).counts

      Mix.shell().info(
        "Migration complete: #{from} -> #{to} (tasks=#{counts.scr_tasks}, results=#{counts.scr_memory}, agent_states=#{counts.scr_agent_states})"
      )
    else
      {:error, reason} ->
        Mix.raise("Migration failed: #{inspect(reason)}")
    end
  end

  defp maybe_clear_target(_to, _opts, true), do: :ok
  defp maybe_clear_target(to, opts, false), do: Storage.clear_backend(to, opts)

  defp parse_backend(nil), do: nil
  defp parse_backend("ets"), do: :ets
  defp parse_backend("dets"), do: :dets
  defp parse_backend("sqlite"), do: :sqlite
  defp parse_backend("postgres"), do: :postgres
  defp parse_backend(_), do: nil

  defp backend_opts(opts, side, backend) do
    cfg = Application.get_env(:scr, :memory_storage, [])

    path =
      case side do
        :from -> Keyword.get(opts, :from_path)
        :to -> Keyword.get(opts, :to_path)
      end

    url =
      case side do
        :from -> Keyword.get(opts, :from_url)
        :to -> Keyword.get(opts, :to_url)
      end

    case backend do
      :dets ->
        [path: path || Keyword.get(cfg, :path, "tmp/memory")]

      :sqlite ->
        [path: path || Keyword.get(cfg, :path, Path.join("tmp/memory", "scr_memory.sqlite3"))]

      :postgres ->
        postgres_cfg = Keyword.get(cfg, :postgres, [])

        if is_binary(url) and url != "" do
          [url: url]
        else
          postgres_cfg
        end

      :ets ->
        []
    end
  end
end
