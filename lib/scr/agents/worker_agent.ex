defmodule SCR.Agents.WorkerAgent do
  @moduledoc """
  WorkerAgent - Executes subtasks assigned by PlannerAgent.

  Performs research, analysis, and synthesis tasks using LLM.
  Falls back to mock responses if LLM is unavailable.
  Supports tool calling for enhanced task execution.
  """

  alias SCR.Message
  alias SCR.AgentContext
  alias SCR.LLM.Client
  alias SCR.Tools.Registry
  alias SCR.Tools.ExecutionContext

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :worker, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("👷 WorkerAgent initialized")

    agent_id = Map.get(init_arg, :agent_id, "worker_1")

    {:ok,
     %{
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

    # Process the task using LLM
    result = process_task_with_llm(task_type, description, task_id)

    _ =
      AgentContext.add_finding(to_string(task_id), %{
        agent_id: state.agent_id,
        task_type: task_type,
        summary: summarize_result(result)
      })

    _ = AgentContext.set_status(to_string(task_id), :completed)

    # Send result back to sender
    result_msg =
      Message.result(state.agent_id, from, %{
        task_id: task_id,
        result: result,
        status: :completed
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    new_state = %{
      internal_state
      | current_task: nil,
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
    # Note: state here is the internal state, not wrapped in agent_state
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    IO.puts("👷 WorkerAgent terminating")
    :ok
  end

  # Private functions

  defp process_task_with_llm(task_type, description, task_id) do
    IO.puts("🤖 Using LLM for #{task_type} task: #{description}")

    context = execution_context(task_id)
    tools = Registry.get_tool_definitions(context)
    tools_info = get_tools_info(context)

    prompt = build_prompt(task_type, description, tools_info)
    messages = [%{"role" => "user", "content" => prompt}]

    if tools != [] do
      # Use chat_with_tools for LLM calls with tool support
      case Client.chat_with_tools(messages, tools,
             temperature: 0.7,
             max_tokens: 2048,
             execution_context: context
           ) do
        {:ok, %{content: llm_response}} ->
          format_result(task_type, description, task_id, llm_response, :llm_with_tools)

        {:error, reason} ->
          IO.puts("⚠️ LLM with tools failed, falling back: #{inspect(reason)}")
          process_task_with_llm_fallback(task_type, description, task_id)
      end
    else
      # No tools available, use regular completion
      case Client.complete(prompt, temperature: 0.7, max_tokens: 2048) do
        {:ok, %{content: llm_response}} ->
          format_result(task_type, description, task_id, llm_response, :llm)

        {:error, reason} ->
          IO.puts("⚠️ LLM failed, falling back to mock: #{inspect(reason)}")
          fallback_process_task(task_type, description, task_id)
      end
    end
  end

  defp build_prompt(:research, description, tools_info) do
    """
    You are a research assistant. Research the following topic and provide detailed findings.

    Topic: #{description}

    #{tools_info}

    Provide your response as a JSON object with the following structure:
    {
      "findings": ["finding 1", "finding 2", ...],
      "summary": "A brief summary of your research",
      "sources": ["source 1", "source 2", ...]
    }
    """
  end

  defp build_prompt(:analysis, description, tools_info) do
    """
    You are an analytical consultant. Analyze the following and provide insights.

    Topic: #{description}

    #{tools_info}

    Provide your response as a JSON object with the following structure:
    {
      "insights": ["insight 1", "insight 2", ...],
      "summary": "A brief summary of your analysis",
      "recommendations": ["recommendation 1", ...]
    }
    """
  end

  defp build_prompt(:synthesis, description, tools_info) do
    """
    You are a technical writer. Synthesize information into a structured output.

    Topic: #{description}

    #{tools_info}

    Provide your response as a JSON object with the following structure:
    {
      "output": {
        "title": "A suitable title",
        "sections": ["section 1", "section 2", ...]
      },
      "summary": "A brief summary"
    }
    """
  end

  defp build_prompt(task_type, description, tools_info) do
    """
    You are a helpful assistant. Complete the following task.

    Task type: #{task_type}
    Description: #{description}

    #{tools_info}

    Provide a clear and concise response.
    """
  end

  defp get_tools_info(context) do
    tools = Registry.list_tools(context: context, descriptors: true)

    if tools != [] do
      tool_descriptions =
        Enum.map_join(tools, "\n", fn tool ->
          source = if tool.source == :mcp, do: "mcp", else: "native"
          "- #{tool.name} (#{source}): #{tool.description}"
        end)

      """
      Available tools:
      You can use these tools to enhance your research:
      #{tool_descriptions}

      If you need to use a tool, call it and then continue with your response.
      """
    else
      ""
    end
  end

  defp format_result(task_type, description, task_id, llm_response, source) do
    # Try to parse as JSON, fall back to plain text
    case Jason.decode(llm_response) do
      {:ok, parsed} ->
        # If it's already a map, use it directly
        if is_map(parsed) do
          # Check if it has the expected structure
          formatted =
            Map.merge(
              %{
                task_id: task_id,
                type: task_type,
                description: description,
                source: source
              },
              parsed
            )

          formatted
        else
          # Plain text response
          %{
            task_id: task_id,
            type: task_type,
            description: description,
            result: %{summary: to_string(parsed)},
            source: source
          }
        end

      _ ->
        # Plain text response
        %{
          task_id: task_id,
          type: task_type,
          description: description,
          result: %{summary: llm_response},
          source: source
        }
    end
  end

  defp process_task_with_llm_fallback(task_type, description, task_id) do
    # Try without tools
    prompt = build_prompt(task_type, description, "")

    case Client.complete(prompt, temperature: 0.7, max_tokens: 2048) do
      {:ok, %{content: llm_response}} ->
        format_result(task_type, description, task_id, llm_response, :llm)

      {:error, reason} ->
        IO.puts("⚠️ LLM fallback also failed: #{inspect(reason)}")
        fallback_process_task(task_type, description, task_id)
    end
  end

  defp fallback_process_task(task_type, description, task_id) do
    # Use the original mock implementation as fallback
    process_task(task_type, description, task_id)
  end

  defp process_task(:research, description, task_id) do
    IO.puts("🔍 Performing research on: #{description}")
    # Simulate work
    Process.sleep(1000)

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
      summary: "Research completed on AI agent runtimes",
      source: :mock
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
      summary: "Analysis completed",
      source: :mock
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
      summary: "Synthesis completed",
      source: :mock
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
      summary: "Generic task completed",
      source: :mock
    }
  end

  defp execution_context(task_id) do
    ExecutionContext.new(%{
      agent_id: "worker",
      task_id: to_string(task_id),
      trace_id: UUID.uuid4()
    })
  end

  defp summarize_result(result) when is_map(result) do
    cond do
      is_binary(Map.get(result, :summary)) -> Map.get(result, :summary)
      is_binary(get_in(result, [:result, :summary])) -> get_in(result, [:result, :summary])
      true -> inspect(result) |> String.slice(0, 240)
    end
  end

  defp summarize_result(result), do: inspect(result) |> String.slice(0, 240)
end
