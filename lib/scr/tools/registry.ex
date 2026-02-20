defmodule SCR.Tools.Registry do
  @moduledoc """
  Unified registry for native and MCP-backed tools.
  """

  use GenServer
  require Logger

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.Policy
  alias SCR.Tools.RateLimiter
  alias SCR.Tools.ToolDescriptor
  alias SCR.Trace

  @name __MODULE__

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    default_tools = Keyword.get(opts, :default_tools, [])
    GenServer.start_link(__MODULE__, default_tools, name: name)
  end

  def register_tool(module) when is_atom(module) do
    GenServer.call(@name, {:register, module})
  end

  def unregister_tool(tool_name) when is_binary(tool_name) do
    GenServer.call(@name, {:unregister, tool_name})
  end

  def list_tools(opts \\ []) do
    GenServer.call(@name, {:list_tools, opts})
  end

  def get_tool(tool_name) do
    GenServer.call(@name, {:get_tool, tool_name})
  end

  def get_tool_descriptor(tool_name) do
    GenServer.call(@name, {:get_tool_descriptor, tool_name})
  end

  def get_tool_definitions(ctx \\ nil) do
    ctx = normalize_context(ctx)
    GenServer.call(@name, {:get_tool_definitions, ctx})
  end

  def execute_tool(tool_name, params) do
    execute_tool(tool_name, params, ExecutionContext.new())
  end

  def execute_tool(tool_name, params, %ExecutionContext{} = ctx) do
    GenServer.call(@name, {:execute, tool_name, params, ctx})
  end

  def has_tool?(tool_name) do
    GenServer.call(@name, {:has_tool, tool_name})
  end

  # Server callbacks

  @impl true
  def init(default_tools) when is_list(default_tools) do
    state = %{
      native_tools: %{},
      mcp_tools: %{}
    }

    state =
      Enum.reduce(default_tools, state, fn tool_module, acc_state ->
        case register_tool_in_state(tool_module, acc_state) do
          {:ok, _name, new_state} -> new_state
          _ -> acc_state
        end
      end)

    {:ok, state}
  end

  @impl true
  def handle_call({:register, module}, _from, state) do
    case register_tool_in_state(module, state) do
      {:ok, tool_name, new_state} ->
        Logger.info("Registered native tool: #{tool_name}")
        {:reply, {:ok, tool_name}, new_state}

      {:error, :already_registered} ->
        Logger.warning("Tool #{apply(module, :name, [])} already registered, skipping")
        {:reply, {:error, :already_registered}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister, tool_name}, _from, state) do
    case Map.fetch(state.native_tools, tool_name) do
      {:ok, %ToolDescriptor{module: module}} ->
        if function_exported?(module, :on_unregister, 0), do: apply(module, :on_unregister, [])

        new_state = %{state | native_tools: Map.delete(state.native_tools, tool_name)}
        Logger.info("Unregistered native tool: #{tool_name}")
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_tools, opts}, _from, state) do
    state = sync_mcp_tools(state)

    ctx =
      opts
      |> Keyword.get(:context, ExecutionContext.new())
      |> normalize_context()

    descriptors = all_descriptors(state)
    filtered = Policy.filter_tools(descriptors, ctx)

    if Keyword.get(opts, :descriptors, false) do
      {:reply, filtered, state}
    else
      names =
        filtered
        |> Enum.map(& &1.name)
        |> Enum.uniq()
        |> Enum.sort()

      {:reply, names, state}
    end
  end

  @impl true
  def handle_call({:get_tool, tool_name}, _from, state) do
    state = sync_mcp_tools(state)

    result =
      case Map.get(state.native_tools, tool_name) do
        %ToolDescriptor{module: module} -> {:ok, module}
        _ -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_tool_descriptor, tool_name}, _from, state) do
    state = sync_mcp_tools(state)
    descriptor = resolve_descriptor(tool_name, ExecutionContext.new(), state)

    case descriptor do
      nil -> {:reply, {:error, :not_found}, state}
      d -> {:reply, {:ok, d}, state}
    end
  end

  @impl true
  def handle_call({:get_tool_definitions, ctx}, _from, state) do
    state = sync_mcp_tools(state)

    definitions =
      state
      |> all_descriptors()
      |> Policy.filter_tools(ctx)
      |> choose_preferred_descriptors(ctx)
      |> Enum.map(&to_openai_tool_definition/1)

    {:reply, definitions, state}
  end

  @impl true
  def handle_call({:execute, tool_name, params, ctx}, _from, state) do
    started_at = System.monotonic_time(:millisecond)
    state = sync_mcp_tools(state)
    normalized_params = normalize_params(params)
    Trace.put_metadata(ctx)
    Logger.info("tool.execute.start name=#{tool_name}")

    with {:ok, descriptor} <- fetch_descriptor(tool_name, ctx, state),
         :ok <- Policy.authorize(descriptor, normalized_params, ctx),
         :ok <- enforce_rate_limit(descriptor.name),
         {:ok, response} <- execute_with_descriptor(descriptor, normalized_params, ctx),
         :ok <- Policy.validate_result_payload(response, ctx) do
      Logger.info("tool.execute.ok name=#{tool_name}")
      emit_tool_execute_event(tool_name, descriptor.source, :ok, started_at, ctx)
      {:reply, {:ok, response}, state}
    else
      {:error, :mcp_unavailable} ->
        Logger.warning("tool.execute.mcp_unavailable name=#{tool_name}")

        if fallback_to_native_enabled?() do
          case fallback_native(tool_name, normalized_params, ctx, state) do
            {:ok, response} ->
              emit_tool_execute_event(tool_name, :native, :ok, started_at, ctx)
              {:reply, {:ok, response}, state}

            {:error, reason} ->
              emit_tool_execute_event(tool_name, :mcp, reason, started_at, ctx)
              {:reply, {:error, reason}, state}
          end
        else
          emit_tool_execute_event(tool_name, :mcp, :mcp_unavailable, started_at, ctx)
          {:reply, {:error, :mcp_unavailable}, state}
        end

      {:error, reason} ->
        Logger.warning("tool.execute.error name=#{tool_name} reason=#{inspect(reason)}")

        emit_tool_execute_event(
          tool_name,
          resolve_source_hint(tool_name, ctx, state),
          reason,
          started_at,
          ctx
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:has_tool, tool_name}, _from, state) do
    state = sync_mcp_tools(state)

    has_tool =
      Map.has_key?(state.native_tools, tool_name) or
        Map.has_key?(state.mcp_tools, tool_name)

    {:reply, has_tool, state}
  end

  defp register_tool_in_state(module, state) do
    case apply(module, :name, []) do
      tool_name when is_binary(tool_name) ->
        if Map.has_key?(state.native_tools, tool_name) do
          {:error, :already_registered}
        else
          if function_exported?(module, :on_register, 0), do: apply(module, :on_register, [])

          descriptor = %ToolDescriptor{
            name: tool_name,
            source: :native,
            module: module,
            description: apply(module, :description, []),
            schema: normalize_schema(apply(module, :parameters_schema, [])),
            timeout_ms: 10_000,
            tags: ["native"],
            safety_level: :standard
          }

          new_state = put_in(state.native_tools[tool_name], descriptor)
          {:ok, tool_name, new_state}
        end

      _ ->
        {:error, :invalid_tool_name}
    end
  end

  defp execute_with_descriptor(%ToolDescriptor{source: :native} = descriptor, params, ctx) do
    started_at = System.monotonic_time(:millisecond)

    case apply(descriptor.module, :execute, [params]) do
      {:ok, result} ->
        latency = System.monotonic_time(:millisecond) - started_at
        {:ok, wrap_result(result, descriptor, latency, ctx)}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:ok, wrap_result(other, descriptor, 0, ctx)}
    end
  rescue
    e ->
      {:error, {:execution_error, Exception.message(e)}}
  end

  defp execute_with_descriptor(%ToolDescriptor{source: :mcp} = descriptor, params, ctx) do
    started_at = System.monotonic_time(:millisecond)

    case SCR.Tools.MCP.ServerManager.call(descriptor.server, descriptor.name, params, ctx) do
      {:ok, result} ->
        latency = System.monotonic_time(:millisecond) - started_at
        {:ok, wrap_result(result, descriptor, latency, ctx)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wrap_result(result, descriptor, latency_ms, ctx) do
    %{
      data: result,
      meta: %{
        source: descriptor.source,
        tool: descriptor.name,
        server: descriptor.server,
        latency_ms: latency_ms,
        trace_id: ctx.trace_id,
        task_id: ctx.task_id,
        parent_task_id: ctx.parent_task_id,
        subtask_id: ctx.subtask_id,
        agent_id: ctx.agent_id
      }
    }
  end

  defp fallback_native(tool_name, params, ctx, state) do
    case Map.get(state.native_tools, tool_name) do
      nil -> {:error, :mcp_unavailable}
      descriptor -> execute_with_descriptor(descriptor, params, ctx)
    end
  end

  defp fetch_descriptor(tool_name, %ExecutionContext{} = ctx, state) do
    case resolve_descriptor(tool_name, ctx, state) do
      nil -> {:error, :not_found}
      descriptor -> {:ok, descriptor}
    end
  end

  defp resolve_descriptor(tool_name, %ExecutionContext{source: :mcp}, state) do
    case Map.get(state.mcp_tools, tool_name, []) do
      [first | _] -> first
      [] -> nil
    end
  end

  defp resolve_descriptor(tool_name, %ExecutionContext{source: :native}, state) do
    Map.get(state.native_tools, tool_name)
  end

  defp resolve_descriptor(tool_name, _ctx, state) do
    Map.get(state.native_tools, tool_name) ||
      case Map.get(state.mcp_tools, tool_name, []) do
        [first | _] -> first
        [] -> nil
      end
  end

  defp all_descriptors(state) do
    native = Map.values(state.native_tools)
    mcp = state.mcp_tools |> Map.values() |> List.flatten()
    native ++ mcp
  end

  defp choose_preferred_descriptors(descriptors, ctx) do
    descriptors
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {_name, group} ->
      case ctx.source do
        :mcp ->
          Enum.find(group, &(&1.source == :mcp)) || Enum.find(group, &(&1.source == :native))

        :native ->
          Enum.find(group, &(&1.source == :native)) || Enum.find(group, &(&1.source == :mcp))

        _ ->
          Enum.find(group, &(&1.source == :native)) || Enum.find(group, &(&1.source == :mcp))
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp to_openai_tool_definition(%ToolDescriptor{source: :native, module: module})
       when not is_nil(module) do
    apply(module, :to_openai_format, [])
  end

  defp to_openai_tool_definition(%ToolDescriptor{} = descriptor) do
    %{
      type: "function",
      function: %{
        name: descriptor.name,
        description: descriptor.description,
        parameters: normalize_schema(descriptor.schema)
      }
    }
  end

  defp normalize_context(%ExecutionContext{} = ctx), do: ctx
  defp normalize_context(ctx) when is_map(ctx), do: ExecutionContext.new(ctx)
  defp normalize_context(_), do: ExecutionContext.new()

  defp normalize_schema(schema) when is_map(schema), do: schema
  defp normalize_schema(_), do: %{"type" => "object", "properties" => %{}}

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), normalize_value(v)}
      {k, v} -> {k, normalize_value(v)}
    end)
  end

  defp normalize_params(_), do: %{}

  defp normalize_value(value) when is_map(value), do: normalize_params(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp sync_mcp_tools(state) do
    if Process.whereis(SCR.Tools.MCP.ServerManager) do
      mcp_descriptors = SCR.Tools.MCP.ServerManager.list_all_tools()
      mcp_tools = Enum.group_by(mcp_descriptors, & &1.name)
      %{state | mcp_tools: mcp_tools}
    else
      state
    end
  end

  defp fallback_to_native_enabled? do
    tools_cfg = SCR.ConfigCache.get(:tools, [])
    Keyword.get(tools_cfg, :fallback_to_native, false)
  end

  defp enforce_rate_limit(tool_name) do
    cfg = SCR.ConfigCache.get(:tool_rate_limit, [])

    if Keyword.get(cfg, :enabled, true) and Process.whereis(SCR.Tools.RateLimiter) do
      {max_calls, window_ms} = tool_rate_limit_settings(tool_name, cfg)
      RateLimiter.check_rate(tool_name, max_calls, window_ms)
    else
      :ok
    end
  end

  defp tool_rate_limit_settings(tool_name, cfg) do
    per_tool = Keyword.get(cfg, :per_tool, %{})

    case Map.get(per_tool, tool_name) do
      %{max_calls: max_calls, window_ms: window_ms} ->
        {max_calls, window_ms}

      _ ->
        {Keyword.get(cfg, :default_max_calls, 60), Keyword.get(cfg, :default_window_ms, 60_000)}
    end
  end

  defp emit_tool_execute_event(tool_name, source, result, started_at_ms, ctx) do
    duration_ms = max(System.monotonic_time(:millisecond) - started_at_ms, 0)

    :telemetry.execute(
      [:scr, :tools, :execute],
      %{count: 1, duration_ms: duration_ms},
      %{
        tool: tool_name,
        source: source || :unknown,
        result: telemetry_result(result),
        agent_id: Map.get(ctx, :agent_id, "unknown"),
        task_id: Map.get(ctx, :task_id, "unknown")
      }
    )
  end

  defp resolve_source_hint(_tool_name, %ExecutionContext{source: :mcp}, _state), do: :mcp
  defp resolve_source_hint(_tool_name, %ExecutionContext{source: :native}, _state), do: :native

  defp resolve_source_hint(tool_name, _ctx, state) do
    cond do
      Map.has_key?(state.native_tools, tool_name) -> :native
      Map.has_key?(state.mcp_tools, tool_name) -> :mcp
      true -> :unknown
    end
  end

  defp telemetry_result(:ok), do: :ok
  defp telemetry_result(:mcp_unavailable), do: :mcp_unavailable
  defp telemetry_result(:rate_limited), do: :rate_limited
  defp telemetry_result(:timeout), do: :timeout
  defp telemetry_result(:invalid_params), do: :invalid_params
  defp telemetry_result(:tool_not_allowed), do: :tool_not_allowed
  defp telemetry_result(:not_found), do: :not_found
  defp telemetry_result({:execution_error, _}), do: :execution_error
  defp telemetry_result({:payload_too_large, _}), do: :payload_too_large
  defp telemetry_result({:invalid_params, _}), do: :invalid_params
  defp telemetry_result(_), do: :error
end
