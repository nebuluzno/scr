defmodule SCR.Tools.CodeExecution do
  @moduledoc """
  Code execution tool for running code snippets safely.

  Supports Elixir code execution in a sandboxed environment.
  Results are returned as strings.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "code_execution"

  @impl true
  def description do
    "Execute code snippets and return the result. Supports Elixir code. Use for calculations, data transformations, and simple algorithms."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        language: %{
          type: "string",
          enum: ["elixir"],
          description: "The programming language (currently only Elixir supported)"
        },
        code: %{
          type: "string",
          description: "The code to execute"
        },
        timeout: %{
          type: "number",
          description: "Execution timeout in milliseconds (default: 5000, max: 10000)"
        }
      },
      required: ["code"]
    }
  end

  @impl true
  def execute(%{"code" => code} = params) do
    language = Map.get(params, "language", "elixir")
    timeout = min(Map.get(params, "timeout", 5000), 10_000)

    case language do
      "elixir" -> execute_elixir(code, timeout)
      _ -> {:error, "Unsupported language: #{language}"}
    end
  end

  def execute(_params) do
    {:error, "Code is required"}
  end

  defp execute_elixir(code, timeout) do
    # Security: Block dangerous operations
    if contains_dangerous_operations?(code) do
      {:error, "Code contains blocked operations for security reasons"}
    else
      try do
        # Execute with timeout
        task =
          Task.async(fn ->
            try do
              {result, _binding} = Code.eval_string(code, [], __ENV__)
              result
            rescue
              e -> {:error, "Execution error: #{Exception.message(e)}"}
            end
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, {:error, _} = error} -> error
          {:ok, result} -> {:ok, format_result(result)}
          nil -> {:error, "Execution timed out after #{timeout}ms"}
        end
      rescue
        e -> {:error, "Failed to execute code: #{Exception.message(e)}"}
      end
    end
  end

  defp contains_dangerous_operations?(code) do
    dangerous_patterns = [
      ~r/System\./,
      ~r/File\./,
      ~r/IO\./,
      ~r/Process\./,
      ~r/Node\./,
      ~r/Port\./,
      ~r/Agent\./,
      ~r/GenServer\./,
      ~r/Supervisor\./,
      ~r/Application\./,
      ~r/Code\.(add_path|require_file|compile_file)/,
      ~r/:os\.cmd/,
      ~r/:erlang\.open_port/,
      ~r/:erlang\.spawn/,
      ~r/__ENV__\./
    ]

    Enum.any?(dangerous_patterns, &Regex.match?(&1, code))
  end

  defp format_result(result) when is_binary(result), do: result
  defp format_result(result) when is_number(result), do: result
  defp format_result(result) when is_atom(result), do: Atom.to_string(result)

  defp format_result(result) when is_list(result) do
    try do
      Enum.join(result, ", ")
    rescue
      _ -> inspect(result)
    end
  end

  defp format_result(result) when is_map(result) do
    try do
      Jason.encode!(result)
    rescue
      _ -> inspect(result)
    end
  end

  defp format_result(result), do: inspect(result)

  @impl true
  def to_openai_format do
    SCR.Tools.Behaviour.build_function_format(name(), description(), parameters_schema())
  end

  @impl true
  def on_register, do: :ok

  @impl true
  def on_unregister, do: :ok
end
