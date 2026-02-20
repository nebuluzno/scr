defmodule SCR.Tools.MCP.Client do
  @moduledoc """
  Minimal MCP stdio JSON-RPC client with framing fallback.
  """

  @type conn :: %{
          port: port(),
          next_id: pos_integer(),
          buffer: binary(),
          default_timeout_ms: pos_integer(),
          server_name: String.t(),
          mode: :framed | :ndjson
        }

  @spec initialize(map()) :: {:ok, conn()} | {:error, term()}
  def initialize(%{name: name, command: command} = config) do
    args = Map.get(config, :args, [])
    env = Map.get(config, :env, %{})
    cwd = Map.get(config, :cwd)
    timeout = Map.get(config, :startup_timeout_ms, 5_000)

    with {:ok, executable} <- resolve_executable(command),
         {:ok, port} <- open_port(executable, args, env, cwd) do
      conn = %{
        port: port,
        next_id: 1,
        buffer: "",
        default_timeout_ms: timeout,
        server_name: name,
        mode: :framed
      }

      init_params = %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "scr", "version" => "0.3.0-alpha"}
      }

      case rpc(conn, "initialize", init_params) do
        {:ok, _result, conn2} ->
          _ = notify(conn2, "notifications/initialized", %{})
          {:ok, conn2}

        {:error, :timeout, _conn2} ->
          Port.close(port)

          with {:ok, ndjson_port} <- open_port(executable, args, env, cwd) do
            ndjson_conn = %{
              port: ndjson_port,
              next_id: 1,
              buffer: "",
              default_timeout_ms: timeout,
              server_name: name,
              mode: :ndjson
            }

            case rpc(ndjson_conn, "initialize", init_params) do
              {:ok, _result, conn3} ->
                _ = notify(conn3, "notifications/initialized", %{})
                {:ok, conn3}

              {:error, reason, _conn3} ->
                Port.close(ndjson_port)
                {:error, reason}
            end
          end

        {:error, reason, _conn2} ->
          Port.close(port)
          {:error, reason}
      end
    end
  end

  @spec list_tools(conn()) :: {:ok, [map()], conn()} | {:error, term(), conn()}
  def list_tools(conn) do
    case rpc(conn, "tools/list", %{}) do
      {:ok, %{"tools" => tools}, conn2} when is_list(tools) -> {:ok, tools, conn2}
      {:ok, _other, conn2} -> {:ok, [], conn2}
      {:error, reason, conn2} -> {:error, reason, conn2}
    end
  end

  @spec call_tool(conn(), String.t(), map(), pos_integer()) ::
          {:ok, map(), conn()} | {:error, term(), conn()}
  def call_tool(conn, tool, params, timeout_ms) do
    rpc(conn, "tools/call", %{"name" => tool, "arguments" => params}, timeout_ms)
  end

  @spec close(conn()) :: :ok
  def close(%{port: port}) do
    Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp resolve_executable(command) do
    case System.find_executable(command) do
      nil -> {:error, {:command_not_found, command}}
      path -> {:ok, path}
    end
  end

  defp open_port(executable, args, env, cwd) do
    opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      args: args,
      env: Enum.map(env, fn {k, v} -> {to_charlist(to_string(k)), to_charlist(to_string(v))} end)
    ]

    opts = if is_binary(cwd), do: [{:cd, cwd} | opts], else: opts

    {:ok, Port.open({:spawn_executable, executable}, opts)}
  rescue
    e -> {:error, {:failed_to_open_port, Exception.message(e)}}
  end

  defp notify(conn, method, params) do
    payload = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    send_message(conn, payload)
  end

  defp rpc(conn, method, params, timeout_ms \\ nil) do
    id = conn.next_id

    payload = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    }

    timeout = timeout_ms || conn.default_timeout_ms
    send_message(conn, payload)

    conn
    |> Map.put(:next_id, id + 1)
    |> await_response(id, timeout)
  end

  defp send_message(%{port: port, mode: :framed}, payload) do
    body = Jason.encode!(payload)
    header = "Content-Length: #{byte_size(body)}\r\n\r\n"
    Port.command(port, header <> body)
  end

  defp send_message(%{port: port, mode: :ndjson}, payload) do
    body = Jason.encode!(payload)
    Port.command(port, body <> "\n")
  end

  defp await_response(conn, id, timeout_ms) do
    receive do
      {port, {:data, data}} when port == conn.port ->
        conn = %{conn | buffer: conn.buffer <> data}
        {messages, rest} = extract_messages(conn.buffer, conn.mode, [])
        conn = %{conn | buffer: rest}

        case Enum.find(messages, fn msg -> Map.get(msg, "id") == id end) do
          nil -> await_response(conn, id, timeout_ms)
          msg -> decode_response(msg, conn)
        end

      {port, {:exit_status, status}} when port == conn.port ->
        {:error, {:mcp_server_exited, status}, conn}
    after
      timeout_ms ->
        {:error, :timeout, conn}
    end
  end

  defp decode_response(%{"error" => error}, conn), do: {:error, {:rpc_error, error}, conn}
  defp decode_response(%{"result" => result}, conn), do: {:ok, result, conn}
  defp decode_response(_msg, conn), do: {:error, :invalid_response, conn}

  defp extract_messages(buffer, :framed, acc) do
    case split_one_message(buffer) do
      {:ok, message, rest} -> extract_messages(rest, :framed, [message | acc])
      :incomplete -> {Enum.reverse(acc), buffer}
      {:error, _reason, rest} -> extract_messages(rest, :framed, acc)
    end
  end

  defp extract_messages(buffer, :ndjson, acc) do
    lines = String.split(buffer, "\n")

    {complete, incomplete} =
      if String.ends_with?(buffer, "\n") do
        {lines, ""}
      else
        {Enum.drop(lines, -1), List.last(lines) || ""}
      end

    messages =
      complete
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn line ->
        case Jason.decode(line) do
          {:ok, msg} -> msg
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {Enum.reverse(acc) ++ messages, incomplete}
  end

  defp split_one_message(buffer) do
    with {:ok, header, body_part} <- split_header(buffer),
         {:ok, content_length} <- content_length(header),
         true <- byte_size(body_part) >= content_length do
      <<body::binary-size(content_length), rest::binary>> = body_part

      case Jason.decode(body) do
        {:ok, json} -> {:ok, json, rest}
        {:error, _} -> {:error, :invalid_json, rest}
      end
    else
      false -> :incomplete
      :incomplete -> :incomplete
      {:error, reason} -> {:error, reason, ""}
    end
  end

  defp split_header(buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {idx, _len} ->
        header = binary_part(buffer, 0, idx)
        body = binary_part(buffer, idx + 4, byte_size(buffer) - idx - 4)
        {:ok, header, body}

      :nomatch ->
        :incomplete
    end
  end

  defp content_length(header) do
    lines = String.split(header, "\r\n", trim: true)

    case Enum.find(lines, fn line ->
           String.starts_with?(String.downcase(line), "content-length:")
         end) do
      nil ->
        {:error, :missing_content_length}

      line ->
        value = line |> String.split(":", parts: 2) |> List.last() |> String.trim()

        case Integer.parse(value) do
          {n, ""} when n >= 0 -> {:ok, n}
          _ -> {:error, :invalid_content_length}
        end
    end
  end
end
