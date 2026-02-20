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
    case File.ls(workspace_root()) do
      {:ok, files} ->
        # Filter to only relevant files
        relevant =
          files
          |> Enum.filter(fn f ->
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
    with {:ok, full_path} <- resolve_workspace_path(path),
         {:ok, content} <- File.read(full_path) do
      # Limit content size for LLM
      limited_content =
        if String.length(content) > 5000 do
          String.slice(content, 0, 5000) <> "\n\n... [truncated]"
        else
          content
        end

      {:ok, %{path: path, content: limited_content}}
    else
      {:error, :path_outside_workspace} ->
        {:error, "Path is outside workspace root"}

      {:error, reason} ->
        {:error, "Failed to read file #{path}: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(%{"operation" => "write", "path" => path, "content" => content}) do
    with {:ok, full_path} <- resolve_workspace_path(path),
         :ok <- File.mkdir_p(Path.dirname(full_path)),
         :ok <- File.write(full_path, content) do
      {:ok, %{path: path, size: byte_size(content)}}
    else
      {:error, :path_outside_workspace} ->
        {:error, "Path is outside workspace root"}

      {:error, reason} ->
        {:error, "Failed to write file #{path}: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(%{"operation" => "append", "path" => path, "content" => content}) do
    with {:ok, full_path} <- resolve_workspace_path(path),
         :ok <- File.mkdir_p(Path.dirname(full_path)),
         :ok <- File.write(full_path, content, [:append]) do
      {:ok, %{path: path, size: byte_size(content)}}
    else
      {:error, :path_outside_workspace} ->
        {:error, "Path is outside workspace root"}

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

  defp workspace_root do
    tools_cfg = Application.get_env(:scr, :tools, [])
    configured = Keyword.get(tools_cfg, :workspace_root)
    configured || File.cwd!()
  end

  defp resolve_workspace_path(path) when is_binary(path) do
    root = Path.expand(workspace_root())
    candidate = Path.expand(path, root)

    if candidate == root || String.starts_with?(candidate, root <> "/") do
      {:ok, candidate}
    else
      {:error, :path_outside_workspace}
    end
  end
end
