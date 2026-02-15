defmodule SCR.Agents.PlannerAgent do
  @moduledoc """
  PlannerAgent - Decomposes tasks and coordinates agent workflow.
  
  Orchestrates the task by:
  1. Breaking down complex tasks into subtasks
  2. Spawning WorkerAgents to execute subtasks
  3. Collecting results and sending to CriticAgent
  4. Handling failures and recovery
  """

  alias SCR.Message
  alias SCR.Agents.WorkerAgent

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :planner, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("🧠 PlannerAgent initialized")
    
    # Get agent_id from init_arg if provided, otherwise use default
    agent_id = Map.get(init_arg, :agent_id, "planner_1")
    
    {:ok, %{
      agent_id: agent_id,
      current_task: nil,
      subtasks: [],
      worker_pool: [],
      results: [],
      status: :idle,
      task_queue: []
    }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: _from}, state) do
    IO.puts("🧠 PlannerAgent received main task: #{inspect(task_data[:description])}")
    
    # Get internal state from context
    internal_state = state.agent_state
    
    # Decompose task into subtasks
    subtasks = decompose_task(task_data)
    
    # Store in memory
    store_in_memory(:task, %{task_data: task_data, subtasks: subtasks})
    
    new_state = %{internal_state |
      current_task: task_data,
      subtasks: subtasks,
      status: :planning
    }
    
    # Start executing subtasks
    new_state = execute_subtasks(new_state)
    
    {:noreply, new_state}
  end

  def handle_message(%Message{type: :result, payload: %{result: result_data}, from: from}, state) do
    IO.puts("🧠 PlannerAgent received result from #{from}")
    
    # Get internal state from context
    internal_state = state.agent_state
    
    # Check if it's a worker result or critic result
    worker_id = result_data[:task_id]
    _ = worker_id
    
    new_results = [%{from: from, data: result_data} | internal_state.results]
    
    # Check if all subtasks are complete
    if length(new_results) >= length(internal_state.subtasks) do
      IO.puts("🧠 All subtasks completed, sending to CriticAgent")
      
      # Send to CriticAgent for evaluation
      critic_msg = Message.result(state.agent_id, "critic_1", %{
        results: new_results,
        task: internal_state.current_task
      })
      
      SCR.Supervisor.send_to_agent("critic_1", critic_msg)
      
      {:noreply, %{internal_state | results: new_results, status: :evaluating}}
    else
      {:noreply, %{internal_state | results: new_results}}
    end
  end

  def handle_message(%Message{type: :critique, payload: %{critique: critique_data}, from: _from}, state) do
    IO.puts("🧠 PlannerAgent received critique: #{inspect(critique_data[:feedback])}")
    
    # Get internal state from context
    internal_state = state.agent_state
    
    # Check if revision is requested
    if critique_data[:revision_requested] do
      IO.puts("🧠 Revision requested, re-executing subtasks...")
      new_state = execute_subtasks(%{internal_state | results: []})
      {:noreply, %{new_state | status: :revising}}
    else
      IO.puts("🧠 Task approved! Finalizing...")
      
      # Store final results in memory
      store_in_memory(:result, %{
        task: internal_state.current_task,
        results: internal_state.results,
        critique: critique_data
      })
      
      {:noreply, %{internal_state | status: :completed}}
    end
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
    IO.puts("🧠 PlannerAgent terminating")
    :ok
  end

  # Private functions

  defp decompose_task(task_data) do
    description = Map.get(task_data, :description, "")
    
    # Create subtasks based on the main task
    [
      %{
        task_id: UUID.uuid4(),
        type: :research,
        description: "Research AI agent runtimes: #{description}",
        worker_id: "worker_1"
      },
      %{
        task_id: UUID.uuid4(),
        type: :analysis,
        description: "Analyze findings from research",
        worker_id: "worker_2"
      },
      %{
        task_id: UUID.uuid4(),
        type: :synthesis,
        description: "Synthesize research into structured output",
        worker_id: "worker_3"
      }
    ]
  end

  defp execute_subtasks(state) do
    # Spawn workers and assign tasks
    Enum.each(state.subtasks, fn subtask ->
      worker_id = "worker_#{:rand.uniform(100)}"
      
      # Start worker agent
      {:ok, _pid} = SCR.Supervisor.start_agent(
        worker_id,
        :worker,
        WorkerAgent,
        %{}
      )
      
      Process.sleep(100) # Give worker time to start
      
      # Send task to worker
      task_msg = Message.task(state.agent_id, worker_id, %{
        task_id: subtask.task_id,
        type: subtask.type,
        description: subtask.description
      })
      
      SCR.Supervisor.send_to_agent(worker_id, task_msg)
      
      IO.puts("🧠 Assigned #{subtask.type} task to #{worker_id}")
    end)
    
    %{state | worker_pool: Enum.map(state.subtasks, & &1.worker_id)}
  end

  defp store_in_memory(type, data) do
    # Send to memory agent
    msg = case type do
      :task -> Message.task("planner_1", "memory_1", %{task: data})
      :result -> Message.result("planner_1", "memory_1", %{result: data})
    end
    
    SCR.Supervisor.send_to_agent("memory_1", msg)
  end
end
