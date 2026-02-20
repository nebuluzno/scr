defmodule SCR.Telemetry.Stream do
  @moduledoc """
  Captures and broadcasts recent telemetry events for live inspection.
  """

  use GenServer

  @name __MODULE__
  @default_max_events 500

  @events [
    [:scr, :task_queue, :enqueue],
    [:scr, :task_queue, :dequeue],
    [:scr, :tools, :execute],
    [:scr, :tools, :rate_limit],
    [:scr, :health, :check],
    [:scr, :health, :heal],
    [:scr, :mcp, :call]
  ]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(SCR.PubSub, "telemetry_events")
  end

  def recent(limit \\ 100) do
    GenServer.call(@name, {:recent, limit})
  end

  @impl true
  def init(_opts) do
    max_events =
      Application.get_env(:scr, __MODULE__, [])
      |> Keyword.get(:max_events, @default_max_events)

    handler_id = "scr-telemetry-stream-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        fn event, measurements, metadata, _ ->
          GenServer.cast(@name, {:event, event, measurements, metadata})
        end,
        nil
      )

    {:ok, %{handler_id: handler_id, max_events: max_events, events: :queue.new()}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    events =
      state.events
      |> :queue.to_list()
      |> Enum.reverse()
      |> Enum.take(limit)

    {:reply, events, state}
  end

  @impl true
  def handle_cast({:event, event, measurements, metadata}, state) do
    payload = %{
      event: event,
      measurements: measurements,
      metadata: metadata,
      at: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(SCR.PubSub, "telemetry_events", {:telemetry_event, payload})

    next_events = :queue.in(payload, state.events)
    trimmed = trim_queue(next_events, state.max_events)
    {:noreply, %{state | events: trimmed}}
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
    :ok
  end

  defp trim_queue(queue, max_events) do
    if :queue.len(queue) > max_events do
      {{:value, _}, rest} = :queue.out(queue)
      trim_queue(rest, max_events)
    else
      queue
    end
  end
end
