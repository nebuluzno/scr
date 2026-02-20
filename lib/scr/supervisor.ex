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

  @agent_specs_table :scr_agent_specs

  #  @max_restart_attempts 3  # Reserved for future use

  def start_link(init_arg) do
    IO.puts("🚀 Starting SCR Supervisor...")

    # Start the registry
    Registry.start_link(keys: :unique, name: SCR.AgentRegistry)
    ensure_agent_specs_table()

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
        :ets.insert(@agent_specs_table, {agent_id, agent_type, module, init_arg})
        sync_spec_upsert(agent_id, agent_type, module, init_arg, Node.self())
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
    case get_agent_pid(agent_id) do
      {:ok, pid} ->
        if node(pid) == Node.self() do
          Agent.stop(agent_id)
          safe_terminate_child(pid)
          :ets.delete(@agent_specs_table, agent_id)
          sync_spec_remove(agent_id)
          IO.puts("✓ Stopped agent: #{agent_id}")
          :ok
        else
          :rpc.call(node(pid), __MODULE__, :stop_agent, [agent_id])
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Get the PID of an agent.
  """
  def get_agent_pid(agent_id) do
    case Registry.lookup(SCR.AgentRegistry, agent_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case :global.whereis_name({:scr_agent, agent_id}) do
          pid when is_pid(pid) -> {:ok, pid}
          _ -> {:error, :not_found}
        end
    end
  end

  @doc """
  Get the start spec of an agent.
  """
  def get_agent_spec(agent_id) do
    case :ets.lookup(@agent_specs_table, agent_id) do
      [{^agent_id, agent_type, module, init_arg}] ->
        {:ok, %{agent_type: agent_type, module: module, init_arg: init_arg}}

      [] ->
        {:error, :not_found}
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
      {:ok, pid} ->
        if node(pid) == Node.self() do
          Agent.send_message(agent_id, message)
        else
          GenServer.cast(pid, {:deliver_message, message})
        end

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
      {:ok, pid} ->
        if node(pid) == Node.self() do
          {:ok, Agent.get_status(agent_id)}
        else
          {:ok, GenServer.call(pid, :get_status)}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Simulate a crash in an agent (for testing recovery).
  """
  def crash_agent(agent_id) do
    case get_agent_pid(agent_id) do
      {:ok, pid} ->
        if node(pid) == Node.self() do
          Agent.crash(agent_id)
        else
          GenServer.cast(pid, :simulate_crash)
        end

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

  @doc """
  Restart an agent from stored start spec.
  """
  def restart_agent(agent_id) do
    case :ets.lookup(@agent_specs_table, agent_id) do
      [{^agent_id, agent_type, module, init_arg}] ->
        restart_agent(agent_id, agent_type, module, init_arg)

      [] ->
        {:error, :unknown_agent_spec}
    end
  end

  defp ensure_agent_specs_table do
    if :ets.whereis(@agent_specs_table) == :undefined do
      :ets.new(@agent_specs_table, [:set, :named_table, :public, read_concurrency: true])
    end
  end

  defp sync_spec_upsert(agent_id, agent_type, module, init_arg, owner_node) do
    if Process.whereis(SCR.Distributed.SpecRegistry) do
      SCR.Distributed.SpecRegistry.upsert(agent_id, agent_type, module, init_arg, owner_node)
    end
  end

  defp sync_spec_remove(agent_id) do
    if Process.whereis(SCR.Distributed.SpecRegistry) do
      SCR.Distributed.SpecRegistry.remove(agent_id)
    end
  end

  defp safe_terminate_child(pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, :noproc} -> :ok
      {:error, _} -> :ok
    end
  catch
    :exit, _ -> :ok
  end
end
