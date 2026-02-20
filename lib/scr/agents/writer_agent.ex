defmodule SCR.Agents.WriterAgent do
  @moduledoc """
  WriterAgent - Specialized agent for content generation and writing tasks.

  Capabilities:
  - Article and report writing
  - Content summarization
  - Text transformation and formatting
  - Multi-format output (markdown, HTML, plain text)
  """

  alias SCR.Message
  alias SCR.LLM.Client

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :writer, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("✍️ WriterAgent initialized")

    agent_id = Map.get(init_arg, :agent_id, "writer_1")

    {:ok,
     %{
       agent_id: agent_id,
       current_draft: nil,
       completed_pieces: [],
       style: Map.get(init_arg, :style, :professional),
       word_count: 0
     }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: from}, state) do
    IO.puts("✍️ WriterAgent received writing task: #{inspect(task_data[:description])}")

    internal_state = state.agent_state

    description = Map.get(task_data, :description, "")
    task_id = Map.get(task_data, :task_id, UUID.uuid4())
    format = Map.get(task_data, :format, :markdown)
    style = Map.get(task_data, :style, internal_state.style)

    # Generate content
    result = generate_content(description, format, style)

    # Send result back
    result_msg =
      Message.result(state.agent_id, from, %{
        task_id: task_id,
        result: result,
        status: :completed,
        agent_type: :writer
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    new_state = %{
      internal_state
      | current_draft: nil,
        completed_pieces: [task_id | internal_state.completed_pieces],
        word_count: internal_state.word_count + (result.word_count || 0)
    }

    {:noreply, new_state}
  end

  def handle_message(
        %Message{
          type: :write,
          payload: %{topic: topic, format: format, style: style},
          from: from
        },
        state
      ) do
    IO.puts("✍️ WriterAgent writing about: #{topic}")

    internal_state = state.agent_state

    result = generate_content(topic, format || :markdown, style || internal_state.style)

    result_msg =
      Message.result(state.agent_id, from, %{
        topic: topic,
        content: result,
        status: :completed
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    {:noreply, internal_state}
  end

  def handle_message(
        %Message{
          type: :summarize,
          payload: %{content: content, max_length: max_length},
          from: from
        },
        state
      ) do
    IO.puts("✍️ WriterAgent summarizing content")

    internal_state = state.agent_state

    result = summarize_content(content, max_length)

    result_msg =
      Message.result(state.agent_id, from, %{
        summary: result,
        status: :completed
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    {:noreply, internal_state}
  end

  def handle_message(
        %Message{
          type: :transform,
          payload: %{content: content, target_format: target},
          from: from
        },
        state
      ) do
    IO.puts("✍️ WriterAgent transforming content to #{target}")

    internal_state = state.agent_state

    result = transform_content(content, target)

    result_msg =
      Message.result(state.agent_id, from, %{
        transformed: result,
        format: target,
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
    IO.puts("✍️ WriterAgent terminating")
    :ok
  end

  # Private functions

  defp generate_content(topic, format, style) do
    prompt = build_writing_prompt(topic, format, style)

    case Client.chat([%{role: "user", content: prompt}], model: "llama2") do
      {:ok, response} ->
        process_writing_response(response, topic, format)

      {:error, _reason} ->
        fallback_content(topic, format)
    end
  end

  defp summarize_content(content, max_length) do
    max_len = max_length || 200

    prompt = """
    Summarize the following content in approximately #{max_len} words or less.
    Focus on the key points and main ideas.

    Content:
    #{String.slice(content, 0, 5000)}
    """

    case Client.chat([%{role: "user", content: prompt}], model: "llama2") do
      {:ok, response} ->
        get_content(response)

      {:error, _} ->
        # Simple fallback: take first sentences
        sentences =
          content
          |> String.split(~r/[.!?]+/)
          |> Enum.take(3)

        Enum.join(sentences, ". ") <> "."
    end
  end

  defp transform_content(content, target_format) do
    prompt = """
    Transform the following content to #{target_format} format.
    Preserve the meaning and key information.

    Content:
    #{String.slice(content, 0, 5000)}
    """

    case Client.chat([%{role: "user", content: prompt}], model: "llama2") do
      {:ok, response} ->
        get_content(response)

      {:error, _} ->
        content
    end
  end

  defp build_writing_prompt(topic, format, style) do
    format_instruction =
      case format do
        :markdown ->
          "Format the output in Markdown with appropriate headers, lists, and emphasis."

        :html ->
          "Format the output as clean HTML with semantic tags."

        :plain ->
          "Format as plain text with clear paragraphs."

        :json ->
          "Format as a JSON object with 'title', 'content', and 'metadata' fields."

        _ ->
          "Format the output clearly and readably."
      end

    style_instruction =
      case style do
        :professional -> "Use a professional, authoritative tone."
        :casual -> "Use a friendly, conversational tone."
        :technical -> "Use a technical, precise tone with appropriate terminology."
        :creative -> "Use a creative, engaging tone with vivid language."
        _ -> "Use a balanced, neutral tone."
      end

    """
    You are a skilled writer. Write content about the following topic:

    Topic: #{topic}

    Style: #{style_instruction}

    Format: #{format_instruction}

    Ensure the content is:
    - Well-structured and organized
    - Clear and engaging
    - Factually accurate
    - Appropriately formatted for the requested output
    """
  end

  defp process_writing_response(response, topic, format) do
    content = get_content(response)

    %{
      topic: topic,
      content: content,
      format: format,
      word_count: count_words(content),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp fallback_content(topic, format) do
    content = """
    # #{topic}

    Content generation is currently unavailable. Please try again later.

    This is a placeholder for content about: #{topic}
    """

    %{
      topic: topic,
      content: content,
      format: format,
      word_count: count_words(content),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp get_content(response) do
    get_in(response, [:message, :content]) ||
      get_in(response, ["message", "content"]) ||
      ""
  end

  defp count_words(text) do
    text
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end
end
