defmodule SCR.Trace do
  @moduledoc """
  Helpers for structured trace metadata in logs.
  """

  require Logger
  alias SCR.Tools.ExecutionContext

  @trace_keys [:trace_id, :task_id, :parent_task_id, :subtask_id, :agent_id]

  def put_metadata(meta) when is_map(meta) do
    Logger.metadata(
      meta
      |> Map.take(@trace_keys)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    )
  end

  def put_metadata(%ExecutionContext{} = ctx) do
    put_metadata(%{
      trace_id: ctx.trace_id,
      task_id: ctx.task_id,
      parent_task_id: ctx.parent_task_id,
      subtask_id: ctx.subtask_id,
      agent_id: ctx.agent_id
    })
  end

  def from_task(task_data, agent_id \\ nil) when is_map(task_data) do
    %{
      trace_id: Map.get(task_data, :trace_id) || Map.get(task_data, "trace_id"),
      task_id:
        to_string(
          Map.get(task_data, :task_id) || Map.get(task_data, "task_id") ||
            Map.get(task_data, :parent_task_id) || Map.get(task_data, "parent_task_id") || ""
        ),
      parent_task_id:
        maybe_to_string(
          Map.get(task_data, :parent_task_id) || Map.get(task_data, "parent_task_id")
        ),
      subtask_id:
        maybe_to_string(Map.get(task_data, :subtask_id) || Map.get(task_data, "subtask_id")),
      agent_id: maybe_to_string(agent_id)
    }
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)
end
