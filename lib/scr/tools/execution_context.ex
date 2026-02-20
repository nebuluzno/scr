defmodule SCR.Tools.ExecutionContext do
  @moduledoc """
  Execution context propagated through tool calls.
  """

  @enforce_keys [:mode]
  defstruct [
    :mode,
    :agent_id,
    :task_id,
    :parent_task_id,
    :subtask_id,
    :trace_id,
    :source
  ]

  @type mode :: :strict | :demo

  @type t :: %__MODULE__{
          mode: mode(),
          agent_id: String.t() | nil,
          task_id: String.t() | nil,
          parent_task_id: String.t() | nil,
          subtask_id: String.t() | nil,
          trace_id: String.t() | nil,
          source: :native | :mcp | nil
        }

  @doc """
  Builds an execution context with defaults from app config.
  """
  def new(attrs \\ %{}) when is_map(attrs) do
    tools_cfg = SCR.ConfigCache.get(:tools, [])
    default_mode = Keyword.get(tools_cfg, :safety_mode, :strict)

    %__MODULE__{
      mode: Map.get(attrs, :mode, default_mode),
      agent_id: Map.get(attrs, :agent_id),
      task_id: Map.get(attrs, :task_id),
      parent_task_id: Map.get(attrs, :parent_task_id),
      subtask_id: Map.get(attrs, :subtask_id),
      trace_id: Map.get(attrs, :trace_id, UUID.uuid4()),
      source: Map.get(attrs, :source)
    }
  end
end
