defmodule SCRWeb.MetricsHTML do
  use SCRWeb, :html

  embed_templates("metrics_html/*")

  def format_number(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
