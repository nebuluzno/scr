defmodule Mix.Tasks.Scr.Mcp.Smoke do
  @shortdoc "Runs an MCP smoke test against configured dev MCP server(s)"

  @moduledoc """
  MCP smoke test for development.

  Validates:
  1. MCP manager is running
  2. At least one healthy server is present
  3. Server returns at least one tool via tools/list
  4. Optional: call one tool

  Usage:

      mix scr.mcp.smoke
      mix scr.mcp.smoke --server github
      mix scr.mcp.smoke --server github --tool search_issues --args-json '{"query":"bug"}'

  Notes:
  - This task requires MCP to be enabled in config (dev env), typically via env vars.
  - It is intended as a local integration smoke check, not a CI test.
  """

  use Mix.Task

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.MCP.ServerManager

  @switches [server: :string, tool: :string, args_json: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    servers = ServerManager.list_servers()

    if servers == [] do
      Mix.raise("No MCP servers available. Ensure MCP is enabled in dev config.")
    end

    healthy = Enum.filter(servers, & &1.healthy)

    if healthy == [] do
      Mix.raise("No healthy MCP servers. Check MCP server command/args and restart app.")
    end

    selected_server = opts[:server] || hd(healthy).name

    unless Enum.any?(healthy, &(&1.name == selected_server)) do
      Mix.raise("Selected server '#{selected_server}' is not healthy or not found.")
    end

    {:ok, tools} = ServerManager.list_tools(selected_server)

    if tools == [] do
      Mix.raise("Server '#{selected_server}' returned zero tools.")
    end

    Mix.shell().info("MCP smoke ok: server='#{selected_server}', tools=#{length(tools)}")

    case opts[:tool] do
      nil ->
        :ok

      tool_name ->
        params = decode_args(opts[:args_json] || "{}")
        ctx = ExecutionContext.new(%{mode: :demo, trace_id: "mcp-smoke"})

        case ServerManager.call(selected_server, tool_name, params, ctx) do
          {:ok, result} ->
            Mix.shell().info("tool call ok: #{tool_name}")
            Mix.shell().info("result: #{inspect(result)}")

          {:error, reason} ->
            Mix.raise("tool call failed for '#{tool_name}': #{inspect(reason)}")
        end
    end
  end

  defp decode_args(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      {:ok, _other} -> Mix.raise("--args-json must decode to a JSON object")
      {:error, reason} -> Mix.raise("Invalid --args-json: #{inspect(reason)}")
    end
  end
end
