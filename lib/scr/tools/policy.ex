defmodule SCR.Tools.Policy do
  @moduledoc """
  Safety and authorization policy for tool execution.
  """

  require Logger

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.ToolDescriptor

  @default_max_params_bytes 20_000
  @default_max_result_bytes 100_000
  @default_max_code_bytes 4_000
  @default_max_write_bytes 100_000
  @risky_native_tools MapSet.new(["code_execution"])
  @known_profiles [:strict, :balanced, :research]

  @spec authorize(ToolDescriptor.t(), map(), ExecutionContext.t()) :: :ok | {:error, term()}
  def authorize(%ToolDescriptor{} = descriptor, params, %ExecutionContext{} = ctx)
      when is_map(params) do
    cfg = effective_tools_config(ctx)

    with :ok <- validate_payload_size(params, cfg, descriptor),
         :ok <- authorize_mode(descriptor, ctx, cfg),
         :ok <- validate_tool_sandbox(descriptor, params, ctx, cfg) do
      :ok
    end
  end

  @spec filter_tools([ToolDescriptor.t()], ExecutionContext.t()) :: [ToolDescriptor.t()]
  def filter_tools(descriptors, %ExecutionContext{} = ctx) do
    cfg = effective_tools_config(ctx)

    Enum.filter(descriptors, fn descriptor ->
      case authorize_mode(descriptor, ctx, cfg) do
        :ok -> true
        _ -> false
      end
    end)
  end

  @doc """
  Returns currently active policy profile.
  """
  def current_profile do
    tools_config()
    |> Keyword.get(:policy_profile, :strict)
    |> normalize_profile()
  end

  @doc """
  Updates active policy profile at runtime.
  """
  def set_profile(profile) when profile in @known_profiles do
    tools_cfg = Application.get_env(:scr, :tools, [])
    next = Keyword.put(tools_cfg, :policy_profile, profile)
    Application.put_env(:scr, :tools, next)
    _ = SCR.ConfigCache.refresh(:tools)
    :ok
  end

  def set_profile(_), do: {:error, :invalid_profile}

  @doc """
  Validates the normalized result payload before returning it.
  """
  def validate_result_payload(result, ctx, descriptor \\ nil) do
    cfg = effective_tools_config(ctx)
    max_bytes = max_result_bytes(cfg, descriptor)

    encoded = Jason.encode!(result)

    if byte_size(encoded) > max_bytes do
      {:error, :result_too_large}
    else
      :ok
    end
  rescue
    _ -> {:error, :invalid_result}
  end

  defp authorize_mode(descriptor, %ExecutionContext{mode: :demo} = ctx, cfg) do
    override = tool_override(cfg, descriptor)

    cond do
      tool_disabled?(override) ->
        {:error, :tool_disabled_by_profile}

      descriptor.source == :mcp and not mcp_tool_allowlisted?(descriptor, cfg) ->
        Logger.warning(
          "[tools] demo mode allowing non-allowlisted MCP tool " <>
            "tool=#{descriptor.name} server=#{descriptor.server} trace_id=#{ctx.trace_id}"
        )

        :ok

      true ->
        :ok
    end
  end

  defp authorize_mode(descriptor, %ExecutionContext{mode: :strict}, cfg) do
    strict_native_allowlist = MapSet.new(Keyword.get(cfg, :strict_native_allowlist, []))
    override = tool_override(cfg, descriptor)
    forced_allow = tool_forced_allow?(override)

    cond do
      tool_disabled?(override) ->
        {:error, :tool_disabled_by_profile}

      descriptor.source == :native and
        MapSet.member?(@risky_native_tools, descriptor.name) and
        not MapSet.member?(strict_native_allowlist, descriptor.name) and
          not forced_allow ->
        {:error, :tool_not_allowed}

      descriptor.source == :mcp and not mcp_tool_allowlisted?(descriptor, cfg) and
          not forced_allow ->
        {:error, :tool_not_allowlisted}

      true ->
        :ok
    end
  end

  defp validate_payload_size(params, cfg, descriptor) do
    max_bytes = max_params_bytes(cfg, descriptor)
    encoded = Jason.encode!(params)

    if byte_size(encoded) > max_bytes do
      {:error, :params_too_large}
    else
      :ok
    end
  rescue
    _ -> {:error, :invalid_params}
  end

  defp validate_tool_sandbox(%ToolDescriptor{name: "file_operations"}, params, ctx, cfg) do
    sandbox_cfg = Keyword.get(cfg, :sandbox, [])
    file_cfg = Keyword.get(sandbox_cfg, :file_operations, [])

    operation = Map.get(params, "operation")
    path = Map.get(params, "path", "")
    content = Map.get(params, "content", "")
    max_write_bytes = Keyword.get(file_cfg, :max_write_bytes, @default_max_write_bytes)

    if operation in ["write", "append"] do
      allow_writes =
        case ctx.mode do
          :strict -> Keyword.get(file_cfg, :strict_allow_writes, false)
          _ -> Keyword.get(file_cfg, :demo_allow_writes, true)
        end

      cond do
        not allow_writes ->
          {:error, :write_not_allowed}

        not valid_relative_path?(path) ->
          {:error, :invalid_path}

        byte_size(content) > max_write_bytes ->
          {:error, :write_too_large}

        not allowlisted_write_path?(path, file_cfg) ->
          {:error, :path_not_allowlisted}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp validate_tool_sandbox(%ToolDescriptor{name: "code_execution"}, params, _ctx, cfg) do
    sandbox_cfg = Keyword.get(cfg, :sandbox, [])
    code_cfg = Keyword.get(sandbox_cfg, :code_execution, [])
    code = Map.get(params, "code", "")
    max_code_bytes = Keyword.get(code_cfg, :max_code_bytes, @default_max_code_bytes)
    blocked_patterns = Keyword.get(code_cfg, :blocked_patterns, [])

    cond do
      byte_size(code) > max_code_bytes ->
        {:error, :code_too_large}

      blocked_pattern?(code, blocked_patterns) ->
        {:error, :blocked_code_pattern}

      true ->
        :ok
    end
  end

  defp validate_tool_sandbox(_descriptor, _params, _ctx, _cfg), do: :ok

  defp allowlisted_write_path?(path, file_cfg) do
    prefixes = Keyword.get(file_cfg, :allowed_write_prefixes, [])

    if prefixes == [] do
      true
    else
      Enum.any?(prefixes, fn prefix ->
        String.starts_with?(path, prefix)
      end)
    end
  end

  defp valid_relative_path?(path) when is_binary(path) do
    not String.starts_with?(path, "/") and not String.contains?(path, "..")
  end

  defp valid_relative_path?(_), do: false

  defp blocked_pattern?(code, patterns) do
    Enum.any?(patterns, fn
      %Regex{} = regex -> Regex.match?(regex, code)
      pattern when is_binary(pattern) -> String.contains?(code, pattern)
      _ -> false
    end)
  end

  defp mcp_tool_allowlisted?(%ToolDescriptor{source: :mcp, server: server, name: name}, cfg) do
    mcp_cfg = Keyword.get(cfg, :mcp, [])
    servers = Keyword.get(mcp_cfg, :servers, %{})

    case Map.get(servers, server) do
      nil ->
        false

      server_cfg ->
        allowlist = MapSet.new(Map.get(server_cfg, :allowed_tools, []))
        MapSet.member?(allowlist, name)
    end
  end

  defp mcp_tool_allowlisted?(_descriptor, _cfg), do: true

  defp max_params_bytes(cfg, descriptor) do
    override = tool_override(cfg, descriptor)

    Keyword.get(
      override,
      :max_params_bytes,
      Keyword.get(cfg, :max_params_bytes, @default_max_params_bytes)
    )
  end

  defp max_result_bytes(cfg, nil),
    do: Keyword.get(cfg, :max_result_bytes, @default_max_result_bytes)

  defp max_result_bytes(cfg, descriptor) do
    override = tool_override(cfg, descriptor)

    Keyword.get(
      override,
      :max_result_bytes,
      Keyword.get(cfg, :max_result_bytes, @default_max_result_bytes)
    )
  end

  defp effective_tools_config(%ExecutionContext{} = ctx) do
    base = tools_config()
    profile = ctx.policy_profile || Keyword.get(base, :policy_profile, :strict)
    profiles = Keyword.get(base, :profiles, %{})
    override = Map.get(profiles, normalize_profile(profile), [])
    deep_merge_keyword(base, override)
  end

  defp normalize_profile(value) when value in @known_profiles, do: value

  defp normalize_profile(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.to_atom()
    |> normalize_profile()
  rescue
    _ -> :strict
  end

  defp normalize_profile(_), do: :strict

  defp deep_merge_keyword(base, override) when is_list(base) and is_list(override) do
    Keyword.merge(base, override, fn _key, left, right ->
      cond do
        is_list(left) and Keyword.keyword?(left) and is_list(right) and Keyword.keyword?(right) ->
          deep_merge_keyword(left, right)

        is_map(left) and is_map(right) ->
          Map.merge(left, right)

        true ->
          right
      end
    end)
  end

  defp tool_override(cfg, %ToolDescriptor{name: name}) do
    cfg
    |> Keyword.get(:tool_overrides, %{})
    |> Map.get(name, [])
  end

  defp tool_disabled?(override), do: Keyword.get(override, :enabled, true) == false
  defp tool_forced_allow?(override), do: Keyword.get(override, :enabled, nil) == true

  defp tools_config, do: SCR.ConfigCache.get(:tools, [])
end
