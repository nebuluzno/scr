defmodule SCR.Agents.ResearcherAgent do
  @moduledoc """
  ResearcherAgent - Specialized agent for web research and information gathering.
  
  Capabilities:
  - Web search and content extraction
  - Multi-source research aggregation
  - Fact verification and cross-referencing
  - Research summarization
  """

  alias SCR.Message
  alias SCR.LLM.Client
  alias SCR.Tools.Registry

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :researcher, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("🔍 ResearcherAgent initialized")
    
    agent_id = Map.get(init_arg, :agent_id, "researcher_1")
    
    {:ok, %{
      agent_id: agent_id,
      current_research: nil,
      sources: [],
      findings: [],
      research_count: 0
    }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: from}, state) do
    IO.puts("🔍 ResearcherAgent received research task: #{inspect(task_data[:description])}")
    
    internal_state = state.agent_state
    
    description = Map.get(task_data, :description, "")
    task_id = Map.get(task_data, :task_id, UUID.uuid4())
    depth = Map.get(task_data, :depth, :standard)
    
    # Perform research
    result = perform_research(description, depth)
    
    # Send result back
    result_msg = Message.result(state.agent_id, from, %{
      task_id: task_id,
      result: result,
      status: :completed,
      agent_type: :researcher
    })
    
    SCR.Supervisor.send_to_agent(from, result_msg)
    
    new_state = %{internal_state |
      current_research: nil,
      findings: result.findings ++ internal_state.findings,
      sources: result.sources ++ internal_state.sources,
      research_count: internal_state.research_count + 1
    }
    
    {:noreply, new_state}
  end

  def handle_message(%Message{type: :research, payload: %{query: query, depth: depth}, from: from}, state) do
    IO.puts("🔍 ResearcherAgent conducting research: #{query}")
    
    internal_state = state.agent_state
    
    result = perform_research(query, depth)
    
    result_msg = Message.result(state.agent_id, from, %{
      query: query,
      result: result,
      status: :completed
    })
    
    SCR.Supervisor.send_to_agent(from, result_msg)
    
    {:noreply, internal_state}
  end

  def handle_message(%Message{type: :stop}, state) do
    {:stop, :normal, state.agent_state}
  end

  def handle_message(_message, state) do
    {:noreply, state.agent_state}
  end

  def handle_heartbeat(state) do
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    IO.puts("🔍 ResearcherAgent terminating")
    :ok
  end

  # Private functions

  defp perform_research(query, depth) do
    # Get research tools
    tools = get_research_tools()
    
    # Build research prompt
    prompt = build_research_prompt(query, depth)
    
    # Use LLM with tools for research
    case Client.chat_with_tools(
      [%{role: "user", content: prompt}],
      tools,
      model: "llama2"
    ) do
      {:ok, response} ->
        process_research_response(response, query)
      
      {:error, _reason} ->
        # Fallback to basic research
        fallback_research(query)
    end
  end

  defp get_research_tools do
    # Get tool definitions for research
    tool_names = ["search", "http_request", "time"]
    
    Enum.flat_map(tool_names, fn name ->
      case Registry.get_tool(name) do
        {:ok, module} -> [apply(module, :to_openai_format, [])]
        _ -> []
      end
    end)
  end

  defp build_research_prompt(query, depth) do
    depth_instruction = case depth do
      :quick -> "Provide a quick overview with 2-3 key points."
      :standard -> "Provide a comprehensive overview with multiple sources."
      :deep -> "Conduct thorough research with extensive sources, analysis, and cross-references."
    end
    
    """
    You are a research specialist. Conduct research on the following topic:
    
    Topic: #{query}
    
    Instructions:
    #{depth_instruction}
    
    Use available tools to:
    1. Search for relevant information
    2. Fetch content from promising sources
    3. Verify facts across multiple sources when possible
    
    Provide your findings in a structured format with:
    - Summary
    - Key findings (bullet points)
    - Sources used
    - Confidence level (high/medium/low)
    """
  end

  defp process_research_response(response, query) do
    content = get_in(response, [:message, :content]) ||
              get_in(response, ["message", "content"]) || ""
    
    %{
      query: query,
      summary: extract_summary(content),
      findings: extract_findings(content),
      sources: extract_sources(content),
      confidence: extract_confidence(content),
      raw_content: content,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp fallback_research(query) do
    %{
      query: query,
      summary: "Research could not be completed due to LLM unavailability.",
      findings: ["Please try again when LLM service is available"],
      sources: [],
      confidence: "low",
      raw_content: "",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp extract_summary(content) do
    case Regex.run(~r/(?:Summary|Overview):\s*(.+?)(?:\n\n|\n[A-Z]|\z)/si, content) do
      [_, summary] -> String.trim(summary)
      _ -> String.slice(content, 0, 200)
    end
  end

  defp extract_findings(content) do
    # Extract bullet points or numbered items
    Regex.scan(~r/(?:^|\n)[\-\*•]\s*(.+)/m, content)
    |> Enum.map(fn [_, finding] -> String.trim(finding) end)
    |> Enum.take(10)
  end

  defp extract_sources(content) do
    # Extract URLs or source references
    Regex.scan(~r/https?:\/\/[^\s\)]+/i, content)
    |> Enum.map(fn [url] -> url end)
    |> Enum.uniq()
  end

  defp extract_confidence(content) do
    cond do
      String.contains?(String.downcase(content), "high confidence") -> "high"
      String.contains?(String.downcase(content), "low confidence") -> "low"
      true -> "medium"
    end
  end
end
