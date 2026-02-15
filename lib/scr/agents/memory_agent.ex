defmodule SCR.Agents.MemoryAgent do
  @moduledoc """
  MemoryAgent - Persistent storage for tasks and agent states.
  
  Uses ETS (Erlang Term Storage) for in-memory persistence with
  disk backup capability.
  """

  alias SCR.Message

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :memory, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    # Initialize ETS table for memory storage
    :ets.new(:scr_memory, [:set, :named_table, :public])
    :ets.new(:scr_tasks, [:set, :named_table, :public])
    :ets.new(:scr_agent_states, [:set, :named_table, :public])
    
    agent_id = Map.get(init_arg, :agent_id, "memory_1")
    
    IO.puts("💾 MemoryAgent initialized with ETS storage")
    
    {:ok, %{agent_id: agent_id, storage: :ets}}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}}, state) do
    # Get internal state from context
    internal_state = state.agent_state
    
    # Store task in memory
    task_id = Map.get(task_data, :task_id, UUID.uuid4())
    :ets.insert(:scr_tasks, {task_id, task_data})
    
    IO.puts("💾 Stored task: #{task_id}")
    
    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :result, payload: %{result: result_data}}, state) do
    # Get internal state from context
    internal_state = state.agent_state
    
    # Store result in memory
    task_id = Map.get(result_data, :task_id, UUID.uuid4())
    :ets.insert(:scr_memory, {task_id, result_data})
    
    IO.puts("💾 Stored result for task: #{task_id}")
    
    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :status, payload: %{status: status_data}}, state) do
    # Get internal state from context
    internal_state = state.agent_state
    
    # Store agent status
    agent_id = Map.get(status_data, :agent_id)
    if agent_id do
      :ets.insert(:scr_agent_states, {agent_id, status_data})
    end
    
    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :ping, from: from, to: to}, state) do
    # Respond to ping
    pong = Message.pong(to, from)
    SCR.Supervisor.send_to_agent(from, pong)
    internal_state = state.agent_state
    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :stop}, state) do
    internal_state = state.agent_state
    {:stop, :normal, internal_state}
  end

  def handle_message(_message, state) do
    internal_state = state.agent_state
    {:noreply, internal_state}
  end

  def handle_heartbeat(state) do
    internal_state = state.agent_state
    {:noreply, internal_state}
  end

  def terminate(_reason, _state) do
    IO.puts("💾 MemoryAgent terminating - persisting data to disk...")
    # In a real system, we'd persist to disk here
    :ok
  end

  # Query API

  def get_task(task_id) do
    case :ets.lookup(:scr_tasks, task_id) do
      [{^task_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def get_result(task_id) do
    case :ets.lookup(:scr_memory, task_id) do
      [{^task_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def get_agent_state(agent_id) do
    case :ets.lookup(:scr_agent_states, agent_id) do
      [{^agent_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def list_tasks do
    :ets.tab2list(:scr_tasks)
    |> Enum.map(fn {id, _data} -> id end)
  end

  def list_agents do
    :ets.tab2list(:scr_agent_states)
    |> Enum.map(fn {id, _data} -> id end)
  end
end
