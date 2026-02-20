defmodule SCR.Agents.MemoryAgent do
  @moduledoc """
  MemoryAgent - Persistent storage for tasks and agent states.

  Uses ETS (Erlang Term Storage) for in-memory persistence with
  optional DETS/SQLite/Postgres persistence capability. Also provides LLM-powered memory
  summarization for context window management.
  """

  alias SCR.Message
  alias SCR.LLM.Client

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :memory, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    # Initialize ETS tables for memory storage (idempotent - safe to call multiple times)
    create_ets_table(:scr_memory)
    create_ets_table(:scr_tasks)
    create_ets_table(:scr_agent_states)

    agent_id = Map.get(init_arg, :agent_id, "memory_1")
    {backend, backend_state} = init_storage_backend()
    load_persisted_data(backend, backend_state)

    IO.puts("💾 MemoryAgent initialized with #{backend} storage")

    {:ok, %{agent_id: agent_id, storage: backend, backend_state: backend_state}}
  end

  # Creates an ETS table if it doesn't already exist
  # This prevents crashes on agent restart
  defp create_ets_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [:set, :named_table, :public])

      _ref ->
        # Table already exists, return the name
        name
    end
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}}, state) do
    # Get internal state from context
    internal_state = state.agent_state

    # Store task in memory
    task_id = Map.get(task_data, :task_id, UUID.uuid4())
    :ets.insert(:scr_tasks, {task_id, task_data})

    maybe_persist(
      :scr_tasks,
      task_id,
      task_data,
      internal_state.storage,
      internal_state.backend_state
    )

    IO.puts("💾 Stored task: #{task_id}")

    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :result, payload: %{result: result_data}}, state) do
    # Get internal state from context
    internal_state = state.agent_state

    # Store result in memory
    task_id = Map.get(result_data, :task_id, UUID.uuid4())
    :ets.insert(:scr_memory, {task_id, result_data})

    maybe_persist(
      :scr_memory,
      task_id,
      result_data,
      internal_state.storage,
      internal_state.backend_state
    )

    IO.puts("💾 Stored result for task: #{task_id}")

    {:noreply, internal_state}
  end

  # New: Handle memory summarization requests
  def handle_message(
        %Message{type: :task, payload: %{summarize: true, data: data}, from: from},
        state
      ) do
    IO.puts("🤖 MemoryAgent: Summarizing memory context")

    internal_state = state.agent_state

    summary = summarize_with_llm(data)

    # Send summary back to requester
    result_msg = Message.result(state.agent_id, from, %{summary: summary})
    SCR.Supervisor.send_to_agent(from, result_msg)

    {:noreply, internal_state}
  end

  # New: Handle memory retrieval with LLM
  def handle_message(%Message{type: :task, payload: %{retrieve: query}, from: from}, state) do
    IO.puts("🤖 MemoryAgent: Retrieving relevant memory for query: #{query}")

    internal_state = state.agent_state

    # Get all memories and use LLM to find relevant ones
    results = retrieve_relevant_memories(query)

    result_msg = Message.result(state.agent_id, from, %{memories: results})
    SCR.Supervisor.send_to_agent(from, result_msg)

    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :status, payload: %{status: status_data}}, state) do
    # Get internal state from context
    internal_state = state.agent_state

    # Store agent status
    agent_id = Map.get(status_data, :agent_id)

    if agent_id do
      :ets.insert(:scr_agent_states, {agent_id, status_data})

      maybe_persist(
        :scr_agent_states,
        agent_id,
        status_data,
        internal_state.storage,
        internal_state.backend_state
      )
    end

    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :ping, from: from, to: to}, state) do
    # Respond to ping
    pong = Message.pong(to, from)
    SCR.Supervisor.send_to_agent(from, pong)
    internal_state = state.agent_state
    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :stop}, state) do
    internal_state = state.agent_state
    {:stop, :normal, internal_state}
  end

  def handle_message(_message, state) do
    internal_state = state.agent_state
    {:noreply, internal_state}
  end

  def handle_heartbeat(state) do
    # Note: state here is the internal state, not wrapped in agent_state
    {:noreply, state}
  end

  def terminate(_reason, state) do
    IO.puts("💾 MemoryAgent terminating - persisting data to disk...")
    close_backend(state.storage, state.backend_state)
    # In a real system, we'd persist to disk here
    :ok
  end

  defp init_storage_backend do
    cfg = Application.get_env(:scr, :memory_storage, [])
    backend = Keyword.get(cfg, :backend, :ets)

    case backend do
      :dets ->
        path = Keyword.get(cfg, :path, "tmp/memory")
        File.mkdir_p!(path)
        {:dets, %{tables: open_dets_tables(path)}}

      :sqlite ->
        configured_path = Keyword.get(cfg, :path, Path.join("tmp/memory", "scr_memory.sqlite3"))
        path = normalize_sqlite_path(configured_path)
        File.mkdir_p!(Path.dirname(path))

        case init_sqlite(path) do
          :ok ->
            {:sqlite, %{path: path}}

          {:error, reason} ->
            IO.puts("⚠️ MemoryAgent sqlite init failed: #{inspect(reason)} (falling back to :ets)")
            {:ets, %{}}
        end

      :postgres ->
        case init_postgres(cfg) do
          {:ok, backend_state} ->
            {:postgres, backend_state}

          {:error, reason} ->
            IO.puts(
              "⚠️ MemoryAgent postgres init failed: #{inspect(reason)} (falling back to :ets)"
            )

            {:ets, %{}}
        end

      _ ->
        {:ets, %{}}
    end
  end

  defp open_dets_tables(path) do
    %{
      scr_tasks: open_dets_table(:scr_tasks, path),
      scr_memory: open_dets_table(:scr_memory, path),
      scr_agent_states: open_dets_table(:scr_agent_states, path)
    }
  end

  defp open_dets_table(name, path) do
    file = String.to_charlist(Path.join(path, "#{name}.dets"))

    case :dets.open_file(name, type: :set, file: file) do
      {:ok, table} -> table
      {:error, reason} -> raise "Failed to open DETS table #{name}: #{inspect(reason)}"
    end
  end

  defp load_persisted_data(:ets, _state), do: :ok

  defp load_persisted_data(:dets, %{tables: dets_tables}) do
    restore_dets_table(:scr_tasks, Map.get(dets_tables, :scr_tasks))
    restore_dets_table(:scr_memory, Map.get(dets_tables, :scr_memory))
    restore_dets_table(:scr_agent_states, Map.get(dets_tables, :scr_agent_states))
  end

  defp load_persisted_data(:sqlite, %{path: path}) do
    restore_sqlite_table(:scr_tasks, path)
    restore_sqlite_table(:scr_memory, path)
    restore_sqlite_table(:scr_agent_states, path)
  end

  defp load_persisted_data(:postgres, %{conn: conn}) do
    restore_postgres_table(:scr_tasks, conn)
    restore_postgres_table(:scr_memory, conn)
    restore_postgres_table(:scr_agent_states, conn)
  end

  defp restore_dets_table(_ets_table, nil), do: :ok

  defp restore_dets_table(ets_table, dets_table) do
    dets_table
    |> :dets.match_object({:"$1", :"$2"})
    |> Enum.each(fn {key, value} -> :ets.insert(ets_table, {key, value}) end)
  rescue
    _ -> :ok
  end

  defp restore_sqlite_table(ets_table, path) do
    table = sqlite_table_name(ets_table)
    sql = "SELECT hex(k), hex(v) FROM #{table};"

    with {:ok, output} <- run_sql(path, sql) do
      output
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        case String.split(line, "|", parts: 2) do
          [k_hex, v_hex] ->
            with {:ok, key_bin} <- Base.decode16(k_hex, case: :mixed),
                 {:ok, value_bin} <- Base.decode16(v_hex, case: :mixed) do
              key = :erlang.binary_to_term(key_bin)
              value = :erlang.binary_to_term(value_bin)
              :ets.insert(ets_table, {key, value})
            end

          _ ->
            :ok
        end
      end)
    end
  rescue
    _ -> :ok
  end

  defp restore_postgres_table(ets_table, conn) do
    table = postgres_table_name(ets_table)
    sql = "SELECT k, v FROM #{table};"

    case postgres_query(conn, sql, []) do
      {:ok, %{rows: rows}} ->
        Enum.each(rows, fn
          [key_bin, value_bin] when is_binary(key_bin) and is_binary(value_bin) ->
            key = :erlang.binary_to_term(key_bin)
            value = :erlang.binary_to_term(value_bin)
            :ets.insert(ets_table, {key, value})

          _ ->
            :ok
        end)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp maybe_persist(_table, _key, _value, :ets, _backend_state), do: :ok

  defp maybe_persist(table, key, value, :dets, %{tables: dets_tables}) do
    case Map.get(dets_tables, table) do
      nil ->
        :ok

      dets_table ->
        :ok = :dets.insert(dets_table, {key, value})
    end
  rescue
    _ -> :ok
  end

  defp maybe_persist(table, key, value, :sqlite, %{path: path}) do
    table_name = sqlite_table_name(table)
    k_hex = key |> :erlang.term_to_binary() |> Base.encode16(case: :upper)
    v_hex = value |> :erlang.term_to_binary() |> Base.encode16(case: :upper)
    sql = "INSERT OR REPLACE INTO #{table_name}(k, v) VALUES (X'#{k_hex}', X'#{v_hex}');"
    _ = run_sql(path, sql)
    :ok
  rescue
    _ -> :ok
  end

  defp maybe_persist(table, key, value, :postgres, %{conn: conn}) do
    table_name = postgres_table_name(table)
    key_bin = :erlang.term_to_binary(key)
    value_bin = :erlang.term_to_binary(value)

    sql = """
    INSERT INTO #{table_name}(k, v) VALUES($1, $2)
    ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
    """

    _ = postgres_query(conn, sql, [key_bin, value_bin])
    :ok
  rescue
    _ -> :ok
  end

  defp close_backend(:dets, %{tables: dets_tables}) do
    Enum.each(dets_tables, fn {_name, table} ->
      _ = :dets.sync(table)
      _ = :dets.close(table)
    end)
  end

  defp close_backend(:postgres, %{conn: conn}) when is_pid(conn) do
    _ = GenServer.stop(conn, :normal, 1_000)
    :ok
  rescue
    _ -> :ok
  end

  defp close_backend(_storage, _backend_state), do: :ok

  defp init_sqlite(path) do
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

  defp sqlite_table_name(:scr_tasks), do: "scr_tasks"
  defp sqlite_table_name(:scr_memory), do: "scr_memory"
  defp sqlite_table_name(:scr_agent_states), do: "scr_agent_states"

  defp normalize_sqlite_path(path) when is_binary(path) do
    if Path.extname(path) == "" do
      Path.join(path, "scr_memory.sqlite3")
    else
      path
    end
  end

  defp init_postgres(cfg) do
    if Code.ensure_loaded?(Postgrex) do
      postgres_cfg = Keyword.get(cfg, :postgres, [])
      opts = postgres_opts(postgres_cfg)

      if opts == [] do
        {:error, :missing_postgres_config}
      else
        case Postgrex.start_link(opts) do
          {:ok, conn} ->
            case init_postgres_schema(conn) do
              :ok -> {:ok, %{conn: conn}}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      {:error, :postgrex_not_available}
    end
  end

  defp postgres_opts(cfg) do
    url = Keyword.get(cfg, :url)

    if is_binary(url) and url != "" do
      [url: url]
    else
      host = Keyword.get(cfg, :hostname)
      user = Keyword.get(cfg, :username)
      db = Keyword.get(cfg, :database)

      if is_binary(host) and host != "" and is_binary(user) and user != "" and is_binary(db) and
           db !=
             "" do
        [
          hostname: host,
          username: user,
          password: Keyword.get(cfg, :password),
          database: db,
          port: Keyword.get(cfg, :port, 5432),
          ssl: Keyword.get(cfg, :ssl, false)
        ]
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      else
        []
      end
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

  defp postgres_table_name(:scr_tasks), do: "scr_tasks"
  defp postgres_table_name(:scr_memory), do: "scr_memory"
  defp postgres_table_name(:scr_agent_states), do: "scr_agent_states"

  defp postgres_query(conn, sql, params) do
    Postgrex.query(conn, sql, params)
  rescue
    _ -> {:error, :postgres_query_failed}
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

  # Query API

  def get_task(task_id) do
    case safe_lookup(:scr_tasks, task_id) do
      [{^task_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
      :no_table -> {:error, :unavailable}
    end
  end

  def get_result(task_id) do
    case safe_lookup(:scr_memory, task_id) do
      [{^task_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
      :no_table -> {:error, :unavailable}
    end
  end

  def get_agent_state(agent_id) do
    case safe_lookup(:scr_agent_states, agent_id) do
      [{^agent_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
      :no_table -> {:error, :unavailable}
    end
  end

  def list_tasks do
    safe_tab2list(:scr_tasks)
    |> Enum.map(fn {id, _data} -> id end)
  end

  def list_agents do
    safe_tab2list(:scr_agent_states)
    |> Enum.map(fn {id, _data} -> id end)
  end

  # New: LLM-powered memory operations

  @doc """
  Summarize stored memories using LLM.
  Useful for reducing context window size.
  """
  def summarize_with_llm(data) when is_list(data) do
    data_str = Enum.map_join(data, "\n---\n", &inspect/1)

    prompt = """
    You are a memory consolidation assistant. Summarize the following information
    into a concise summary that captures the key points.

    Information to summarize:
    #{data_str}

    Provide a single paragraph summary (2-4 sentences).
    """

    case Client.complete(prompt, temperature: 0.5, max_tokens: 512) do
      {:ok, %{content: summary}} ->
        %{summary: summary, source: :llm}

      {:error, _} ->
        %{summary: "Summary unavailable", source: :fallback}
    end
  end

  def summarize_with_llm(data) when is_map(data) do
    summarize_with_llm([data])
  end

  def summarize_with_llm(_), do: %{summary: "No data to summarize", source: :fallback}

  @doc """
  Retrieve relevant memories based on a query.
  Uses LLM to rank memory relevance.
  """
  def retrieve_relevant_memories(query) do
    # Get all stored data
    all_tasks = :ets.tab2list(:scr_tasks)
    all_results = :ets.tab2list(:scr_memory)

    # Combine all memories
    all_memories =
      Enum.map(all_tasks ++ all_results, fn {id, data} ->
        %{id: id, data: data}
      end)

    if length(all_memories) == 0 do
      []
    else
      # Use LLM to find relevant memories
      prompt = """
      Given the query: "#{query}"

      Rate the relevance of each memory item on a scale of 0-1.
      Return ONLY a JSON array of relevance scores in the same order as the memories.

      Memories (in order):
      #{Enum.map_join(all_memories, "\n", fn m -> inspect(m.data) end)}
      """

      case Client.complete(prompt, temperature: 0.2, max_tokens: 512) do
        {:ok, %{content: response}} ->
          # Try to parse the scores
          parse_relevance_scores(response, all_memories)

        {:error, _} ->
          # Fallback: return all memories
          all_memories
      end
    end
  end

  defp parse_relevance_scores(response, memories) do
    # Try to extract scores from LLM response
    # This is a simplified implementation
    scores =
      response
      |> String.split(["[", "]", ",", "\n"])
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn s ->
        case Float.parse(s) do
          {_num, ""} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn s ->
        {num, _} = Float.parse(s)
        num
      end)

    # Combine memories with scores and sort by relevance
    Enum.zip(memories, scores)
    |> Enum.filter(fn {_m, score} -> score > 0.3 end)
    |> Enum.sort_by(fn {_m, score} -> -score end)
    |> Enum.map(fn {m, _score} -> m end)
  rescue
    # Fallback to returning all memories
    _ -> memories
  end

  defp safe_lookup(table, key) do
    if :ets.whereis(table) == :undefined do
      :no_table
    else
      :ets.lookup(table, key)
    end
  end

  defp safe_tab2list(table) do
    if :ets.whereis(table) == :undefined do
      []
    else
      :ets.tab2list(table)
    end
  end
end
