defmodule SCR.Agents.CriticAgent do
  @moduledoc """
  CriticAgent - Evaluates worker outputs and provides feedback.
  
  Reviews task results and can request revisions if quality
  doesn't meet standards.
  """

  alias SCR.Message

  @quality_threshold 0.5

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :critic, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("📝 CriticAgent initialized")
    
    agent_id = Map.get(init_arg, :agent_id, "critic_1")
    
    {:ok, %{
      agent_id: agent_id,
      evaluations: [],
      revision_requests: []
    }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: from}, state) do
    IO.puts("📝 CriticAgent evaluating task: #{inspect(task_data[:description])}")
    
    # Get internal state from context
    internal_state = state.agent_state
    
    task_id = Map.get(task_data, :task_id, UUID.uuid4())
    result_data = Map.get(task_data, :result)
    
    # Evaluate the result
    evaluation = evaluate_result(result_data, task_id)
    
    # Send evaluation back
    critique_msg = Message.critique(state.agent_id, from, %{
      task_id: task_id,
      evaluation: evaluation,
      quality_score: evaluation.score,
      feedback: evaluation.feedback,
      revision_requested: evaluation.score < @quality_threshold
    })
    
    SCR.Supervisor.send_to_agent(from, critique_msg)
    
    new_state = %{internal_state |
      evaluations: [evaluation | internal_state.evaluations]
    }
    
    {:noreply, new_state}
  end

  def handle_message(%Message{type: :result, payload: %{result: result_data}, from: from}, state) do
    IO.puts("📝 CriticAgent reviewing result")
    
    # Get internal state from context
    internal_state = state.agent_state
    
    task_id = Map.get(result_data, :task_id, UUID.uuid4())
    
    # Evaluate the result
    evaluation = evaluate_result(result_data, task_id)
    
    # Send critique back to planner
    critique_msg = Message.critique(state.agent_id, from, %{
      task_id: task_id,
      evaluation: evaluation,
      quality_score: evaluation.score,
      feedback: evaluation.feedback,
      revision_requested: evaluation.score < @quality_threshold
    })
    
    SCR.Supervisor.send_to_agent(from, critique_msg)
    
    new_state = %{internal_state |
      evaluations: [evaluation | internal_state.evaluations]
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
    IO.puts("📝 CriticAgent terminating")
    :ok
  end

  # Private functions

  defp evaluate_result(nil, _task_id) do
    %{
      task_id: nil,
      score: 0.0,
      feedback: "No result provided for evaluation",
      strengths: [],
      weaknesses: ["Missing result data"],
      revision_needed: true
    }
  end

  defp evaluate_result(result_data, task_id) do
    # Result can be either a single result or a map with :results array
    results = case result_data do
      %{results: rs} -> rs  # Array of results from planner
      _ -> [result_data]     # Single result
    end
    
    # Aggregate findings from all results
    all_results = Enum.map(results, fn r -> Map.get(r, :result, r) end)
    
    has_findings = Enum.any?(all_results, fn r -> Map.has_key?(r, :findings) end)
    has_summary = Enum.any?(all_results, fn r -> Map.has_key?(r, :summary) end)
    has_output = Enum.any?(all_results, fn r -> Map.has_key?(r, :output) end)
    
    score = cond do
      has_findings and has_summary -> 0.9
      has_output and has_summary -> 0.85
      has_summary -> 0.75
      true -> 0.6
    end
    
    strengths = []
    |> maybe_add("Comprehensive research", has_findings)
    |> maybe_add("Clear summary provided", has_summary)
    |> maybe_add("Structured output", has_output)
    
    weaknesses = []
    |> maybe_add("Missing detailed findings", not has_findings)
    |> maybe_add("No structured output", not has_output)
    
    %{
      task_id: task_id,
      score: score,
      feedback: generate_feedback(score, strengths, weaknesses),
      strengths: strengths,
      weaknesses: weaknesses,
      revision_needed: score < @quality_threshold
    }
  end

  defp maybe_add(list, _str, true), do: list
  defp maybe_add(list, str, false), do: [str | list]

  defp generate_feedback(score, _strengths, _weaknesses) when score >= 0.8 do
    "Excellent work! The result demonstrates strong quality."
  end

  defp generate_feedback(score, _strengths, _weaknesses) when score >= 0.7 do
    "Good quality. The result meets acceptable standards."
  end

  defp generate_feedback(_score, _strengths, weaknesses) do
    revision_items = Enum.take(weaknesses, 2)
    "Revision needed. Please address: #{Enum.join(revision_items, ", ")}"
  end
end
