defmodule SCR.Agents.PlannerAgent do
  @moduledoc """
  PlannerAgent - Decomposes tasks and coordinates agent workflow.
  
  Orchestrates the task by:
  1. Breaking down complex tasks into subtasks using LLM
  2. Spawning appropriate agent types to execute subtasks
  3. Collecting results and sending to CriticAgent
  4. Handling failures and recovery
  
  Available Agent Types:
  - WorkerAgent: General task execution
  - ResearcherAgent: Web research and information gathering
  - WriterAgent: Content generation and summarization
  - ValidatorAgent: Quality assurance and verification
  - CriticAgent: Evaluation and feedback
  """

  alias SCR.Message
  alias SCR.Agents.WorkerAgent
  alias SCR.Agents.ResearcherAgent
  alias SCR.Agents.WriterAgent
  alias SCR.Agents.ValidatorAgent
  alias SCR.LLM.Client

  # Agent type mappings
  @agent_modules %{
    worker: WorkerAgent,
    researcher: ResearcherAgent,
    writer: WriterAgent,
    validator: ValidatorAgent
  }

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
    
    # Decompose task into subtasks using LLM
    subtasks = decompose_task_with_llm(task_data)
    
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
    # Note: state here is the internal state, not wrapped in agent_state
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    IO.puts("🧠 PlannerAgent terminating")
    :ok
  end

  # Private functions

  defp decompose_task_with_llm(task_data) do
    description = Map.get(task_data, :description, "")
    
    IO.puts("🤖 Using LLM to decompose task: #{description}")
    
    prompt = """
    You are a task planning assistant. Break down the following complex task into 3-5 subtasks.
    
    Main Task: #{description}
    
    Available Agent Types:
    - researcher: Best for web research, information gathering, fact-finding
    - writer: Best for content generation, summarization, formatting
    - validator: Best for quality assurance, fact-checking, verification
    - worker: General purpose for analysis, synthesis, other tasks
    
    Provide your response as a JSON array of subtask objects with this structure:
    [
      {
        "task_id": "unique-id",
        "agent_type": "researcher|writer|validator|worker",
        "description": "specific subtask description",
        "priority": 1-5
      },
      ...
    ]
    
    Choose the most appropriate agent type for each subtask.
    """
    
    case Client.complete(prompt, temperature: 0.5, max_tokens: 1024) do
      {:ok, %{content: llm_response}} ->
        parse_llm_subtasks(llm_response)
      
      {:error, reason} ->
        IO.puts("⚠️ LLM decomposition failed, using rule-based: #{inspect(reason)}")
        fallback_decompose_task(description)
    end
  end

  defp parse_llm_subtasks(llm_response) do
    case Jason.decode(llm_response) do
      {:ok, subtasks} when is_list(subtasks) ->
        Enum.map(subtasks, fn subtask ->
          agent_type = Map.get(subtask, "agent_type", "worker") |> String.to_atom()
          Map.merge(%{
            task_id: UUID.uuid4(),
            agent_type: agent_type,
            agent_id: "#{agent_type}_#{:rand.uniform(100)}",
            priority: Map.get(subtask, "priority", 3)
          }, subtask)
        end)
      
      _ ->
        # If JSON parsing fails, try to extract subtasks manually
        IO.puts("⚠️ Could not parse LLM response as JSON, using fallback")
        fallback_decompose_task("")
    end
  rescue
    _ -> fallback_decompose_task("")
  end

  defp fallback_decompose_task(description) do
    decompose_task(%{description: description})
  end

  defp decompose_task(task_data) do
    description = Map.get(task_data, :description, "")
    
    # Create subtasks using specialized agents
    [
      %{
        task_id: UUID.uuid4(),
        agent_type: :researcher,
        agent_id: "researcher_1",
        description: "Research and gather information about: #{description}",
        priority: 1
      },
      %{
        task_id: UUID.uuid4(),
        agent_type: :worker,
        agent_id: "worker_1",
        description: "Analyze findings from research",
        priority: 2
      },
      %{
        task_id: UUID.uuid4(),
        agent_type: :writer,
        agent_id: "writer_1",
        description: "Synthesize research into structured output",
        priority: 3
      },
      %{
        task_id: UUID.uuid4(),
        agent_type: :validator,
        agent_id: "validator_1",
        description: "Validate and verify the final output",
        priority: 4
      }
    ]
  end

  defp execute_subtasks(state) do
    # Sort subtasks by priority
    sorted_subtasks = Enum.sort_by(state.subtasks, & &1.priority)
    
    # Spawn appropriate agents and assign tasks
    Enum.each(sorted_subtasks, fn subtask ->
      agent_type = Map.get(subtask, :agent_type, :worker)
      agent_id = Map.get(subtask, :agent_id, "#{agent_type}_#{:rand.uniform(100)}")
      agent_module = Map.get(@agent_modules, agent_type, WorkerAgent)
      
      # Start agent
      {:ok, _pid} = SCR.Supervisor.start_agent(
        agent_id,
        agent_type,
        agent_module,
        %{agent_id: agent_id}
      )
      
      Process.sleep(100) # Give agent time to start
      
      # Send task to agent
      task_msg = Message.task(state.agent_id, agent_id, %{
        task_id: subtask.task_id,
        type: agent_type,
        description: subtask.description
      })
      
      SCR.Supervisor.send_to_agent(agent_id, task_msg)
      
      IO.puts("🧠 Assigned #{agent_type} task to #{agent_id}")
    end)
    
    %{state | worker_pool: Enum.map(sorted_subtasks, & &1.agent_id)}
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
