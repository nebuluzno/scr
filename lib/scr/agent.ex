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

  @doc """
  Called when the agent is started.
  """
  @callback init(init_arg :: term()) :: {:ok, state()} | {:stop, reason :: term()}

  @doc """
  Called when a message is received.
  """
  @callback handle_message(message :: Message.t(), state :: state()) :: {:noreply, state()} | {:stop, reason :: term(), state()}

  @doc """
  Called periodically for heartbeat/health checks.
  """
  @callback handle_heartbeat(state :: state()) :: {:noreply, state()} | {:stop, reason :: term(), state()}

  @doc """
  Called when the agent is stopping.
  """
  @callback terminate(reason :: term(), state :: state()) :: :ok

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
        full_state = Map.merge(initial_state, %{agent_state: agent_state, status: :running})
        schedule_heartbeat()
        {:ok, full_state}

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  def handle_cast({:deliver_message, message}, state) do
    # Pass a map with agent_id and agent_state to handle_message
    agent_context = %{agent_id: state.agent_id, agent_state: state.agent_state}
    
    case state.module.handle_message(message, agent_context) do
      {:noreply, new_agent_state} ->
        new_state = %{state | agent_state: new_agent_state, message_count: state.message_count + 1}
        {:noreply, new_state}

      {:stop, reason, new_agent_state} ->
        new_state = %{state | agent_state: new_agent_state, status: :crashed}
        {:stop, reason, new_state}
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

  def handle_info(:heartbeat, state) do
    case state.module.handle_heartbeat(state.agent_state) do
      {:noreply, new_agent_state} ->
        new_state = %{state |
          agent_state: new_agent_state,
          last_heartbeat: DateTime.utc_now()
        }
        schedule_heartbeat()
        {:noreply, new_state}

      {:stop, reason, new_agent_state} ->
        {:stop, reason, %{state | agent_state: new_agent_state, status: :crashed}}
    end
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    IO.puts("⚠️ Agent #{state.agent_id} received exit signal: #{reason}")
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    IO.puts("🛑 Agent #{state.agent_id} terminating: #{reason}")
    state.module.terminate(reason, state.agent_state)
  end

  # Private helpers

  defp via_tuple(agent_id) do
    {:via, Registry, {SCR.AgentRegistry, agent_id}}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, 5000) # Heartbeat every 5 seconds
  end
end
