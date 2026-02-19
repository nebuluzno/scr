defmodule SCRWeb.ToolController do
  use SCRWeb, :controller

  def index(conn, _params) do
    tools = SCR.Tools.Registry.list_tools()
    
    # Get details for each tool
    tool_details = Enum.map(tools, fn tool_name ->
      case SCR.Tools.Registry.get_tool(tool_name) do
        {:ok, module} ->
          schema = if function_exported?(module, :parameters_schema, 0) do
            apply(module, :parameters_schema, [])
          else
            %{}
          end
          
          %{
            name: tool_name,
            description: apply(module, :description, []),
            schema: schema,
            module: module
          }
        _ ->
          %{name: tool_name, description: "Unknown", module: nil, schema: %{}}
      end
    end)
    
    render(conn, :index, tools: tool_details)
  end

  def execute(conn, %{"tool" => tool_name, "params" => params}) do
    result = case SCR.Tools.Registry.get_tool(tool_name) do
      {:ok, module} ->
        try do
          # Convert string keys to atoms if needed
          parsed_params = for {k, v} <- params, into: %{} do
            {String.to_atom(k), v}
          end
          apply(module, :execute, [parsed_params])
        rescue
          e -> %{success: false, error: "Execution error: #{inspect(e)}"}
        end
      {:error, _} ->
        %{success: false, error: "Tool not found: #{tool_name}"}
    end

    json(conn, result)
  end
end
