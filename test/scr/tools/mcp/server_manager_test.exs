defmodule SCR.Tools.MCP.ServerManagerTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.MCP.ServerManager

  setup_all do
    {:ok, _} = Application.ensure_all_started(:scr)
    :ok
  end

  setup do
    original_state = :sys.get_state(ServerManager)

    on_exit(fn ->
      :sys.replace_state(ServerManager, fn _ -> original_state end)
    end)

    :ok
  end

  test "returns mcp_unavailable when server connection is nil" do
    :sys.replace_state(ServerManager, fn state ->
      %{
        state
        | servers: %{
            "broken" => %{
              conn: nil,
              healthy: false,
              failures: 1,
              circuit_open_until: 0,
              call_timeout_ms: 1000,
              tools: [],
              config: %{}
            }
          }
      }
    end)

    ctx = ExecutionContext.new(%{mode: :strict, trace_id: "trace-1"})

    assert {:error, :mcp_unavailable} = ServerManager.call("broken", "tool_x", %{}, ctx)
  end
end
