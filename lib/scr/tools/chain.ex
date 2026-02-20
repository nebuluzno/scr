defmodule SCR.Tools.Chain do
  @moduledoc """
  Utility for composing multiple tool calls into a single pipeline.

  Each step can be:
  - `%{tool: "tool_name", params: %{...}}`
  - `%{"tool" => "tool_name", "params" => %{...}}`
  - `{"tool_name", %{...}}`

  Parameter templates support:
  - `"__input__"` to inject the previous step output
  - `"$input.path.to.value"` to inject a nested value from previous output
  """

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.Registry

  @type step :: map() | {String.t(), map()}

  @doc """
  Execute a chain of tool calls.
  """
  def execute(chain, initial_input, ctx \\ ExecutionContext.new())

  def execute(chain, initial_input, ctx) when is_list(chain) and length(chain) > 0 do
    normalized_ctx = normalize_context(ctx)

    Enum.reduce_while(Enum.with_index(chain, 1), {:ok, initial_input, []}, fn {step, idx},
                                                                              {:ok, input, steps} ->
      with {:ok, tool_name, params_template} <- normalize_step(step),
           resolved_params <- resolve_params(params_template, input),
           step_ctx <- step_context(normalized_ctx, idx),
           {:ok, result} <- Registry.execute_tool(tool_name, resolved_params, step_ctx) do
        next_input = Map.get(result, :data, result)
        step_record = %{index: idx, tool: tool_name, params: resolved_params, result: result}
        {:cont, {:ok, next_input, steps ++ [step_record]}}
      else
        {:error, reason} ->
          {:halt, {:error, %{step: idx, reason: reason}}}
      end
    end)
    |> case do
      {:ok, output, steps} -> {:ok, %{output: output, steps: steps}}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute([], _initial_input, _ctx), do: {:error, :empty_chain}

  defp normalize_step(%{tool: tool, params: params}) when is_binary(tool) and is_map(params),
    do: {:ok, tool, params}

  defp normalize_step(%{"tool" => tool, "params" => params})
       when is_binary(tool) and is_map(params),
       do: {:ok, tool, params}

  defp normalize_step({tool, params}) when is_binary(tool) and is_map(params),
    do: {:ok, tool, params}

  defp normalize_step(_), do: {:error, :invalid_step}

  defp resolve_params(value, input) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, resolve_params(v, input)} end)
  end

  defp resolve_params(value, input) when is_list(value) do
    Enum.map(value, &resolve_params(&1, input))
  end

  defp resolve_params("__input__", input), do: input

  defp resolve_params("$input" <> rest, input) do
    path =
      rest
      |> String.trim_leading(".")
      |> String.split(".", trim: true)

    get_in_path(input, path)
  end

  defp resolve_params(value, _input), do: value

  defp get_in_path(data, []), do: data

  defp get_in_path(data, [key | rest]) when is_map(data) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        _ -> nil
      end

    value = Map.get(data, key) || if(atom_key, do: Map.get(data, atom_key), else: nil)
    get_in_path(value, rest)
  end

  defp get_in_path(data, [index | rest]) when is_list(data) do
    case Integer.parse(index) do
      {i, ""} -> get_in_path(Enum.at(data, i), rest)
      _ -> nil
    end
  end

  defp get_in_path(_data, _path), do: nil

  defp step_context(ctx, idx) do
    ExecutionContext.new(%{
      mode: ctx.mode,
      source: ctx.source,
      agent_id: ctx.agent_id,
      task_id: ctx.task_id,
      parent_task_id: ctx.parent_task_id || ctx.task_id,
      subtask_id: "chain_step_#{idx}",
      trace_id: ctx.trace_id
    })
  end

  defp normalize_context(%ExecutionContext{} = ctx), do: ctx
  defp normalize_context(ctx) when is_map(ctx), do: ExecutionContext.new(ctx)
  defp normalize_context(_), do: ExecutionContext.new()
end
