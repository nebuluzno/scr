defmodule SCRWeb.ToolController do
  use SCRWeb, :controller

  def index(conn, _params) do
    tool_details =
      SCR.Tools.Registry.list_tools(descriptors: true)
      |> Enum.map(fn descriptor ->
        %{
          name: descriptor.name,
          description: descriptor.description,
          schema: descriptor.schema,
          source: descriptor.source,
          server: descriptor.server
        }
      end)

    render(conn, :index, tools: tool_details)
  end

  def execute(conn, %{"tool" => tool_name, "params" => params}) do
    result =
      case SCR.Tools.Registry.execute_tool(tool_name, params) do
        {:ok, payload} -> %{success: true, result: payload}
        {:error, reason} -> %{success: false, error: inspect(reason)}
      end

    json(conn, result)
  end
end
