defmodule SCR.Observability.OTelBridge do
  @moduledoc """
  Bridges SCR telemetry events into OpenTelemetry spans for export.

  This is opt-in and intended for production observability.
  """

  use GenServer

  require Logger

  @events [
    [:scr, :tools, :execute],
    [:scr, :task_queue, :enqueue],
    [:scr, :task_queue, :dequeue],
    [:scr, :health, :check],
    [:scr, :health, :heal],
    [:scr, :mcp, :call]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    cfg = Application.get_env(:scr, __MODULE__, [])

    if Keyword.get(cfg, :enabled, false) do
      maybe_attach_handlers()
    end

    {:ok, %{enabled: Keyword.get(cfg, :enabled, false), handlers: handler_ids()}}
  end

  @impl true
  def terminate(_reason, state) do
    if Map.get(state, :enabled, false) do
      Enum.each(Map.get(state, :handlers, []), &:telemetry.detach/1)
    end

    :ok
  end

  defp maybe_attach_handlers do
    Enum.zip(@events, handler_ids())
    |> Enum.each(fn {event, id} ->
      :ok =
        :telemetry.attach(
          id,
          event,
          &__MODULE__.handle_event/4,
          %{}
        )
    end)
  rescue
    e ->
      Logger.warning("otel.bridge.attach.failed reason=#{inspect(e)}")
  end

  def handle_event(event, measurements, metadata, _config) do
    with true <- Code.ensure_loaded?(:otel_tracer),
         true <- function_exported?(:otel_tracer, :start_span, 1),
         true <- Code.ensure_loaded?(:otel_span),
         true <- function_exported?(:otel_span, :set_attribute, 3),
         true <- function_exported?(:otel_span, :end_span, 1) do
      span_name = Enum.join(event, ".")
      span_ctx = :otel_tracer.start_span(span_name, %{}, [])

      measurements
      |> normalize_pairs("measurements")
      |> Enum.each(fn {k, v} ->
        :otel_span.set_attribute(span_ctx, k, v)
      end)

      metadata
      |> normalize_pairs("metadata")
      |> Enum.each(fn {k, v} ->
        :otel_span.set_attribute(span_ctx, k, v)
      end)

      logger_trace_pairs()
      |> Enum.each(fn {k, v} ->
        :otel_span.set_attribute(span_ctx, k, v)
      end)

      :otel_span.end_span(span_ctx)
    else
      _ ->
        :ok
    end
  rescue
    _ ->
      :ok
  end

  defp handler_ids do
    Enum.map(@events, fn event ->
      "scr-otel-bridge-" <> Enum.join(event, "-")
    end)
  end

  defp normalize_pairs(data, prefix) when is_map(data) do
    Enum.map(data, fn {k, v} -> {"#{prefix}.#{k}", normalize_value(v)} end)
  end

  defp normalize_pairs(data, prefix) when is_list(data) do
    Enum.map(data, fn {k, v} -> {"#{prefix}.#{k}", normalize_value(v)} end)
  end

  defp normalize_pairs(_, _), do: []

  defp logger_trace_pairs do
    Logger.metadata()
    |> Enum.filter(fn {k, v} ->
      k in [:trace_id, :task_id, :parent_task_id, :subtask_id, :agent_id] and not is_nil(v)
    end)
    |> Enum.map(fn {k, v} -> {"trace.#{k}", normalize_value(v)} end)
  end

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_number(value), do: value
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(value) when is_nil(value), do: "nil"
  defp normalize_value(value), do: inspect(value)
end
