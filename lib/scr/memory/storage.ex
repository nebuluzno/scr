defmodule SCR.Memory.Storage do
  @moduledoc """
  Backend-agnostic helpers for reading, writing, and verifying memory records.
  """

  @tables [:scr_tasks, :scr_memory, :scr_agent_states]

  @type backend :: :ets | :dets | :sqlite | :postgres
  @type table_data :: %{optional(atom()) => map()}

  @spec read_backend(backend(), keyword()) :: {:ok, table_data()} | {:error, term()}
  def read_backend(:ets, _opts) do
    data =
      Enum.into(@tables, %{}, fn table ->
        rows =
          if :ets.whereis(table) == :undefined do
            %{}
          else
            :ets.tab2list(table) |> Enum.into(%{})
          end

        {table, rows}
      end)

    {:ok, data}
  end

  def read_backend(:dets, opts) do
    path = dets_path!(opts)

    with {:ok, state} <- open_dets(path),
         {:ok, data} <- read_dets(state) do
      close_dets(state)
      {:ok, data}
    else
      {:error, _} = error -> error
    end
  end

  def read_backend(:sqlite, opts) do
    path = sqlite_path!(opts)

    with :ok <- ensure_sqlite_available(),
         {:ok, data} <- read_sqlite(path) do
      {:ok, data}
    end
  end

  def read_backend(:postgres, opts) do
    with :ok <- ensure_postgrex_available(),
         {:ok, conn} <- open_postgres(opts),
         {:ok, data} <- read_postgres(conn) do
      _ = GenServer.stop(conn, :normal, 1_000)
      {:ok, data}
    else
      {:error, _} = error -> error
    end
  end

  @spec clear_backend(backend(), keyword()) :: :ok | {:error, term()}
  def clear_backend(:ets, _opts) do
    Enum.each(@tables, fn table ->
      if :ets.whereis(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end)

    :ok
  end

  def clear_backend(:dets, opts) do
    path = dets_path!(opts)

    with {:ok, state} <- open_dets(path) do
      Enum.each(state.tables, fn {_key, table} -> :ok = :dets.delete_all_objects(table) end)
      close_dets(state)
      :ok
    end
  end

  def clear_backend(:sqlite, opts) do
    path = sqlite_path!(opts)

    with :ok <- ensure_sqlite_available(),
         :ok <- init_sqlite(path) do
      sql = """
      DELETE FROM scr_tasks;
      DELETE FROM scr_memory;
      DELETE FROM scr_agent_states;
      """

      case run_sql(path, sql) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def clear_backend(:postgres, opts) do
    with :ok <- ensure_postgrex_available(),
         {:ok, conn} <- open_postgres(opts) do
      sql = """
      DELETE FROM scr_tasks;
      DELETE FROM scr_memory;
      DELETE FROM scr_agent_states;
      """

      result = postgres_query(conn, sql, [])
      _ = GenServer.stop(conn, :normal, 1_000)

      case result do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec write_backend(backend(), table_data(), keyword()) :: :ok | {:error, term()}
  def write_backend(:ets, data, _opts) do
    Enum.each(@tables, fn table ->
      maybe_create_ets_table(table)

      data
      |> Map.get(table, %{})
      |> Enum.each(fn {key, value} ->
        :ets.insert(table, {key, value})
      end)
    end)

    :ok
  end

  def write_backend(:dets, data, opts) do
    path = dets_path!(opts)

    with {:ok, state} <- open_dets(path) do
      Enum.each(@tables, fn table ->
        dets_table = Map.fetch!(state.tables, table)

        data
        |> Map.get(table, %{})
        |> Enum.each(fn {key, value} ->
          :ok = :dets.insert(dets_table, {key, value})
        end)
      end)

      close_dets(state)
      :ok
    end
  end

  def write_backend(:sqlite, data, opts) do
    path = sqlite_path!(opts)

    with :ok <- ensure_sqlite_available(),
         :ok <- init_sqlite(path) do
      Enum.each(@tables, fn table ->
        table_name = sqlite_table_name(table)

        data
        |> Map.get(table, %{})
        |> Enum.each(fn {key, value} ->
          k_hex = key |> :erlang.term_to_binary() |> Base.encode16(case: :upper)
          v_hex = value |> :erlang.term_to_binary() |> Base.encode16(case: :upper)
          sql = "INSERT OR REPLACE INTO #{table_name}(k, v) VALUES (X'#{k_hex}', X'#{v_hex}');"
          _ = run_sql(path, sql)
        end)
      end)

      :ok
    end
  end

  def write_backend(:postgres, data, opts) do
    with :ok <- ensure_postgrex_available(),
         {:ok, conn} <- open_postgres(opts),
         :ok <- init_postgres_schema(conn) do
      result =
        Enum.reduce_while(@tables, :ok, fn table, _acc ->
          table_name = postgres_table_name(table)

          sql = """
          INSERT INTO #{table_name}(k, v) VALUES($1, $2)
          ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
          """

          status =
            data
            |> Map.get(table, %{})
            |> Enum.reduce_while(:ok, fn {key, value}, _ ->
              key_bin = :erlang.term_to_binary(key)
              value_bin = :erlang.term_to_binary(value)

              case postgres_query(conn, sql, [key_bin, value_bin]) do
                {:ok, _} -> {:cont, :ok}
                {:error, reason} -> {:halt, {:error, reason}}
              end
            end)

          case status do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      _ = GenServer.stop(conn, :normal, 1_000)
      result
    end
  end

  @doc """
  Verifies shape/consistency of loaded memory data.
  """
  @spec verify_data(table_data()) :: %{
          errors: [String.t()],
          warnings: [String.t()],
          counts: map()
        }
  def verify_data(data) when is_map(data) do
    errors =
      Enum.flat_map(@tables, fn table ->
        table_data = Map.get(data, table, %{})

        cond do
          not is_map(table_data) ->
            ["#{table}: expected a map of key/value entries"]

          true ->
            Enum.flat_map(table_data, fn
              {key, _value} when is_nil(key) -> ["#{table}: nil key detected"]
              {_key, _value} -> []
            end)
        end
      end)

    task_keys = data |> Map.get(:scr_tasks, %{}) |> Map.keys() |> MapSet.new()
    result_keys = data |> Map.get(:scr_memory, %{}) |> Map.keys() |> MapSet.new()
    orphan_result_count = MapSet.difference(result_keys, task_keys) |> MapSet.size()

    warnings =
      if orphan_result_count > 0 do
        ["scr_memory: #{orphan_result_count} result entries have no matching task key"]
      else
        []
      end

    counts =
      Enum.into(@tables, %{}, fn table ->
        value = Map.get(data, table, %{})
        count = if is_map(value), do: map_size(value), else: 0
        {table, count}
      end)

    %{errors: errors, warnings: warnings, counts: counts}
  end

  defp maybe_create_ets_table(name) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, [:set, :named_table, :public])
    end
  end

  defp dets_path!(opts) do
    path = Keyword.get(opts, :path)
    if is_binary(path) and path != "", do: path, else: "tmp/memory"
  end

  defp sqlite_path!(opts) do
    path = Keyword.get(opts, :path, Path.join("tmp/memory", "scr_memory.sqlite3"))

    if Path.extname(path) == "" do
      Path.join(path, "scr_memory.sqlite3")
    else
      path
    end
  end

  defp open_dets(path) do
    File.mkdir_p!(path)

    tables =
      Enum.into(@tables, %{}, fn table ->
        unique = System.unique_integer([:positive])
        dets_table = String.to_atom("scr_migrate_#{table}_#{unique}")
        file = String.to_charlist(Path.join(path, "#{table}.dets"))

        case :dets.open_file(dets_table, type: :set, file: file) do
          {:ok, opened} -> {table, opened}
          {:error, reason} -> throw({:error, {:dets_open_failed, table, reason}})
        end
      end)

    {:ok, %{tables: tables}}
  catch
    {:error, _} = error -> error
  end

  defp read_dets(state) do
    data =
      Enum.into(state.tables, %{}, fn {table, dets_table} ->
        rows =
          dets_table
          |> :dets.match_object({:"$1", :"$2"})
          |> Enum.into(%{})

        {table, rows}
      end)

    {:ok, data}
  rescue
    e -> {:error, {:dets_read_failed, e}}
  end

  defp close_dets(%{tables: tables}) do
    Enum.each(tables, fn {_key, table} ->
      _ = :dets.sync(table)
      _ = :dets.close(table)
    end)
  end

  defp ensure_sqlite_available do
    if is_nil(System.find_executable("sqlite3")) do
      {:error, :sqlite3_not_available}
    else
      :ok
    end
  end

  defp init_sqlite(path) do
    File.mkdir_p!(Path.dirname(path))

    sql = """
    PRAGMA journal_mode=WAL;
    CREATE TABLE IF NOT EXISTS scr_tasks (k BLOB PRIMARY KEY, v BLOB NOT NULL);
    CREATE TABLE IF NOT EXISTS scr_memory (k BLOB PRIMARY KEY, v BLOB NOT NULL);
    CREATE TABLE IF NOT EXISTS scr_agent_states (k BLOB PRIMARY KEY, v BLOB NOT NULL);
    """

    case run_sql(path, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_sqlite(path) do
    if not File.exists?(path) do
      {:ok, Enum.into(@tables, %{}, &{&1, %{}})}
    else
      data =
        Enum.into(@tables, %{}, fn table ->
          sql = "SELECT hex(k), hex(v) FROM #{sqlite_table_name(table)};"

          rows =
            case run_sql(path, sql) do
              {:ok, output} ->
                output
                |> String.split("\n", trim: true)
                |> Enum.reduce(%{}, fn line, acc ->
                  case String.split(line, "|", parts: 2) do
                    [k_hex, v_hex] ->
                      with {:ok, key_bin} <- Base.decode16(k_hex, case: :mixed),
                           {:ok, val_bin} <- Base.decode16(v_hex, case: :mixed) do
                        key = :erlang.binary_to_term(key_bin)
                        value = :erlang.binary_to_term(val_bin)
                        Map.put(acc, key, value)
                      else
                        _ -> acc
                      end

                    _ ->
                      acc
                  end
                end)

              {:error, _} ->
                %{}
            end

          {table, rows}
        end)

      {:ok, data}
    end
  rescue
    e -> {:error, {:sqlite_read_failed, e}}
  end

  defp run_sql(path, sql) do
    args = ["-batch", "-noheader", "-separator", "|", path, sql]

    case System.cmd("sqlite3", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, String.trim(error)}
    end
  rescue
    e in ErlangError -> {:error, e.original}
  end

  defp sqlite_table_name(:scr_tasks), do: "scr_tasks"
  defp sqlite_table_name(:scr_memory), do: "scr_memory"
  defp sqlite_table_name(:scr_agent_states), do: "scr_agent_states"

  defp ensure_postgrex_available do
    if Code.ensure_loaded?(Postgrex), do: :ok, else: {:error, :postgrex_not_available}
  end

  defp open_postgres(opts) do
    pg_opts =
      case Keyword.get(opts, :url) do
        url when is_binary(url) and url != "" ->
          [url: url]

        _ ->
          [
            hostname: Keyword.get(opts, :hostname),
            username: Keyword.get(opts, :username),
            password: Keyword.get(opts, :password),
            database: Keyword.get(opts, :database),
            port: Keyword.get(opts, :port, 5432),
            ssl: Keyword.get(opts, :ssl, false)
          ]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      end

    if pg_opts == [] or
         (is_nil(Keyword.get(pg_opts, :url)) and is_nil(Keyword.get(pg_opts, :hostname))) do
      {:error, :missing_postgres_config}
    else
      Postgrex.start_link(pg_opts)
    end
  end

  defp init_postgres_schema(conn) do
    sql = """
    CREATE TABLE IF NOT EXISTS scr_tasks (k BYTEA PRIMARY KEY, v BYTEA NOT NULL);
    CREATE TABLE IF NOT EXISTS scr_memory (k BYTEA PRIMARY KEY, v BYTEA NOT NULL);
    CREATE TABLE IF NOT EXISTS scr_agent_states (k BYTEA PRIMARY KEY, v BYTEA NOT NULL);
    """

    case postgres_query(conn, sql, []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_postgres(conn) do
    data =
      Enum.into(@tables, %{}, fn table ->
        sql = "SELECT k, v FROM #{postgres_table_name(table)};"

        rows =
          case postgres_query(conn, sql, []) do
            {:ok, %{rows: pg_rows}} ->
              Enum.reduce(pg_rows, %{}, fn
                [k, v], acc when is_binary(k) and is_binary(v) ->
                  key = :erlang.binary_to_term(k)
                  value = :erlang.binary_to_term(v)
                  Map.put(acc, key, value)

                _, acc ->
                  acc
              end)

            _ ->
              %{}
          end

        {table, rows}
      end)

    {:ok, data}
  rescue
    e -> {:error, {:postgres_read_failed, e}}
  end

  defp postgres_query(conn, sql, params) do
    Postgrex.query(conn, sql, params)
  rescue
    _ -> {:error, :postgres_query_failed}
  end

  defp postgres_table_name(:scr_tasks), do: "scr_tasks"
  defp postgres_table_name(:scr_memory), do: "scr_memory"
  defp postgres_table_name(:scr_agent_states), do: "scr_agent_states"
end
