defmodule SCR.Distributed.SpecRegistry do
  @moduledoc """
  Replicates agent start specs across connected nodes for handoff/recovery.
  """

  use GenServer

  @group {:scr, :distributed_spec_registry}

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def upsert(agent_id, agent_type, module, init_arg, owner_node \\ Node.self()) do
    GenServer.cast(__MODULE__, {:upsert, agent_id, agent_type, module, init_arg, owner_node})
  end

  def remove(agent_id) do
    GenServer.cast(__MODULE__, {:remove, agent_id})
  end

  def claim(agent_id, owner_node) do
    GenServer.cast(__MODULE__, {:claim, agent_id, owner_node})
  end

  def specs_for_node(owner_node) do
    GenServer.call(__MODULE__, {:specs_for_node, owner_node})
  end

  def get(agent_id) do
    GenServer.call(__MODULE__, {:get, agent_id})
  end

  def all do
    GenServer.call(__MODULE__, :all)
  end

  @impl true
  def init(_opts) do
    if enabled?() and Node.alive?() do
      :ok = :pg.join(@group, self())
    end

    {:ok, %{entries: %{}}}
  end

  @impl true
  def handle_cast({:upsert, agent_id, agent_type, module, init_arg, owner_node}, state) do
    entry = %{
      agent_id: agent_id,
      agent_type: agent_type,
      module: module,
      init_arg: init_arg,
      owner_node: owner_node,
      updated_at: DateTime.utc_now()
    }

    broadcast({:spec_sync, :upsert, entry})
    {:noreply, put_entry(state, entry)}
  end

  @impl true
  def handle_cast({:remove, agent_id}, state) do
    broadcast({:spec_sync, :remove, agent_id})
    {:noreply, %{state | entries: Map.delete(state.entries, agent_id)}}
  end

  @impl true
  def handle_cast({:claim, agent_id, owner_node}, state) do
    case Map.get(state.entries, agent_id) do
      nil ->
        {:noreply, state}

      entry ->
        claimed = %{entry | owner_node: owner_node, updated_at: DateTime.utc_now()}
        broadcast({:spec_sync, :upsert, claimed})
        {:noreply, put_entry(state, claimed)}
    end
  end

  @impl true
  def handle_call({:specs_for_node, owner_node}, _from, state) do
    specs =
      state.entries
      |> Map.values()
      |> Enum.filter(&(&1.owner_node == owner_node))

    {:reply, specs, state}
  end

  @impl true
  def handle_call({:get, agent_id}, _from, state) do
    {:reply, Map.get(state.entries, agent_id), state}
  end

  @impl true
  def handle_call(:all, _from, state) do
    {:reply, Map.values(state.entries), state}
  end

  @impl true
  def handle_info({:spec_sync, :upsert, entry}, state) do
    {:noreply, put_entry(state, entry)}
  end

  @impl true
  def handle_info({:spec_sync, :remove, agent_id}, state) do
    {:noreply, %{state | entries: Map.delete(state.entries, agent_id)}}
  end

  defp put_entry(state, %{agent_id: agent_id} = entry) do
    %{state | entries: Map.put(state.entries, agent_id, entry)}
  end

  defp broadcast(msg) do
    if enabled?() and Node.alive?() do
      @group
      |> :pg.get_members()
      |> Enum.reject(&(&1 == self()))
      |> Enum.each(&send(&1, msg))
    end

    :ok
  end

  defp enabled? do
    cfg = Application.get_env(:scr, :distributed, [])
    Keyword.get(cfg, :enabled, false)
  end
end
