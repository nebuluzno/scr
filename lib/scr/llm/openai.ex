defmodule SCR.LLM.OpenAI do
  @moduledoc """
  OpenAI LLM adapter.

  Supports chat completions, tool calling, embeddings, and streaming.
  """

  alias SCR.LLM.Behaviour

  @behaviour Behaviour

  @default_base_url "https://api.openai.com"
  @default_model "gpt-4o-mini"

  @impl true
  def complete(prompt, options \\ []) do
    messages = [%{role: "user", content: prompt}]

    case chat(messages, options) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end

  @impl true
  def chat(messages, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)

    payload = %{
      model: model,
      messages: normalize_messages(messages),
      temperature: temperature,
      max_tokens: max_tokens,
      stream: false
    }

    case post("/v1/chat/completions", payload, options) do
      {:ok, %{"choices" => [first | _], "usage" => usage} = raw} ->
        {:ok, chat_response_from_choice(first, model, usage, raw)}

      {:ok, %{"choices" => [first | _]} = raw} ->
        {:ok, chat_response_from_choice(first, model, %{}, raw)}

      {:ok, %{"error" => error}} ->
        {:error, normalize_api_error(error)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def chat_with_tools(messages, tool_definitions, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)

    payload = %{
      model: model,
      messages: normalize_messages(messages),
      tools: tool_definitions,
      tool_choice: "auto",
      temperature: temperature,
      max_tokens: max_tokens,
      stream: false
    }

    case post("/v1/chat/completions", payload, options) do
      {:ok, %{"choices" => [first | _], "usage" => usage} = raw} ->
        {:ok, chat_response_from_choice(first, model, usage, raw)}

      {:ok, %{"choices" => [first | _]} = raw} ->
        {:ok, chat_response_from_choice(first, model, %{}, raw)}

      {:ok, %{"error" => error}} ->
        {:error, normalize_api_error(error)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def stream(prompt, callback, options \\ []) when is_function(callback, 1) do
    messages = [%{role: "user", content: prompt}]
    chat_stream(messages, callback, options)
  end

  @impl true
  def chat_stream(messages, callback, options \\ []) when is_function(callback, 1) do
    options = Behaviour.merge_options(options)
    timeout = Keyword.get(options, :timeout, 120_000)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)

    payload = %{
      model: model,
      messages: normalize_messages(messages),
      temperature: temperature,
      max_tokens: max_tokens,
      stream: true
    }

    url = base_url() <> "/v1/chat/completions"

    case HTTPoison.post(url, Jason.encode!(payload), headers(),
           timeout: timeout,
           stream_to: self()
         ) do
      {:ok, %{id: request_id}} ->
        collect_stream_chunks(request_id, callback, "", timeout, model)

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end

  @impl true
  def embed(text, options \\ []) do
    model =
      options
      |> Keyword.get(:model)
      |> case do
        nil -> "text-embedding-3-small"
        value -> value
      end

    input = if is_list(text), do: text, else: [text]
    payload = %{model: model, input: input}

    case post("/v1/embeddings", payload, options) do
      {:ok, %{"data" => data} = raw} ->
        {:ok, %{embedding: data, model: model, raw: raw}}

      {:ok, %{"error" => error}} ->
        {:error, normalize_api_error(error)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def ping do
    case get("/v1/models") do
      {:ok, %{"data" => _}} ->
        {:ok, %{status: "available", provider: :openai}}

      {:ok, %{"error" => error}} ->
        {:error, normalize_api_error(error)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def list_models do
    case get("/v1/models") do
      {:ok, %{"data" => models}} when is_list(models) ->
        {:ok, models}

      {:ok, %{"error" => error}} ->
        {:error, normalize_api_error(error)}

      {:error, _} = error ->
        error
    end
  end

  defp collect_stream_chunks(request_id, callback, acc, timeout, model) do
    receive do
      {:http_reply, ^request_id, %{status_code: 200, body: _}} ->
        collect_stream_chunks(request_id, callback, acc, timeout, model)

      {:http_reply, ^request_id, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, status: status, body: body}}

      {:stream, ^request_id, %HTTPoison.AsyncChunk{chunk: chunk}} ->
        case parse_stream_chunk(chunk) do
          {:chunk, content} ->
            callback.(content)
            collect_stream_chunks(request_id, callback, acc <> content, timeout, model)

          :done ->
            {:ok, %{content: acc, model: model, finish_reason: "stop", streamed: true}}

          :noop ->
            collect_stream_chunks(request_id, callback, acc, timeout, model)
        end

      {:stream, ^request_id, %HTTPoison.AsyncEnd{}} ->
        {:ok, %{content: acc, model: model, finish_reason: "stop", streamed: true}}
    after
      timeout ->
        {:error, %{type: :timeout, message: "Stream timed out after #{timeout}ms"}}
    end
  end

  defp parse_stream_chunk(chunk) when is_binary(chunk) do
    chunk
    |> String.split("\n")
    |> Enum.find_value(:noop, fn line ->
      case String.trim(line) do
        "" ->
          false

        "data: [DONE]" ->
          :done

        "data: " <> json ->
          case Jason.decode(json) do
            {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}}
            when is_binary(content) ->
              {:chunk, content}

            {:ok, _} ->
              false

            _ ->
              false
          end

        _ ->
          false
      end
    end)
  end

  defp chat_response_from_choice(choice, model, usage, raw) do
    message = Map.get(choice, "message", %{})
    tool_calls = normalize_tool_calls(Map.get(message, "tool_calls", []))

    %{
      content: Map.get(message, "content", ""),
      role: Map.get(message, "role", "assistant"),
      tool_calls: tool_calls,
      model: model,
      finish_reason: Map.get(choice, "finish_reason"),
      usage: %{
        prompt_tokens: Map.get(usage, "prompt_tokens", 0),
        completion_tokens: Map.get(usage, "completion_tokens", 0),
        total_tokens: Map.get(usage, "total_tokens", 0)
      },
      message: %{
        content: Map.get(message, "content", ""),
        role: Map.get(message, "role", "assistant"),
        tool_calls: tool_calls
      },
      raw: raw
    }
  end

  defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn call ->
      function = Map.get(call, "function", %{})

      %{
        id: Map.get(call, "id"),
        type: Map.get(call, "type", "function"),
        function: %{
          name: Map.get(function, "name"),
          arguments: Map.get(function, "arguments", "{}")
        }
      }
    end)
  end

  defp normalize_tool_calls(_), do: []

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} ->
        %{role: role, content: content}

      %{"role" => role, "content" => content} ->
        %{role: role, content: content}

      other ->
        other
    end)
  end

  defp post(path, payload, options) do
    timeout = Keyword.get(options, :timeout, 30_000)

    case HTTPoison.post(base_url() <> path, Jason.encode!(payload), headers(), timeout: timeout) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, status: status, body: body}}

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end

  defp get(path) do
    case HTTPoison.get(base_url() <> path, headers(), timeout: 15_000) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, status: status, body: body}}

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key()}"}
    ]
  end

  defp normalize_api_error(error) when is_map(error) do
    %{
      type: :openai_error,
      message: Map.get(error, "message", "OpenAI request failed"),
      code: Map.get(error, "code")
    }
  end

  defp normalize_api_error(error), do: %{type: :openai_error, message: inspect(error)}

  defp api_key do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:api_key, System.get_env("OPENAI_API_KEY", ""))
  end

  defp base_url do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:base_url, @default_base_url)
  end

  defp default_model do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:default_model, @default_model)
  end
end
