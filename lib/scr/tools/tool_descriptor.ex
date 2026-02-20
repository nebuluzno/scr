defmodule SCR.Tools.ToolDescriptor do
  @moduledoc """
  Canonical descriptor used by the registry for both native and MCP tools.
  """

  @type source :: :native | :mcp

  @enforce_keys [:name, :source, :description, :schema]
  defstruct [
    :name,
    :source,
    :module,
    :server,
    :description,
    :schema,
    timeout_ms: 10_000,
    tags: [],
    safety_level: :standard
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          source: source(),
          module: module() | nil,
          server: String.t() | nil,
          description: String.t(),
          schema: map(),
          timeout_ms: pos_integer(),
          tags: [String.t()],
          safety_level: atom()
        }
end
