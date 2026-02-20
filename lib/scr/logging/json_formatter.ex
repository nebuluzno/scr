defmodule SCR.Logging.JSONFormatter do
  @moduledoc """
  Logger formatter that emits one JSON object per line.
  """

  @spec format(
          atom(),
          term(),
          {{integer(), integer(), integer()}, {integer(), integer(), integer(), integer()}},
          keyword()
        ) :: iodata()
  def format(level, message, timestamp, metadata) do
    payload = %{
      timestamp: format_timestamp(timestamp),
      level: level,
      message: format_message(message),
      metadata: format_metadata(metadata)
    }

    [Jason.encode!(payload), "\n"]
  end

  defp format_timestamp({date, time}) do
    with {year, month, day} <- date,
         {hour, minute, second, microsecond} <- time,
         {:ok, d} <- Date.new(year, month, day),
         {:ok, t} <- Time.new(hour, minute, second, {microsecond, 6}),
         {:ok, naive} <- NaiveDateTime.new(d, t) do
      NaiveDateTime.to_iso8601(naive)
    else
      _ -> nil
    end
  end

  defp format_message({format, args}) when is_binary(format) and is_list(args) do
    :io_lib.format(format, args)
    |> IO.iodata_to_binary()
  rescue
    _ -> inspect({format, args})
  end

  defp format_message(message) when is_binary(message), do: message

  defp format_message(message) do
    IO.iodata_to_binary(message)
  rescue
    _ -> inspect(message)
  end

  defp format_metadata(metadata) when is_list(metadata) do
    Enum.into(metadata, %{}, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp format_metadata(_), do: %{}

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_number(value), do: value
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(value) when is_nil(value), do: nil
  defp normalize_value(value), do: inspect(value)
end
