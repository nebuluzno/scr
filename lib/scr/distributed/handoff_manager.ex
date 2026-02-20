defmodule SCR.Distributed.HandoffManager do
  @moduledoc """
  Monitors cluster node availability and attempts agent handoff on node-down events.
  """

  use GenServer
  require Logger

  alias SCR.Distributed.SpecRegistry

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def handoff_from_node(failed_node) when is_atom(failed_node) do
    GenServer.call(__MODULE__, {:handoff_from_node, failed_node})
  end

  @impl true
  def init(_opts) do
    if enabled?() do
      :net_kernel.monitor_nodes(true)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call({:handoff_from_node, failed_node}, _from, state) do
    result = do_handoff_from_node(failed_node)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:nodedown, failed_node}, state) do
    if enabled?() do
      if Process.whereis(SCR.Distributed.NodeWatchdog) do
        SCR.Distributed.NodeWatchdog.note_node_down(failed_node)
      end

      _ = do_handoff_from_node(failed_node)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    if Process.whereis(SCR.Distributed.NodeWatchdog) do
      SCR.Distributed.NodeWatchdog.note_node_up(node)
    end

    {:noreply, state}
  end

  defp do_handoff_from_node(failed_node) do
    specs = SpecRegistry.specs_for_node(failed_node)

    results =
      Enum.map(specs, fn spec ->
        agent_id = spec.agent_id
        name = {:scr_agent, agent_id}

        case :global.whereis_name(name) do
          pid when is_pid(pid) and node(pid) != failed_node ->
            SpecRegistry.claim(agent_id, node(pid))
            {agent_id, :already_running}

          _ ->
            case SCR.Distributed.start_agent(
                   spec.agent_id,
                   spec.agent_type,
                   spec.module,
                   spec.init_arg
                 ) do
              {:ok, %{node: started_node}} ->
                SpecRegistry.claim(agent_id, started_node)
                Logger.warning("[distributed] handed off agent=#{agent_id} from=#{failed_node}")
                {agent_id, {:restarted, started_node}}

              {:ok, _pid} ->
                SpecRegistry.claim(agent_id, Node.self())
                Logger.warning("[distributed] handed off agent=#{agent_id} from=#{failed_node}")
                {agent_id, :restarted}

              {:error, reason} ->
                Logger.warning(
                  "[distributed] handoff failed agent=#{agent_id} from=#{failed_node} reason=#{inspect(reason)}"
                )

                {agent_id, {:error, reason}}
            end
        end
      end)

    {:ok, results}
  end

  defp enabled? do
    cfg = Application.get_env(:scr, :distributed, [])
    Keyword.get(cfg, :enabled, false) and Keyword.get(cfg, :handoff_enabled, true)
  end
end
