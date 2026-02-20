defmodule SCR.Agent do
  @moduledoc """
  Base Agent behavior for all SCR agents.

  Provides common functionality for:
  - Message handling
  - State management
  - Heartbeat monitoring
  - Lifecycle management
  """

  use GenServer

  alias SCR.Message

  @type agent_type :: :planner | :worker | :critic | :memory | :supervisor
  @type agent_state :: :idle | :running | :crashed | :stopped
  @type state :: map()
  @dedupe_table :scr_routing_dedupe

  @doc """
  Called when the agent is started.
  """
  @callback init(init_arg :: term()) :: {:ok, state()} | {:stop, reason :: term()}

  @doc """
  Called when a message is received.
  """
  @callback handle_message(message :: Message.t(), state :: state()) ::
              {:noreply, state()} | {:stop, reason :: term(), state()}

  @doc """
  Called periodically for heartbeat/health checks.
  """
  @callback handle_heartbeat(state :: state()) ::
              {:noreply, state()} | {:stop, reason :: term(), state()}

  @doc """
  Called when the agent is stopping.
  """
  @callback terminate(reason :: term(), state :: state()) :: :ok

  @doc """
  Optional deep health probe callback.
  """
  @callback handle_health_check(state :: state()) :: map()

  @optional_callbacks handle_health_check: 1

  # Client API

  # For DynamicSupervisor - accepts a tuple as arg
  def start_link({agent_id, _agent_type, _module, _init_arg} = args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(agent_id))
  end

  # Backward compatibility - accepts individual args
  def start_link(agent_id, agent_type, module, init_arg) do
    start_link({agent_id, agent_type, module, init_arg})
  end

  def stop(agent_id, reason \\ :normal, timeout \\ 5000) do
    GenServer.stop(via_tuple(agent_id), reason, timeout)
  end

  def send_message(agent_id, message) do
    GenServer.cast(via_tuple(agent_id), {:deliver_message, message})
  end

  def get_state(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_state)
  end

  def get_status(agent_id) do
    GenServer.call(via_tuple(agent_id), :get_status)
  end

  def health_check(agent_id) do
    GenServer.call(via_tuple(agent_id), :health_check)
  end

  def crash(agent_id) do
    GenServer.cast(via_tuple(agent_id), :simulate_crash)
  end

  # GenServer callbacks

  def init({agent_id, agent_type, module, init_arg}) do
    Process.flag(:trap_exit, true)

    initial_state = %{
      agent_id: agent_id,
      agent_type: agent_type,
      module: module,
      status: :idle,
      message_count: 0,
      last_heartbeat: DateTime.utc_now(),
      supervisor_pid: nil
    }

    case module.init(init_arg) do
      {:ok, agent_state} ->
        case register_cluster_name(agent_id) do
          :ok ->
            full_state = Map.merge(initial_state, %{agent_state: agent_state, status: :running})
            schedule_heartbeat()

            # Broadcast agent started
            broadcast_agent_event(:agent_started, %{
              agent_id: agent_id,
              agent_type: agent_type,
              status: :running
            })

            {:ok, full_state}

          {:error, reason} ->
            {:stop, reason}
        end

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  def handle_cast({:deliver_message, message}, state) do
    if duplicate_task_message?(state.agent_id, message) do
      {:noreply, state}
    else
      # Pass a map with agent_id and agent_state to handle_message
      agent_context = %{agent_id: state.agent_id, agent_state: state.agent_state}

      case state.module.handle_message(message, agent_context) do
        {:noreply, new_agent_state} ->
          new_state = %{
            state
            | agent_state: new_agent_state,
              message_count: state.message_count + 1
          }

          {:noreply, new_state}

        {:stop, reason, new_agent_state} ->
          new_state = %{state | agent_state: new_agent_state, status: :crashed}
          {:stop, reason, new_state}
      end
    end
  end

  def handle_cast(:simulate_crash, state) do
    IO.puts("💥 Agent #{state.agent_id} (#{state.agent_type}) simulating crash!")
    {:stop, :simulated_crash, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state.agent_state, state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      agent_id: state.agent_id,
      agent_type: state.agent_type,
      status: state.status,
      message_count: state.message_count,
      last_heartbeat: state.last_heartbeat
    }

    {:reply, status, state}
  end

  def handle_call(:health_check, _from, state) do
    probe =
      if function_exported?(state.module, :handle_health_check, 1) do
        state.module.handle_health_check(state.agent_state)
      else
        %{
          healthy: true,
          status: state.status,
          message_count: state.message_count,
          agent_type: state.agent_type
        }
      end

    payload =
      Map.merge(
        %{
          agent_id: state.agent_id,
          agent_type: state.agent_type,
          status: state.status,
          message_count: state.message_count,
          last_heartbeat: state.last_heartbeat
        },
        probe || %{}
      )

    {:reply, payload, state}
  end

  def handle_info(:heartbeat, state) do
    case state.module.handle_heartbeat(state.agent_state) do
      {:noreply, new_agent_state} ->
        new_state = %{state | agent_state: new_agent_state, last_heartbeat: DateTime.utc_now()}
        schedule_heartbeat()
        {:noreply, new_state}

      {:stop, reason, new_agent_state} ->
        {:stop, reason, %{state | agent_state: new_agent_state, status: :crashed}}
    end
  end

  def handle_info({:EXIT, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    IO.puts("⚠️ Agent #{state.agent_id} received exit signal: #{reason}")
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    IO.puts("🛑 Agent #{state.agent_id} terminating: #{reason}")

    # Broadcast agent stopped
    broadcast_agent_event(:agent_stopped, state.agent_id)

    state.module.terminate(reason, state.agent_state)
  end

  # Private helpers

  defp broadcast_agent_event(event, data) do
    Phoenix.PubSub.broadcast(SCR.PubSub, "agents", {event, data})
  end

  defp via_tuple(agent_id) do
    {:via, Registry, {SCR.AgentRegistry, agent_id}}
  end

  defp schedule_heartbeat do
    # Heartbeat every 5 seconds
    Process.send_after(self(), :heartbeat, 5000)
  end

  defp register_cluster_name(agent_id) do
    cfg = Application.get_env(:scr, :distributed, [])
    distributed_enabled = Keyword.get(cfg, :enabled, false)
    cluster_registry = Keyword.get(cfg, :cluster_registry, true)

    if distributed_enabled and cluster_registry and Node.alive?() do
      case :global.register_name({:scr_agent, agent_id}, self()) do
        :yes -> :ok
        :no -> {:error, :duplicate_agent_id}
      end
    else
      :ok
    end
  end

  defp duplicate_task_message?(_agent_id, %{type: type}) when type != :task, do: false

  defp duplicate_task_message?(agent_id, message) do
    if dedupe_enabled?() do
      dedupe_key = message_dedupe_key(message)

      if is_nil(dedupe_key) do
        false
      else
        ensure_dedupe_table()
        cleanup_expired(agent_id)
        now_ms = System.system_time(:millisecond)
        table_key = {agent_id, dedupe_key}

        case :ets.lookup(@dedupe_table, table_key) do
          [{^table_key, expires_at}] when is_integer(expires_at) and expires_at > now_ms ->
            true

          _ ->
            :ets.insert(@dedupe_table, {table_key, now_ms + dedupe_ttl_ms()})
            false
        end
      end
    else
      false
    end
  end

  defp message_dedupe_key(message) do
    message.dedupe_key ||
      get_in(message.payload, [:task, :dedupe_key]) ||
      get_in(message.payload, [:task, :task_id]) ||
      message.message_id
  end

  defp ensure_dedupe_table do
    if :ets.whereis(@dedupe_table) == :undefined do
      :ets.new(@dedupe_table, [:set, :named_table, :public, read_concurrency: true])
    end
  end

  defp cleanup_expired(agent_id) do
    cutoff = System.system_time(:millisecond)

    match_spec = [
      {{{agent_id, :"$1"}, :"$2"}, [{:<, :"$2", cutoff}], [true]}
    ]

    :ets.select_delete(@dedupe_table, match_spec)
  rescue
    _ -> :ok
  end

  defp dedupe_enabled? do
    SCR.ConfigCache.get(:distributed, [])
    |> Keyword.get(:routing, [])
    |> then(fn routing ->
      Keyword.get(routing, :enabled, false) and Keyword.get(routing, :dedupe_enabled, true)
    end)
  rescue
    _ -> false
  end

  defp dedupe_ttl_ms do
    SCR.ConfigCache.get(:distributed, [])
    |> Keyword.get(:routing, [])
    |> Keyword.get(:dedupe_ttl_ms, 300_000)
  rescue
    _ -> 300_000
  end
end
