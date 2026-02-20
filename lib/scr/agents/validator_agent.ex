defmodule SCR.Agents.ValidatorAgent do
  @moduledoc """
  ValidatorAgent - Specialized agent for quality assurance and verification.

  Capabilities:
  - Content validation and fact-checking
  - Quality scoring and assessment
  - Consistency checking
  - Compliance verification
  """

  alias SCR.Message
  alias SCR.LLM.Client

  # Client API

  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :validator, __MODULE__, init_arg)
  end

  # Agent callbacks

  def init(init_arg) do
    IO.puts("✅ ValidatorAgent initialized")

    agent_id = Map.get(init_arg, :agent_id, "validator_1")

    {:ok,
     %{
       agent_id: agent_id,
       validations_performed: 0,
       issues_found: 0,
       validation_history: []
     }}
  end

  def handle_message(%Message{type: :task, payload: %{task: task_data}, from: from}, state) do
    IO.puts("✅ ValidatorAgent received validation task: #{inspect(task_data[:description])}")

    internal_state = state.agent_state

    content = Map.get(task_data, :content, "")
    criteria = Map.get(task_data, :criteria, [:accuracy, :completeness, :clarity])
    task_id = Map.get(task_data, :task_id, UUID.uuid4())

    # Perform validation
    result = validate_content(content, criteria)

    # Send result back
    result_msg =
      Message.result(state.agent_id, from, %{
        task_id: task_id,
        validation: result,
        status: :completed,
        agent_type: :validator
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    new_state = %{
      internal_state
      | validations_performed: internal_state.validations_performed + 1,
        issues_found: internal_state.issues_found + length(result.issues),
        validation_history: [task_id | internal_state.validation_history] |> Enum.take(100)
    }

    {:noreply, new_state}
  end

  def handle_message(
        %Message{type: :validate, payload: %{content: content, criteria: criteria}, from: from},
        state
      ) do
    IO.puts("✅ ValidatorAgent validating content")

    internal_state = state.agent_state

    result = validate_content(content, criteria || default_criteria())

    result_msg =
      Message.result(state.agent_id, from, %{
        validation: result,
        status: :completed
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    {:noreply, internal_state}
  end

  def handle_message(
        %Message{type: :fact_check, payload: %{content: content, claims: claims}, from: from},
        state
      ) do
    IO.puts("✅ ValidatorAgent fact-checking claims")

    internal_state = state.agent_state

    result = fact_check(content, claims)

    result_msg =
      Message.result(state.agent_id, from, %{
        fact_check: result,
        status: :completed
      })

    SCR.Supervisor.send_to_agent(from, result_msg)

    {:noreply, internal_state}
  end

  def handle_message(
        %Message{type: :quality_score, payload: %{content: content}, from: from},
        state
      ) do
    IO.puts("✅ ValidatorAgent calculating quality score")

    internal_state = state.agent_state

    score = calculate_quality_score(content)

    result_msg =
      Message.result(state.agent_id, from, %{
        quality_score: score,
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
    IO.puts("✅ ValidatorAgent terminating")
    :ok
  end

  # Private functions

  defp validate_content(content, criteria) do
    prompt = build_validation_prompt(content, criteria)

    case Client.chat([%{role: "user", content: prompt}], model: "llama2") do
      {:ok, response} ->
        process_validation_response(response, criteria)

      {:error, _reason} ->
        fallback_validation(content, criteria)
    end
  end

  defp fact_check(content, claims) do
    claims_text = Enum.map_join(claims, "\n", fn claim -> "- #{claim}" end)

    prompt = """
    You are a fact-checker. Verify the following claims against the provided content.

    Content:
    #{String.slice(content, 0, 5000)}

    Claims to verify:
    #{claims_text}

    For each claim, provide:
    1. Verdict: VERIFIED, UNVERIFIED, or FALSE
    2. Evidence from the content
    3. Confidence level (high/medium/low)

    Format your response as a structured list.
    """

    case Client.chat([%{role: "user", content: prompt}], model: "llama2") do
      {:ok, response} ->
        parse_fact_check_response(get_content(response))

      {:error, _} ->
        %{
          results:
            Enum.map(claims, fn claim ->
              %{claim: claim, verdict: "UNVERIFIED", confidence: "low"}
            end),
          overall_confidence: "low"
        }
    end
  end

  defp calculate_quality_score(content) do
    # Calculate various quality metrics
    word_count = count_words(content)
    sentence_count = count_sentences(content)
    paragraph_count = count_paragraphs(content)

    # Basic quality indicators
    avg_sentence_length = if sentence_count > 0, do: word_count / sentence_count, else: 0

    # Use LLM for semantic quality assessment
    semantic_score = get_semantic_score(content)

    %{
      overall_score: calculate_overall_score(word_count, avg_sentence_length, semantic_score),
      metrics: %{
        word_count: word_count,
        sentence_count: sentence_count,
        paragraph_count: paragraph_count,
        avg_sentence_length: Float.round(avg_sentence_length, 1),
        semantic_quality: semantic_score
      },
      recommendations: generate_recommendations(word_count, avg_sentence_length, semantic_score)
    }
  end

  defp build_validation_prompt(content, criteria) do
    criteria_text = Enum.map_join(criteria, "\n", fn c -> "- #{Atom.to_string(c)}" end)

    """
    You are a quality assurance validator. Analyze the following content against these criteria:

    Criteria:
    #{criteria_text}

    Content:
    #{String.slice(content, 0, 5000)}

    Provide:
    1. An overall pass/fail verdict
    2. A score from 0-100 for each criterion
    3. A list of specific issues found (if any)
    4. Suggestions for improvement

    Format your response clearly with sections for each criterion.
    """
  end

  defp process_validation_response(response, criteria) do
    content = get_content(response)

    %{
      verdict: extract_verdict(content),
      scores: extract_scores(content, criteria),
      issues: extract_issues(content),
      suggestions: extract_suggestions(content),
      passed: String.downcase(content) =~ "pass",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp fallback_validation(content, criteria) do
    # Basic validation without LLM
    word_count = count_words(content)

    scores =
      Enum.map(criteria, fn criterion ->
        score =
          case criterion do
            # Cannot verify without LLM
            :accuracy -> 50
            # Rough proxy
            :completeness -> min(100, word_count * 2)
            :clarity -> if word_count > 50, do: 60, else: 40
            :consistency -> 50
            _ -> 50
          end

        {criterion, score}
      end)
      |> Map.new()

    %{
      verdict: "UNVERIFIED",
      scores: scores,
      issues: ["LLM unavailable - manual verification required"],
      suggestions: ["Please verify content manually"],
      passed: false,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp parse_fact_check_response(content) do
    results =
      Regex.scan(~r/(?:Claim:?\s*)?(.+?)\s*[-:]\s*(VERIFIED|UNVERIFIED|FALSE)/i, content)
      |> Enum.map(fn [_, claim, verdict] ->
        %{
          claim: String.trim(claim),
          verdict: String.upcase(verdict),
          confidence: extract_confidence_near(content, claim)
        }
      end)

    %{
      results: results,
      overall_confidence: determine_overall_confidence(results)
    }
  end

  defp get_semantic_score(content) do
    prompt = """
    Rate the quality of the following content on a scale of 0-100.
    Consider clarity, coherence, and informativeness.

    Content:
    #{String.slice(content, 0, 2000)}

    Respond with only a number between 0 and 100.
    """

    case Client.chat([%{role: "user", content: prompt}], model: "llama2") do
      {:ok, response} ->
        content = get_content(response)

        case Integer.parse(content) do
          {score, _} when score >= 0 and score <= 100 -> score
          _ -> 50
        end

      {:error, _} ->
        50
    end
  end

  defp calculate_overall_score(word_count, avg_sentence_length, semantic_score) do
    # Weighted combination of metrics
    length_score =
      cond do
        word_count < 50 -> 30
        word_count < 200 -> 60
        word_count < 500 -> 80
        true -> 70
      end

    sentence_score =
      cond do
        avg_sentence_length < 10 -> 60
        avg_sentence_length < 25 -> 100
        avg_sentence_length < 40 -> 80
        true -> 50
      end

    trunc(length_score * 0.2 + sentence_score * 0.3 + semantic_score * 0.5)
  end

  defp generate_recommendations(word_count, avg_sentence_length, semantic_score) do
    recommendations = []

    recommendations =
      if word_count < 100 do
        ["Consider adding more content for better coverage" | recommendations]
      else
        recommendations
      end

    recommendations =
      if avg_sentence_length > 30 do
        ["Consider breaking up long sentences for better readability" | recommendations]
      else
        recommendations
      end

    recommendations =
      if semantic_score < 60 do
        ["Content quality could be improved - consider revising for clarity" | recommendations]
      else
        recommendations
      end

    if recommendations == [], do: ["Content meets quality standards"], else: recommendations
  end

  defp extract_verdict(content) do
    cond do
      String.downcase(content) =~ "pass" -> "PASS"
      String.downcase(content) =~ "fail" -> "FAIL"
      true -> "NEEDS REVIEW"
    end
  end

  defp extract_scores(content, criteria) do
    Enum.map(criteria, fn criterion ->
      pattern = "#{criterion}.*?(\\d+)"

      score =
        case Regex.run(~r/#{pattern}/i, content) do
          [_, score_str] ->
            case Integer.parse(score_str) do
              {s, _} when s >= 0 and s <= 100 -> s
              _ -> 50
            end

          _ ->
            50
        end

      {criterion, score}
    end)
    |> Map.new()
  end

  defp extract_issues(content) do
    Regex.scan(~r/(?:Issue|Problem):\s*(.+)/i, content)
    |> Enum.map(fn [_, issue] -> String.trim(issue) end)
  end

  defp extract_suggestions(content) do
    Regex.scan(~r/(?:Suggestion|Recommendation):\s*(.+)/i, content)
    |> Enum.map(fn [_, suggestion] -> String.trim(suggestion) end)
  end

  defp extract_confidence_near(content, _claim) do
    cond do
      String.downcase(content) =~ "high confidence" -> "high"
      String.downcase(content) =~ "low confidence" -> "low"
      true -> "medium"
    end
  end

  defp determine_overall_confidence(results) do
    if Enum.empty?(results) do
      "low"
    else
      verified_count = Enum.count(results, fn r -> r.verdict == "VERIFIED" end)
      ratio = verified_count / length(results)

      cond do
        ratio >= 0.8 -> "high"
        ratio >= 0.5 -> "medium"
        true -> "low"
      end
    end
  end

  defp get_content(response) do
    get_in(response, [:message, :content]) ||
      get_in(response, ["message", "content"]) ||
      ""
  end

  defp default_criteria, do: [:accuracy, :completeness, :clarity]

  defp count_words(text) do
    text
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp count_sentences(text) do
    text
    |> String.split(~r/[.!?]+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp count_paragraphs(text) do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end
end
