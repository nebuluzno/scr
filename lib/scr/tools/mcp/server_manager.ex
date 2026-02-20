defmodule SCR.Tools.MCP.ServerManager do
  @moduledoc """
  MCP server lifecycle manager for local stdio-backed servers.
  """

  use GenServer
  require Logger

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.MCP.Client
  alias SCR.Tools.ToolDescriptor

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Returns current servers with health metadata.
  """
  def list_servers do
    GenServer.call(@name, :list_servers)
  end

  @doc """
  Returns tool descriptors for a server.
  """
  def list_tools(server) do
    GenServer.call(@name, {:list_tools, server})
  end

  @doc """
  Returns all MCP descriptors.
  """
  def list_all_tools do
    GenServer.call(@name, :list_all_tools)
  end

  @doc """
  Call an MCP tool by server + tool name.
  """
  def call(server, tool, params, %ExecutionContext{} = ctx) do
    GenServer.call(@name, {:call, server, tool, params, ctx})
  end

  @impl true
  def init(_opts) do
    tools_cfg = Application.get_env(:scr, :tools, [])
    mcp_cfg = Keyword.get(tools_cfg, :mcp, [])
    enabled = Keyword.get(mcp_cfg, :enabled, false)
    refresh_interval_ms = Keyword.get(mcp_cfg, :refresh_interval_ms, 60_000)

    state = %{
      enabled: enabled,
      refresh_interval_ms: refresh_interval_ms,
      max_failures: Keyword.get(mcp_cfg, :max_failures, 3),
      startup_timeout_ms: Keyword.get(mcp_cfg, :startup_timeout_ms, 5_000),
      call_timeout_ms: Keyword.get(mcp_cfg, :call_timeout_ms, 10_000),
      servers: %{}
    }

    state = if enabled, do: boot_servers(state, mcp_cfg), else: state

    if enabled do
      Process.send_after(self(), :refresh, refresh_interval_ms)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:list_servers, _from, state) do
    payload =
      state.servers
      |> Enum.map(fn {name, server_state} ->
        %{name: name, healthy: server_state.healthy, failures: server_state.failures}
      end)

    {:reply, payload, state}
  end

  @impl true
  def handle_call({:list_tools, server}, _from, state) do
    case Map.fetch(state.servers, server) do
      {:ok, server_state} -> {:reply, {:ok, server_state.tools}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_all_tools, _from, state) do
    tools =
      state.servers
      |> Map.values()
      |> Enum.flat_map(& &1.tools)

    {:reply, tools, state}
  end

  @impl true
  def handle_call({:call, server, tool, params, ctx}, _from, state) do
    now = System.system_time(:millisecond)

    case Map.fetch(state.servers, server) do
      :error ->
        {:reply, {:error, :mcp_unavailable}, state}

      {:ok, %{circuit_open_until: open_until} = _server_state} when open_until > now ->
        {:reply, {:error, :circuit_open}, state}

      {:ok, server_state} ->
        timeout_ms = server_state.call_timeout_ms || state.call_timeout_ms

        case Client.call_tool(server_state.conn, tool, params, timeout_ms) do
          {:ok, result, conn} ->
            server_state = %{
              server_state
              | conn: conn,
                failures: 0,
                healthy: true,
                circuit_open_until: 0
            }

            state = put_in(state.servers[server], server_state)
            {:reply, {:ok, result}, state}

          {:error, reason, conn} ->
            Logger.warning(
              "[tools:mcp] call failed server=#{server} tool=#{tool} " <>
                "reason=#{inspect(reason)} trace_id=#{ctx.trace_id}"
            )

            failures = server_state.failures + 1
            circuit_open_until = if failures >= state.max_failures, do: now + 30_000, else: 0

            server_state = %{
              server_state
              | conn: conn,
                failures: failures,
                healthy: false,
                circuit_open_until: circuit_open_until
            }

            state = put_in(state.servers[server], server_state)
            {:reply, {:error, map_reason(reason)}, state}
        end
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    state = refresh_tools(state)
    Process.send_after(self(), :refresh, state.refresh_interval_ms)
    {:noreply, state}
  end

  defp boot_servers(state, mcp_cfg) do
    servers_cfg = Keyword.get(mcp_cfg, :servers, %{})

    Enum.reduce(servers_cfg, state, fn {name, cfg}, acc ->
      if Map.get(cfg, :enabled, false) do
        server_cfg =
          cfg
          |> Map.put_new(:name, name)
          |> Map.put_new(:startup_timeout_ms, state.startup_timeout_ms)

        case Client.initialize(server_cfg) do
          {:ok, conn} ->
            {tools, conn} = fetch_tools(conn, name)

            server_state = %{
              conn: conn,
              healthy: true,
              failures: 0,
              circuit_open_until: 0,
              call_timeout_ms: Map.get(cfg, :call_timeout_ms, state.call_timeout_ms),
              tools: tools,
              config: cfg
            }

            put_in(acc.servers[name], server_state)

          {:error, reason} ->
            Logger.warning("[tools:mcp] failed to initialize server #{name}: #{inspect(reason)}")

            put_in(acc.servers[name], %{
              conn: nil,
              healthy: false,
              failures: 1,
              circuit_open_until: 0,
              call_timeout_ms: Map.get(cfg, :call_timeout_ms, state.call_timeout_ms),
              tools: [],
              config: cfg
            })
        end
      else
        acc
      end
    end)
  end

  defp refresh_tools(state) do
    Enum.reduce(state.servers, state, fn {name, server_state}, acc ->
      if server_state.conn do
        {tools, conn, healthy} =
          case Client.list_tools(server_state.conn) do
            {:ok, remote_tools, conn2} -> {to_descriptors(name, remote_tools), conn2, true}
            {:error, _reason, conn2} -> {server_state.tools, conn2, false}
          end

        updated = %{server_state | conn: conn, tools: tools, healthy: healthy}
        put_in(acc.servers[name], updated)
      else
        acc
      end
    end)
  end

  defp fetch_tools(conn, server_name) do
    case Client.list_tools(conn) do
      {:ok, remote_tools, conn2} -> {to_descriptors(server_name, remote_tools), conn2}
      {:error, _reason, conn2} -> {[], conn2}
    end
  end

  defp to_descriptors(server_name, tools) do
    Enum.map(tools, fn tool ->
      name = Map.get(tool, "name") || Map.get(tool, :name)
      description = Map.get(tool, "description") || Map.get(tool, :description) || "MCP tool"

      schema =
        Map.get(tool, "inputSchema") ||
          Map.get(tool, :inputSchema) ||
          Map.get(tool, :input_schema) ||
          %{"type" => "object", "properties" => %{}}

      %ToolDescriptor{
        name: name,
        source: :mcp,
        server: server_name,
        description: description,
        schema: schema,
        timeout_ms: 10_000,
        tags: ["mcp"],
        safety_level: :external
      }
    end)
  end

  defp map_reason(:timeout), do: :timeout
  defp map_reason({:rpc_error, _}), do: :mcp_call_failed
  defp map_reason(_), do: :mcp_unavailable
end
