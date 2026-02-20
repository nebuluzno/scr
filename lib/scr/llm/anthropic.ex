defmodule SCR.LLM.Anthropic do
  @moduledoc """
  Anthropic LLM adapter.

  Supports messages, tool use, and streaming.
  """

  alias SCR.LLM.Behaviour

  @behaviour Behaviour

  @default_base_url "https://api.anthropic.com"
  @default_model "claude-3-5-sonnet-latest"
  @default_api_version "2023-06-01"

  @impl true
  def complete(prompt, options \\ []) do
    messages = [%{role: "user", content: prompt}]
    chat(messages, options)
  end

  @impl true
  def chat(messages, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    max_tokens = Keyword.get(options, :max_tokens, 2048)
    system = Keyword.get(options, :system)

    payload =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: normalize_messages(messages)
      }
      |> maybe_put(:system, system)

    case post("/v1/messages", payload, options) do
      {:ok, response} ->
        {:ok, normalize_response(response, model)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def chat_with_tools(messages, tool_definitions, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    max_tokens = Keyword.get(options, :max_tokens, 2048)
    system = Keyword.get(options, :system)

    payload =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: normalize_messages(messages),
        tools: normalize_tools(tool_definitions)
      }
      |> maybe_put(:system, system)

    case post("/v1/messages", payload, options) do
      {:ok, response} ->
        {:ok, normalize_response(response, model)}

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
    max_tokens = Keyword.get(options, :max_tokens, 2048)
    system = Keyword.get(options, :system)

    payload =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: normalize_messages(messages),
        stream: true
      }
      |> maybe_put(:system, system)

    case HTTPoison.post(
           base_url() <> "/v1/messages",
           Jason.encode!(payload),
           headers(),
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
  def embed(_text, _options \\ []) do
    {:error, %{type: :unsupported, message: "Anthropic embedding API not configured"}}
  end

  @impl true
  def ping do
    case list_models() do
      {:ok, _models} -> {:ok, %{status: "available", provider: :anthropic}}
      error -> error
    end
  end

  @impl true
  def list_models do
    case get("/v1/models") do
      {:ok, %{"data" => models}} when is_list(models) -> {:ok, models}
      {:ok, other} -> {:ok, [other]}
      {:error, _} = error -> error
    end
  end

  defp normalize_response(response, model) do
    content_blocks = Map.get(response, "content", [])
    text = extract_text(content_blocks)
    tool_calls = extract_tool_calls(content_blocks)
    usage = Map.get(response, "usage", %{})

    %{
      content: text,
      role: Map.get(response, "role", "assistant"),
      tool_calls: tool_calls,
      model: model,
      finish_reason: Map.get(response, "stop_reason"),
      usage: %{
        prompt_tokens: Map.get(usage, "input_tokens", 0),
        completion_tokens: Map.get(usage, "output_tokens", 0),
        total_tokens: Map.get(usage, "input_tokens", 0) + Map.get(usage, "output_tokens", 0)
      },
      message: %{
        content: text,
        role: Map.get(response, "role", "assistant"),
        tool_calls: tool_calls
      },
      raw: response
    }
  end

  defp extract_text(content_blocks) when is_list(content_blocks) do
    content_blocks
    |> Enum.filter(&(Map.get(&1, "type") == "text"))
    |> Enum.map(&Map.get(&1, "text", ""))
    |> Enum.join("")
  end

  defp extract_text(_), do: ""

  defp extract_tool_calls(content_blocks) when is_list(content_blocks) do
    content_blocks
    |> Enum.filter(&(Map.get(&1, "type") == "tool_use"))
    |> Enum.map(fn block ->
      %{
        id: Map.get(block, "id", "tool_#{System.unique_integer([:positive])}"),
        type: "function",
        function: %{
          name: Map.get(block, "name"),
          arguments: Jason.encode!(Map.get(block, "input", %{}))
        }
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} ->
        %{role: normalize_role(role), content: normalize_content(content)}

      %{"role" => role, "content" => content} ->
        %{role: normalize_role(role), content: normalize_content(content)}
    end)
  end

  defp normalize_role(role) when role in [:assistant, "assistant"], do: "assistant"
  defp normalize_role(_), do: "user"

  defp normalize_content(content) when is_binary(content), do: content

  defp normalize_content(content) when is_list(content) do
    Enum.map(content, fn
      %{type: type, text: text} -> %{type: type, text: text}
      %{"type" => type, "text" => text} -> %{type: type, text: text}
      other when is_binary(other) -> %{type: "text", text: other}
      _ -> %{type: "text", text: inspect(content)}
    end)
  end

  defp normalize_content(content), do: to_string(content)

  defp normalize_tools(tool_definitions) do
    Enum.map(tool_definitions, fn
      %{type: "function", function: function} ->
        %{
          name: Map.get(function, :name) || Map.get(function, "name"),
          description: Map.get(function, :description) || Map.get(function, "description"),
          input_schema: Map.get(function, :parameters) || Map.get(function, "parameters") || %{}
        }

      %{"type" => "function", "function" => function} ->
        %{
          name: Map.get(function, "name"),
          description: Map.get(function, "description"),
          input_schema: Map.get(function, "parameters") || %{}
        }

      other ->
        other
    end)
  end

  defp collect_stream_chunks(request_id, callback, acc, timeout, model) do
    receive do
      {:http_reply, ^request_id, %{status_code: 200, body: _}} ->
        collect_stream_chunks(request_id, callback, acc, timeout, model)

      {:http_reply, ^request_id, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, status: status, body: body}}

      {:stream, ^request_id, %HTTPoison.AsyncChunk{chunk: chunk}} ->
        case parse_stream_chunk(chunk) do
          {:chunk, text} ->
            callback.(text)
            collect_stream_chunks(request_id, callback, acc <> text, timeout, model)

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

  defp parse_stream_chunk(chunk) do
    chunk
    |> String.split("\n")
    |> Enum.reduce(:noop, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" ->
          acc

        String.starts_with?(line, "event: message_stop") ->
          :done

        String.starts_with?(line, "data: ") ->
          data = String.replace_prefix(line, "data: ", "")

          case Jason.decode(data) do
            {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
              {:chunk, text}

            {:ok, %{"type" => "message_stop"}} ->
              :done

            _ ->
              acc
          end

        true ->
          acc
      end
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
      {"x-api-key", api_key()},
      {"anthropic-version", api_version()}
    ]
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp api_key do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:api_key, System.get_env("ANTHROPIC_API_KEY", ""))
  end

  defp api_version do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:anthropic_api_version, @default_api_version)
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
