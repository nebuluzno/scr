defmodule SCR.Tools.FileOperations do
  @moduledoc """
  File Operations tool for reading and writing files in the SCR workspace.
  
  Allows agents to persist results and read configuration files.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "file_operations"

  @impl true
  def description do
    "Reads or writes files in the workspace. Use this to save research results, read configuration, or persist data."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        operation: %{
          type: "string",
          enum: ["read", "write", "append", "list"],
          description: "The file operation to perform"
        },
        path: %{
          type: "string",
          description: "File path (relative to workspace)"
        },
        content: %{
          type: "string",
          description: "Content to write (for write/append operations)"
        }
      },
      required: ["operation"]
    }
  end

  @impl true
  def execute(%{"operation" => "list"}) do
    # List files in workspace
    case File.ls("/Users/lars/Documents/SCR") do
      {:ok, files} ->
        # Filter to only relevant files
        relevant = files |> Enum.filter(fn f -> 
          String.ends_with?(f, ".ex") or 
          String.ends_with?(f, ".md") or
          String.ends_with?(f, ".txt") or
          String.ends_with?(f, ".json")
        end)
        {:ok, %{files: relevant}}
      
      {:error, reason} ->
        {:error, "Failed to list files: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(%{"operation" => "read", "path" => path}) do
    full_path = Path.expand(path, "/Users/lars/Documents/SCR")
    
    case File.read(full_path) do
      {:ok, content} -> 
        # Limit content size for LLM
        limited_content = if String.length(content) > 5000 do
          String.slice(content, 0, 5000) <> "\n\n... [truncated]"
        else
          content
        end
        {:ok, %{path: path, content: limited_content}}
      
      {:error, reason} -> 
        {:error, "Failed to read file #{path}: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(%{"operation" => "write", "path" => path, "content" => content}) do
    full_path = Path.expand(path, "/Users/lars/Documents/SCR")
    
    # Ensure directory exists
    dir = Path.dirname(full_path)
    File.mkdir_p(dir)
    
    case File.write(full_path, content) do
      :ok -> 
        {:ok, %{path: path, size: byte_size(content)}}
      
      {:error, reason} -> 
        {:error, "Failed to write file #{path}: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(%{"operation" => "append", "path" => path, "content" => content}) do
    full_path = Path.expand(path, "/Users/lars/Documents/SCR")
    
    case File.write(full_path, content, [:append]) do
      :ok -> 
        {:ok, %{path: path, size: byte_size(content)}}
      
      {:error, reason} -> 
        {:error, "Failed to append to file #{path}: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(params) do
    {:error, "Invalid parameters: #{inspect(params)}"}
  end

  @impl true
  def to_openai_format do
    SCR.Tools.Behaviour.build_function_format(
      name(),
      description(),
      parameters_schema()
    )
  end

  @impl true
  def on_register, do: :ok

  @impl true
  def on_unregister, do: :ok
end
