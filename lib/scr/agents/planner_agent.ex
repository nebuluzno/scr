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

  require Logger

  alias SCR.Message
  alias SCR.Agents.WorkerAgent
  alias SCR.Agents.ResearcherAgent
  alias SCR.Agents.WriterAgent
  alias SCR.Agents.ValidatorAgent
  alias SCR.AgentContext
  alias SCR.LLM.Client
  alias SCR.TaskQueue
  alias SCR.Trace

  @allowed_agent_types %{
    "worker" => :worker,
    "researcher" => :researcher,
    "writer" => :writer,
    "validator" => :validator
  }

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

    {:ok,
     %{
       agent_id: agent_id,
       current_task: nil,
       subtasks: [],
       worker_pool: [],
       results: [],
       status: :idle
     }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: _from}, state) do
    Trace.put_metadata(Trace.from_task(task_data, state.agent_id))
    Logger.info("planner.task.received description=#{inspect(task_data[:description])}")
    internal_state = state.agent_state

    task_data = normalize_main_task(task_data)
    priority = TaskQueue.normalize_priority(Map.get(task_data, :priority, :normal))
    queue_server = task_queue_server()

    if cluster_backpressured?() do
      Logger.warning("planner.task.rejected cluster_backpressured task_id=#{task_data.task_id}")

      _ =
        AgentContext.upsert(to_string(task_data.task_id), %{
          description: task_data.description,
          priority: priority,
          status: :rejected_backpressure,
          trace_id: task_data.trace_id
        })

      {:noreply, internal_state}
    else
      case TaskQueue.enqueue(task_data, priority, queue_server) do
        {:ok, _} ->
          _ =
            AgentContext.upsert(to_string(task_data.task_id), %{
              description: task_data.description,
              priority: priority,
              status: :queued,
              trace_id: task_data.trace_id
            })

          Logger.info("planner.task.enqueued task_id=#{task_data.task_id} priority=#{priority}")
          {:noreply, maybe_start_next_task(internal_state, state.agent_id)}

        {:error, :queue_full} ->
          Logger.warning("planner.task.rejected queue_full task_id=#{task_data.task_id}")
          _ = AgentContext.set_status(to_string(task_data.task_id), :rejected_queue_full)
          {:noreply, internal_state}
      end
    end
  end

  def handle_message(
        %Message{type: :status, payload: %{status: %{action: :dispatch_next}}},
        state
      ) do
    internal_state = state.agent_state
    {:noreply, maybe_start_next_task(internal_state, state.agent_id)}
  end

  def handle_message(%Message{type: :result, payload: %{result: result_data}, from: from}, state) do
    Trace.put_metadata(Trace.from_task(result_data, state.agent_id))
    Logger.info("planner.result.received from=#{from}")

    # Get internal state from context
    internal_state = state.agent_state

    # Check if it's a worker result or critic result
    worker_id = result_data[:task_id]
    _ = worker_id

    new_results = [%{from: from, data: result_data} | internal_state.results]

    # Check if all subtasks are complete
    if length(new_results) >= length(internal_state.subtasks) do
      Logger.info("planner.subtasks.completed count=#{length(new_results)}")

      # Send to CriticAgent for evaluation
      critic_msg =
        Message.result(state.agent_id, "critic_1", %{
          results: new_results,
          task: internal_state.current_task
        })

      SCR.Supervisor.send_to_agent("critic_1", critic_msg)

      {:noreply, %{internal_state | results: new_results, status: :evaluating}}
    else
      {:noreply, %{internal_state | results: new_results}}
    end
  end

  def handle_message(
        %Message{type: :critique, payload: %{critique: critique_data}, from: _from},
        state
      ) do
    Logger.info("planner.critique.received revision=#{critique_data[:revision_requested]}")

    # Get internal state from context
    internal_state = state.agent_state

    # Check if revision is requested
    if critique_data[:revision_requested] do
      Logger.warning("planner.critique.revision_requested")
      new_state = execute_subtasks(%{internal_state | results: []})
      {:noreply, %{new_state | status: :revising}}
    else
      Logger.info("planner.task.approved")

      # Store final results in memory
      store_in_memory(:result, %{
        task: internal_state.current_task,
        results: internal_state.results,
        critique: critique_data
      })

      current_task_id = to_string(Map.get(internal_state.current_task || %{}, :task_id, ""))
      _ = AgentContext.set_status(current_task_id, :completed)

      _ =
        AgentContext.upsert(current_task_id, %{
          critique: critique_data,
          results: internal_state.results
        })

      reset_state = %{
        internal_state
        | current_task: nil,
          subtasks: [],
          worker_pool: [],
          results: [],
          status: :idle
      }

      {:noreply, maybe_start_next_task(reset_state, state.agent_id)}
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

  def handle_health_check(state) do
    queue_stats =
      try do
        SCR.TaskQueue.stats()
      rescue
        _ -> %{size: 0, high: 0, normal: 0, low: 0}
      end

    %{
      healthy: true,
      current_task_id: get_in(state, [:current_task, :task_id]),
      pending_subtasks: length(Map.get(state, :subtasks, [])),
      queue_size: Map.get(queue_stats, :size, 0),
      queue_high: Map.get(queue_stats, :high, 0)
    }
  end

  def terminate(_reason, _state) do
    IO.puts("🧠 PlannerAgent terminating")
    :ok
  end

  # Private functions

  defp decompose_task_with_llm(task_data) do
    description = Map.get(task_data, :description, "")

    Logger.info("planner.decompose.start description=#{inspect(description)}")

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
        Logger.warning("planner.decompose.fallback reason=#{inspect(reason)}")
        fallback_decompose_task(description)
    end
  end

  defp parse_llm_subtasks(llm_response) do
    case Jason.decode(llm_response) do
      {:ok, subtasks} when is_list(subtasks) ->
        Enum.map(subtasks, fn subtask ->
          agent_type = normalize_agent_type(Map.get(subtask, "agent_type", "worker"))

          Map.merge(
            %{
              task_id: UUID.uuid4(),
              agent_type: agent_type,
              agent_id: "#{agent_type}_#{:rand.uniform(100)}",
              priority: Map.get(subtask, "priority", 3)
            },
            subtask
          )
        end)

      _ ->
        # If JSON parsing fails, try to extract subtasks manually
        Logger.warning("planner.decompose.parse_failed_using_fallback")
        fallback_decompose_task("")
    end
  rescue
    _ -> fallback_decompose_task("")
  end

  @doc false
  def normalize_agent_type(value) when is_atom(value) do
    if value in Map.values(@allowed_agent_types), do: value, else: :worker
  end

  def normalize_agent_type(value) when is_binary(value) do
    value
    |> String.downcase()
    |> then(&Map.get(@allowed_agent_types, &1, :worker))
  end

  def normalize_agent_type(_), do: :worker

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

  defp maybe_start_next_task(state, planner_agent_id) do
    if planner_busy?(state) or TaskQueue.paused?(task_queue_server()) do
      state
    else
      case TaskQueue.dequeue(task_queue_server()) do
        {:ok, next_task} ->
          start_main_task(next_task, state, planner_agent_id)

        :empty ->
          %{state | status: :idle}
      end
    end
  end

  defp planner_busy?(state) do
    state.status in [:planning, :evaluating, :revising] and not is_nil(state.current_task)
  end

  defp start_main_task(task_data, state, _planner_agent_id) do
    subtasks = decompose_task_with_llm(task_data)

    _ =
      AgentContext.upsert(to_string(task_data.task_id), %{
        description: task_data.description,
        status: :planning,
        subtasks: subtasks,
        trace_id: task_data.trace_id
      })

    store_in_memory(:task, %{task_data: task_data, subtasks: subtasks})

    state
    |> Map.merge(%{
      current_task: task_data,
      subtasks: subtasks,
      worker_pool: [],
      results: [],
      status: :planning
    })
    |> execute_subtasks()
  end

  defp normalize_main_task(task_data) do
    %{
      task_id: Map.get(task_data, :task_id, UUID.uuid4()),
      description: Map.get(task_data, :description, ""),
      type: Map.get(task_data, :type, :general),
      priority: Map.get(task_data, :priority, :normal),
      max_workers: Map.get(task_data, :max_workers, 2),
      trace_id: Map.get(task_data, :trace_id, UUID.uuid4())
    }
  end

  defp task_queue_server do
    SCR.ConfigCache.get(:task_queue, []) |> Keyword.get(:server, SCR.TaskQueue)
  end

  defp execute_subtasks(state) do
    # Sort subtasks by priority
    sorted_subtasks = Enum.sort_by(state.subtasks, & &1.priority)

    started_workers =
      Enum.reduce(sorted_subtasks, [], fn subtask, acc ->
        agent_type = Map.get(subtask, :agent_type, :worker)
        agent_id = Map.get(subtask, :agent_id, "#{agent_type}_#{:rand.uniform(100)}")
        agent_module = Map.get(@agent_modules, agent_type, WorkerAgent)

        case SCR.Supervisor.start_agent(
               agent_id,
               agent_type,
               agent_module,
               %{agent_id: agent_id}
             ) do
          {:ok, _pid} ->
            # Give agent time to start.
            Process.sleep(100)

            task_msg =
              Message.task(state.agent_id, agent_id, %{
                task_id: subtask.task_id,
                parent_task_id: get_in(state, [:current_task, :task_id]),
                subtask_id: subtask.task_id,
                trace_id: get_in(state, [:current_task, :trace_id]),
                type: agent_type,
                description: subtask.description
              })

            SCR.Supervisor.send_to_agent(agent_id, task_msg)
            Logger.info("planner.subtask.assigned agent_type=#{agent_type} agent_id=#{agent_id}")
            [agent_id | acc]

          {:error, reason} ->
            Logger.warning(
              "planner.subtask.start_failed agent_type=#{agent_type} agent_id=#{agent_id} reason=#{inspect(reason)}"
            )

            acc
        end
      end)

    %{state | worker_pool: Enum.reverse(started_workers)}
  end

  defp cluster_backpressured? do
    SCR.Distributed.enabled?() and SCR.Distributed.cluster_backpressured?()
  rescue
    _ -> false
  end

  defp store_in_memory(type, data) do
    # Send to memory agent
    msg =
      case type do
        :task -> Message.task("planner_1", "memory_1", %{task: data})
        :result -> Message.result("planner_1", "memory_1", %{result: data})
      end

    SCR.Supervisor.send_to_agent("memory_1", msg)
  end
end
