defmodule SCR.Distributed.RecoveryDrills do
  @moduledoc """
  Scripted recovery drills for distributed runtime validation.
  """

  alias SCR.Distributed.NodeWatchdog

  @type drill_name :: :node_flap | :partition

  def run(name, opts \\ [])

  def run(:node_flap, opts) do
    node = Keyword.get(opts, :node, Node.self())
    cycles = max(Keyword.get(opts, :cycles, 3), 1)
    down_ms = max(Keyword.get(opts, :down_ms, 150), 0)
    up_ms = max(Keyword.get(opts, :up_ms, 150), 0)

    steps =
      Enum.flat_map(1..cycles, fn _ ->
        [
          {:node_down, node},
          {:sleep, down_ms},
          {:node_up, node},
          {:sleep, up_ms}
        ]
      end)

    execute_steps(steps, opts)
  end

  def run(:partition, opts) do
    peers =
      Keyword.get(opts, :peers, Node.list())
      |> Enum.uniq()
      |> Enum.reject(&(&1 == Node.self()))

    duration_ms = max(Keyword.get(opts, :duration_ms, 500), 0)

    steps =
      Enum.map(peers, &{:disconnect, &1}) ++
        [{:sleep, duration_ms}] ++
        Enum.map(peers, &{:connect, &1})

    execute_steps(steps, opts)
  end

  def run(other, _opts), do: {:error, {:unsupported_drill, other}}

  defp execute_steps(steps, opts) do
    dry_run = Keyword.get(opts, :dry_run, true)

    events =
      Enum.map(steps, fn step ->
        if dry_run do
          {:planned, step}
        else
          {:executed, step, execute_step(step)}
        end
      end)

    {:ok, %{dry_run: dry_run, events: events}}
  end

  defp execute_step({:sleep, ms}) do
    Process.sleep(ms)
    :ok
  end

  defp execute_step({:node_down, node}) do
    if Process.whereis(NodeWatchdog), do: NodeWatchdog.note_node_down(node)
    :ok
  end

  defp execute_step({:node_up, node}) do
    if Process.whereis(NodeWatchdog), do: NodeWatchdog.note_node_up(node)
    :ok
  end

  defp execute_step({:disconnect, node}) do
    Node.disconnect(node)
  end

  defp execute_step({:connect, node}) do
    Node.connect(node)
  end
end
