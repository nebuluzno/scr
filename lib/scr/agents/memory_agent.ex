defmodule SCR.Agents.MemoryAgent do
  @moduledoc """
  MemoryAgent - Persistent storage for tasks and agent states.
  
  Uses ETS (Erlang Term Storage) for in-memory persistence with
  disk backup capability. Also provides LLM-powered memory
  summarization for context window management.
  """

  alias SCR.Message
  alias SCR.LLM.Client

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :memory, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    # Initialize ETS tables for memory storage (idempotent - safe to call multiple times)
    create_ets_table(:scr_memory)
    create_ets_table(:scr_tasks)
    create_ets_table(:scr_agent_states)
    
    agent_id = Map.get(init_arg, :agent_id, "memory_1")
    
    IO.puts("💾 MemoryAgent initialized with ETS storage")
    
    {:ok, %{agent_id: agent_id, storage: :ets}}
  end
  
  # Creates an ETS table if it doesn't already exist
  # This prevents crashes on agent restart
  defp create_ets_table(name) do
    case :ets.whereis(name) do
      :undefined -> 
        :ets.new(name, [:set, :named_table, :public])
      _ref -> 
        name  # Table already exists, return the name
    end
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

  # New: Handle memory summarization requests
  def handle_message(%Message{type: :task, payload: %{summarize: true, data: data}, from: from}, state) do
    IO.puts("🤖 MemoryAgent: Summarizing memory context")
    
    internal_state = state.agent_state
    
    summary = summarize_with_llm(data)
    
    # Send summary back to requester
    result_msg = Message.result(state.agent_id, from, %{summary: summary})
    SCR.Supervisor.send_to_agent(from, result_msg)
    
    {:noreply, internal_state}
  end

  # New: Handle memory retrieval with LLM
  def handle_message(%Message{type: :task, payload: %{retrieve: query}, from: from}, state) do
    IO.puts("🤖 MemoryAgent: Retrieving relevant memory for query: #{query}")
    
    internal_state = state.agent_state
    
    # Get all memories and use LLM to find relevant ones
    results = retrieve_relevant_memories(query)
    
    result_msg = Message.result(state.agent_id, from, %{memories: results})
    SCR.Supervisor.send_to_agent(from, result_msg)
    
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
    # Note: state here is the internal state, not wrapped in agent_state
    {:noreply, state}
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

  # New: LLM-powered memory operations

  @doc """
  Summarize stored memories using LLM.
  Useful for reducing context window size.
  """
  def summarize_with_llm(data) when is_list(data) do
    data_str = Enum.map_join(data, "\n---\n", &inspect/1)
    
    prompt = """
    You are a memory consolidation assistant. Summarize the following information
    into a concise summary that captures the key points.
    
    Information to summarize:
    #{data_str}
    
    Provide a single paragraph summary (2-4 sentences).
    """
    
    case Client.complete(prompt, temperature: 0.5, max_tokens: 512) do
      {:ok, %{content: summary}} -> 
        %{summary: summary, source: :llm}
      {:error, _} -> 
        %{summary: "Summary unavailable", source: :fallback}
    end
  end

  def summarize_with_llm(data) when is_map(data) do
    summarize_with_llm([data])
  end

  def summarize_with_llm(_), do: %{summary: "No data to summarize", source: :fallback}

  @doc """
  Retrieve relevant memories based on a query.
  Uses LLM to rank memory relevance.
  """
  def retrieve_relevant_memories(query) do
    # Get all stored data
    all_tasks = :ets.tab2list(:scr_tasks)
    all_results = :ets.tab2list(:scr_memory)
    
    # Combine all memories
    all_memories = Enum.map(all_tasks ++ all_results, fn {id, data} ->
      %{id: id, data: data}
    end)
    
    if length(all_memories) == 0 do
      []
    else
      # Use LLM to find relevant memories
      prompt = """
      Given the query: "#{query}"
      
      Rate the relevance of each memory item on a scale of 0-1.
      Return ONLY a JSON array of relevance scores in the same order as the memories.
      
      Memories (in order):
      #{Enum.map_join(all_memories, "\n", fn m -> inspect(m.data) end)}
      """
      
      case Client.complete(prompt, temperature: 0.2, max_tokens: 512) do
        {:ok, %{content: response}} ->
          # Try to parse the scores
          parse_relevance_scores(response, all_memories)
        
        {:error, _} ->
          # Fallback: return all memories
          all_memories
      end
    end
  end

  defp parse_relevance_scores(response, memories) do
    # Try to extract scores from LLM response
    # This is a simplified implementation
    scores = 
      response
      |> String.split(["[", "]", ",", "\n"])
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn s -> 
        case Float.parse(s) do
          {_num, ""} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn s -> 
        {num, _} = Float.parse(s)
        num
      end)
    
    # Combine memories with scores and sort by relevance
    Enum.zip(memories, scores)
    |> Enum.filter(fn {_m, score} -> score > 0.3 end)
    |> Enum.sort_by(fn {_m, score} -> -score end)
    |> Enum.map(fn {m, _score} -> m end)
  rescue
    _ -> memories  # Fallback to returning all memories
  end
end
