defmodule SCR.Tools.Calculator do
  @moduledoc """
  Calculator tool for performing mathematical operations.

  Supports basic arithmetic operations: addition, subtraction,
  multiplication, division, and exponentiation.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "calculator"

  @impl true
  def description do
    "A calculator tool that performs basic arithmetic operations. Use this when you need to calculate numeric results."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        operation: %{
          type: "string",
          enum: ["add", "subtract", "multiply", "divide", "power", "sqrt", "modulo"],
          description: "The arithmetic operation to perform"
        },
        a: %{
          type: "number",
          description: "First number"
        },
        b: %{
          type: "number",
          description: "Second number (not needed for sqrt)"
        }
      },
      required: ["operation", "a"]
    }
  end

  @impl true
  def execute(%{"operation" => op, "a" => a}) when is_number(a) and op == "sqrt" do
    result = :math.sqrt(a)
    {:ok, result}
  end

  # Two-argument operations (add, subtract, multiply, divide, power, modulo)
  @impl true
  def execute(%{"operation" => op, "a" => a, "b" => b}) when is_number(a) and is_number(b) do
    result =
      case op do
        "add" ->
          a + b

        "subtract" ->
          a - b

        "multiply" ->
          a * b

        "divide" ->
          if b == 0 do
            {:error, "Cannot divide by zero"}
          else
            a / b
          end

        "power" ->
          :math.pow(a, b)

        "modulo" ->
          if b == 0 do
            {:error, "Cannot modulo by zero"}
          else
            rem(a, b)
          end

        _ ->
          {:error, "Unknown operation: #{op}"}
      end

    case result do
      {:error, _} -> result
      _ -> {:ok, result}
    end
  end

  # Single-argument operations (sqrt)
  @impl true
  def execute(%{"operation" => "sqrt", "a" => a}) when is_number(a) do
    result = :math.sqrt(a)
    {:ok, result}
  end

  # Catch-all for single-argument operations that aren't supported
  @impl true
  def execute(%{"operation" => _op, "a" => _a}) do
    {:error, "This operation requires only 'a' parameter (e.g., sqrt)"}
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
