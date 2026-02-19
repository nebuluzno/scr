defmodule SCR.Tools.Time do
  @moduledoc """
  Time tool for getting current time and date information.
  
  Provides current time in various formats and timezones.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "time"

  @impl true
  def description do
    "Get the current time and date. Can return time in different formats and timezones."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        format: %{
          type: "string",
          enum: ["iso8601", "unix", "rfc2822", "pretty"],
          description: "The format to return the time in"
        },
        timezone: %{
          type: "string",
          description: "The timezone (e.g., 'UTC', 'America/New_York', 'Europe/London')"
        }
      },
      required: []
    }
  end

  @impl true
  def execute(params) do
    format = Map.get(params, "format", "iso8601")
    timezone = Map.get(params, "timezone", "UTC")
    
    now = DateTime.utc_now()
    
    result = case format do
      "iso8601" ->
        {:ok, format_iso8601(now, timezone)}
      "unix" ->
        {:ok, DateTime.to_unix(now)}
      "rfc2822" ->
        {:ok, format_rfc2822(now)}
      "pretty" ->
        {:ok, format_pretty(now, timezone)}
      _ ->
        {:ok, format_iso8601(now, timezone)}
    end
    
    result
  rescue
    e -> {:error, "Time formatting error: #{inspect(e)}"}
  end

  defp format_iso8601(datetime, "UTC") do
    DateTime.to_iso8601(datetime)
  end
  
  defp format_iso8601(datetime, timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} -> DateTime.to_iso8601(shifted)
      {:error, _} -> "#{DateTime.to_iso8601(datetime)} (unknown timezone: #{timezone})"
    end
  end

  defp format_rfc2822(datetime) do
    Calendar.strftime(datetime, "%a, %d %b %Y %H:%M:%S +0000")
  end

  defp format_pretty(datetime, timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} ->
        Calendar.strftime(shifted, "%B %d, %Y at %I:%M %p %Z")
      {:error, _} ->
        Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p UTC")
    end
  end

  @impl true
  def to_openai_format do
    SCR.Tools.Behaviour.build_function_format(name(), description(), parameters_schema())
  end

  @impl true
  def on_register, do: :ok

  @impl true
  def on_unregister, do: :ok
end
