defmodule SCRWeb.TaskHTML do
  use SCRWeb, :html

  embed_templates("task_html/*")

  def status_badge_class(status) do
    case status do
      :completed -> "badge-success"
      :done -> "badge-success"
      :failed -> "badge-error"
      :error -> "badge-error"
      :in_progress -> "badge-warning"
      :queued -> "badge-info"
      _ -> "badge-secondary"
    end
  end

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_datetime(_), do: "n/a"
end
