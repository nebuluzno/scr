defmodule SCR.Tools.Registry do
  @moduledoc """
  Registry for managing available tools in SCR.
  
  Agents can discover and call tools through this registry.
  Tools are registered when the application starts or dynamically at runtime.
  """

  use GenServer
  require Logger

  @name __MODULE__

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    default_tools = Keyword.get(opts, :default_tools, [])
    GenServer.start_link(__MODULE__, default_tools, name: name)
  end

  @doc """
  Registers a tool module with the registry.
  """
  def register_tool(module) when is_atom(module) do
    GenServer.call(@name, {:register, module})
  end

  @doc """
  Unregisters a tool from the registry.
  """
  def unregister_tool(tool_name) when is_binary(tool_name) do
    GenServer.call(@name, {:unregister, tool_name})
  end

  @doc """
  Lists all registered tools.
  """
  def list_tools do
    GenServer.call(@name, :list_tools)
  end

  @doc """
  Gets a tool by name.
  """
  def get_tool(tool_name) do
    GenServer.call(@name, {:get_tool, tool_name})
  end

  @doc """
  Gets all tool definitions in OpenAI function calling format.
  """
  def get_tool_definitions do
    GenServer.call(@name, :get_tool_definitions)
  end

  @doc """
  Executes a tool by name with the given parameters.
  """
  def execute_tool(tool_name, params) do
    GenServer.call(@name, {:execute, tool_name, params})
  end

  @doc """
  Checks if a tool with the given name exists.
  """
  def has_tool?(tool_name) do
    GenServer.call(@name, {:has_tool, tool_name})
  end

  # Server Callbacks

  @impl true
  def init(default_tools) when is_list(default_tools) do
    state = %{
      tools: %{}
    }
    
    # Register default tools if provided
    state = Enum.reduce(default_tools, state, fn tool_module, acc_state ->
      case register_tool_in_state(tool_module, acc_state) do
        {:ok, _name, new_state} -> new_state
        _ -> acc_state
      end
    end)
    
    {:ok, state}
  end
  
  defp register_tool_in_state(module, state) do
    case apply(module, :name, []) do
      tool_name when is_binary(tool_name) ->
        if Map.has_key?(state.tools, tool_name) do
          {:error, :already_registered}
        else
          # Call on_register callback if it exists
          if function_exported?(module, :on_register, 0) do
            apply(module, :on_register, [])
          end
          
          new_state = put_in(state.tools[tool_name], module)
          Logger.info("Registered tool: #{tool_name}")
          {:ok, tool_name, new_state}
        end
      
      _ ->
        {:error, :invalid_tool_name}
    end
  end

  @impl true
  def handle_call({:register, module}, _from, state) do
    case apply(module, :name, []) do
      tool_name when is_binary(tool_name) ->
        if Map.has_key?(state.tools, tool_name) do
          Logger.warning("Tool #{tool_name} already registered, skipping")
          {:reply, {:error, :already_registered}, state}
        else
          # Call on_register callback if it exists
          if function_exported?(module, :on_register, 0) do
            apply(module, :on_register, [])
          end
          
          new_state = put_in(state.tools[tool_name], module)
          Logger.info("Registered tool: #{tool_name}")
          {:reply, {:ok, tool_name}, new_state}
        end
      
      _ ->
        {:reply, {:error, :invalid_tool_name}, state}
    end
  end

  @impl true
  def handle_call({:unregister, tool_name}, _from, state) do
    case Map.fetch(state.tools, tool_name) do
      {:ok, module} ->
        # Call on_unregister callback if it exists
        if function_exported?(module, :on_unregister, 0) do
          apply(module, :on_unregister, [])
        end
        
        new_state = Map.delete(state.tools, tool_name)
        Logger.info("Unregistered tool: #{tool_name}")
        {:reply, :ok, new_state}
      
      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    tools = 
      state.tools
      |> Map.keys()
      |> Enum.sort()
    
    {:reply, tools, state}
  end

  @impl true
  def handle_call({:get_tool, tool_name}, _from, state) do
    result = Map.fetch(state.tools, tool_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_tool_definitions, _from, state) do
    definitions = 
      state.tools
      |> Map.values()
      |> Enum.map(fn module ->
        apply(module, :to_openai_format, [])
      end)
    
    {:reply, definitions, state}
  end

  @impl true
  def handle_call({:execute, tool_name, params}, _from, state) do
    case Map.fetch(state.tools, tool_name) do
      {:ok, module} ->
        result = apply(module, :execute, [params])
        {:reply, result, state}
      
      :error ->
        {:reply, {:error, "Tool #{tool_name} not found"}, state}
    end
  end

  @impl true
  def handle_call({:has_tool, tool_name}, _from, state) do
    {:reply, Map.has_key?(state.tools, tool_name), state}
  end
end
