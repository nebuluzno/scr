defmodule SCR.Supervisor do
  @moduledoc """
  Main supervisor for the SCR runtime.
  
  Manages:
  - Agent registry
  - Agent lifecycle (start, stop, restart)
  - Crash detection and recovery
  - Dynamic agent spawning
  """

  use DynamicSupervisor
  alias SCR.Agent

#  @max_restart_attempts 3  # Reserved for future use

  def start_link(init_arg) do
    IO.puts("🚀 Starting SCR Supervisor...")
    
    # Start the registry
    Registry.start_link(keys: :unique, name: SCR.AgentRegistry)
    
    # Start dynamic supervisor
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    IO.puts("✅ SCR Supervisor initialized")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new agent of the specified type.
  """
  def start_agent(agent_id, agent_type, module, init_arg \\ %{}) do
    spec = {Agent, {agent_id, agent_type, module, init_arg}}
    
    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        IO.puts("✓ Started #{agent_type} agent: #{agent_id}")
        {:ok, pid}
      
      {:error, {:already_started, _pid}} ->
        IO.puts("⚠️ Agent #{agent_id} already running")
        {:error, :already_started}
      
      {:error, reason} ->
        IO.puts("✗ Failed to start agent #{agent_id}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Stop an agent.
  """
  def stop_agent(agent_id) do
    case Registry.lookup(SCR.AgentRegistry, agent_id) do
      [{pid, _}] ->
        Agent.stop(agent_id)
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        IO.puts("✓ Stopped agent: #{agent_id}")
        :ok
      
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Get the PID of an agent.
  """
  def get_agent_pid(agent_id) do
    case Registry.lookup(SCR.AgentRegistry, agent_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all running agents.
  """
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.map(fn pid -> 
      case Registry.keys(SCR.AgentRegistry, pid) do
        [agent_id] -> agent_id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Send a message to an agent.
  """
  def send_to_agent(agent_id, message) do
    case get_agent_pid(agent_id) do
      {:ok, _pid} ->
        Agent.send_message(agent_id, message)
        :ok
      
      {:error, :not_found} ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Get status of an agent.
  """
  def get_agent_status(agent_id) do
    case get_agent_pid(agent_id) do
      {:ok, _pid} ->
        Agent.get_status(agent_id)
      
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Simulate a crash in an agent (for testing recovery).
  """
  def crash_agent(agent_id) do
    case get_agent_pid(agent_id) do
      {:ok, _pid} ->
        Agent.crash(agent_id)
        :ok
      
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Restart a crashed agent.
  """
  def restart_agent(agent_id, agent_type, module, init_arg \\ %{}) do
    # Wait a bit for the old process to fully terminate
    Process.sleep(100)
    
    # Clean up registry entry if it exists
    try do
      Registry.unregister(SCR.AgentRegistry, agent_id)
    rescue
      _ -> :ok
    end
    
    IO.puts("🔄 Restarting agent: #{agent_id}")
    start_agent(agent_id, agent_type, module, init_arg)
  end
end
