defmodule SCR.Agents.WorkerAgent do
  @moduledoc """
  WorkerAgent - Executes subtasks assigned by PlannerAgent.
  
  Performs research, analysis, and synthesis tasks.
  """

  alias SCR.Message

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :worker, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("👷 WorkerAgent initialized")
    
    agent_id = Map.get(init_arg, :agent_id, "worker_1")
    
    {:ok, %{
      agent_id: agent_id,
      current_task: nil,
      completed_tasks: [],
      task_type: nil
    }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: from}, state) do
    IO.puts("👷 WorkerAgent received task: #{inspect(task_data[:description])}")
    
    # Get internal state from context
    internal_state = state.agent_state
    
    task_type = Map.get(task_data, :type, :research)
    description = Map.get(task_data, :description, "")
    task_id = Map.get(task_data, :task_id, UUID.uuid4())
    
    # Process the task
    result = process_task(task_type, description, task_id)
    
    # Send result back to sender
    result_msg = Message.result(state.agent_id, from, %{
      task_id: task_id,
      result: result,
      status: :completed
    })
    
    SCR.Supervisor.send_to_agent(from, result_msg)
    
    new_state = %{internal_state |
      current_task: nil,
      completed_tasks: [task_id | internal_state.completed_tasks],
      task_type: task_type
    }
    
    {:noreply, new_state}
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
    IO.puts("👷 WorkerAgent terminating")
    :ok
  end

  # Private functions

  defp process_task(:research, description, task_id) do
    IO.puts("🔍 Performing research on: #{description}")
    Process.sleep(1000) # Simulate work
    
    %{
      task_id: task_id,
      type: :research,
      description: description,
      findings: [
        "LangChain: A framework for building LLM applications",
        "AutoGen: Microsoft's multi-agent framework",
        "CrewAI: Multi-agent orchestration platform",
        "BabyAGI: AI-powered task management system",
        "MetaGPT: Multi-agent collaboration framework"
      ],
      summary: "Research completed on AI agent runtimes"
    }
  end

  defp process_task(:analysis, description, task_id) do
    IO.puts("📊 Performing analysis on: #{description}")
    Process.sleep(800)
    
    %{
      task_id: task_id,
      type: :analysis,
      description: description,
      insights: [
        "Agent runtimes vary in complexity",
        "Supervision is critical for fault tolerance",
        "Message passing enables loose coupling",
        "Memory persistence enables long-running tasks"
      ],
      summary: "Analysis completed"
    }
  end

  defp process_task(:synthesis, description, task_id) do
    IO.puts("🎯 Performing synthesis on: #{description}")
    Process.sleep(600)
    
    %{
      task_id: task_id,
      type: :synthesis,
      description: description,
      output: %{
        title: "AI Agent Runtimes Overview",
        sections: [
          "Introduction to Agent Frameworks",
          "Comparison of LangChain, AutoGen, CrewAI",
          "Fault Tolerance Patterns",
          "Future Directions"
        ]
      },
      summary: "Synthesis completed"
    }
  end

  defp process_task(task_type, description, task_id) do
    IO.puts("⚙️ Performing generic task: #{task_type}")
    Process.sleep(500)
    
    %{
      task_id: task_id,
      type: task_type,
      description: description,
      output: "Task completed",
      summary: "Generic task completed"
    }
  end
end
