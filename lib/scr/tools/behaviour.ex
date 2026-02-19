defmodule SCR.Tools.Behaviour do
  @moduledoc """
  Behaviour that defines the contract for SCR tools.
  
  Tools are modules that agents can call to perform specific actions
  beyond text generation, such as making HTTP requests, calculations,
  or interacting with external services.
  """

  @doc """
  Returns the unique name of the tool.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what the tool does.
  """
  @callback description() :: String.t()

  @doc """
  Returns the JSON schema for the tool's input parameters.
  """
  @callback parameters_schema() :: map()

  @doc """
  Executes the tool with the given parameters.
  
  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  @callback execute(params :: map()) :: {:ok, any()} | {:error, String.t()}

  @doc """
  Optional callback. Called when the tool is registered.
  """
  @callback on_register() :: :ok

  @doc """
  Optional callback. Called when the tool is unregistered.
  """
  @callback on_unregister() :: :ok

  @doc false
  def on_register(), do: :ok

  @doc false
  def on_unregister(), do: :ok

  @doc """
  Returns the tool definition in OpenAI function calling format.
  This is used to pass tool definitions to the LLM.
  """
  @callback to_openai_format() :: map()
  def to_openai_format(_module) do
    raise "Not implemented - each tool must implement to_openai_format/0"
  end

  # Helper to build OpenAI function format
  def build_function_format(name, description, parameters) do
    %{
      type: "function",
      function: %{
        name: name,
        description: description,
        parameters: parameters
      }
    }
  end
end
