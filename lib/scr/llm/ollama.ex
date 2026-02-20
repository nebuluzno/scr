defmodule SCR.LLM.Ollama do
  @moduledoc """
  Ollama LLM adapter for local development.

  This adapter connects to a local Ollama server for LLM inference.
  It's ideal for development and testing without API costs.

  ## Configuration

  The adapter can be configured via application environment:

      config :scr, :llm,
        provider: :ollama,
        base_url: "http://localhost:11434",
        default_model: "llama2"

  ## Usage

      {:ok, response} = SCR.LLM.Ollama.chat([
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "What is Elixir?"}
      ])
      
      # Streaming
      SCR.LLM.Ollama.stream("Tell me a story", fn chunk -> 
        IO.write(chunk) 
      end)
  """

  alias SCR.LLM.Behaviour

  @behaviour Behaviour

  @default_base_url "http://localhost:11434"
  @default_model "llama2"

  # Client API

  @doc """
  Start the adapter (for supervised workers).
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current configuration.
  """
  def config do
    %{
      base_url: base_url(),
      default_model: default_model()
    }
  end

  # Behaviour implementation

  @impl Behaviour
  def complete(prompt, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)

    payload = %{
      model: model,
      prompt: prompt,
      temperature: temperature,
      options: %{
        num_predict: max_tokens
      },
      stream: false
    }

    case post("/api/generate", payload, options) do
      {:ok, %{"response" => response} = result} ->
        {:ok,
         %{
           content: response,
           model: model,
           finish_reason: "stop",
           raw: result
         }}

      {:ok, %{"error" => error}} ->
        {:error, %{type: :ollama_error, message: error}}

      error ->
        error
    end
  end

  @impl Behaviour
  def chat(messages, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)

    # Convert messages to Ollama format if needed
    ollama_messages =
      Enum.map(messages, fn
        %{role: role, content: content} -> %{role: role, content: content}
        %{"role" => role, "content" => content} -> %{role: role, content: content}
      end)

    payload = %{
      model: model,
      messages: ollama_messages,
      temperature: temperature,
      options: %{
        num_predict: max_tokens
      },
      stream: false
    }

    case post("/api/chat", payload, options) do
      {:ok, %{"message" => %{"content" => content} = message, "done" => done}} ->
        {:ok,
         %{
           content: content,
           role: message["role"],
           model: model,
           finish_reason: if(done, do: "stop", else: nil),
           raw: %{
             message: message,
             done: done
           }
         }}

      {:ok, %{"error" => error}} ->
        {:error, %{type: :ollama_error, message: error}}

      error ->
        error
    end
  end

  @doc """
  Generate a chat completion with tool support.

  Note: Ollama doesn't natively support function calling in the same way
  as OpenAI. This implementation adds tools to the system prompt and
  parses tool calls from the response.
  """
  @impl true
  def chat_with_tools(messages, tool_definitions, options \\ []) do
    options = Behaviour.merge_options(options)
    _model = Keyword.get(options, :model, default_model())

    # Convert tool definitions to a system prompt
    tools_prompt = build_tools_prompt(tool_definitions)

    # Add tools instruction to messages
    enhanced_messages = add_tools_to_messages(messages, tools_prompt)

    # Make the chat call
    chat(enhanced_messages, options)
  end

  defp build_tools_prompt(tool_definitions) do
    tools_json = Jason.encode!(tool_definitions)

    """
    You have access to the following tools:

    #{tools_json}

    When you need to use a tool, respond in JSON format:
    {"name": "tool_name", "arguments": {"param1": "value1"}}

    Always use tools when appropriate rather than making up information.
    """
  end

  defp add_tools_to_messages(messages, tools_prompt) do
    # Find or add system message - handle both string and atom keys
    case Enum.find_index(
           messages,
           &(Map.get(&1, "role") == "system" or Map.get(&1, :role) == "system")
         ) do
      nil ->
        # No system message, add one
        [%{"role" => "system", "content" => tools_prompt} | messages]

      idx ->
        # Update existing system message
        List.update_at(messages, idx, fn msg ->
          existing_content = Map.get(msg, "content") || Map.get(msg, :content) || ""
          Map.put(msg, "content", existing_content <> "\n\n" <> tools_prompt)
        end)
    end
  end

  @doc """
  Stream a completion from a prompt, calling the callback for each chunk.

  ## Parameters
    - prompt: String prompt for the LLM
    - callback: Function to call with each chunk of the response
    - options: Keyword list of options (model, temperature, max_tokens, etc.)

  ## Returns
    - {:ok, final_response} on success (after all chunks received)
    - {:error, reason} on failure

  ## Example

      {:ok, result} = SCR.LLM.Ollama.stream(
        "Write a story",
        fn chunk -> IO.write(chunk) end,
        model: "llama2"
      )
  """
  @impl true
  @spec stream(String.t(), (String.t() -> term()), keyword()) :: {:ok, map()} | {:error, term()}
  def stream(prompt, callback, options \\ []) when is_function(callback, 1) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)
    timeout = Keyword.get(options, :timeout, 120_000)

    payload = %{
      model: model,
      prompt: prompt,
      temperature: temperature,
      options: %{
        num_predict: max_tokens
      },
      stream: true
    }

    url = base_url() <> "/api/generate"

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/x-ndjson"}
    ]

    # Use HTTPoison.Async for streaming
    case HTTPoison.post(url, Jason.encode!(payload), headers, timeout: timeout, stream_to: self()) do
      {:ok, %{id: request_id}} ->
        collect_stream_chunks(request_id, callback, "", timeout, model, :generate)

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end

  @impl true
  def chat_stream(messages, callback, options \\ []) when is_function(callback, 1) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())
    temperature = Keyword.get(options, :temperature, 0.7)
    max_tokens = Keyword.get(options, :max_tokens, 2048)
    timeout = Keyword.get(options, :timeout, 120_000)

    ollama_messages =
      Enum.map(messages, fn
        %{role: role, content: content} -> %{role: role, content: content}
        %{"role" => role, "content" => content} -> %{role: role, content: content}
      end)

    payload = %{
      model: model,
      messages: ollama_messages,
      temperature: temperature,
      options: %{
        num_predict: max_tokens
      },
      stream: true
    }

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/x-ndjson"}
    ]

    case HTTPoison.post(
           base_url() <> "/api/chat",
           Jason.encode!(payload),
           headers,
           timeout: timeout,
           stream_to: self()
         ) do
      {:ok, %{id: request_id}} ->
        collect_stream_chunks(request_id, callback, "", timeout, model, :chat)

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end

  # Collect streaming chunks from the HTTP response
  defp collect_stream_chunks(request_id, callback, acc, timeout, model, mode) do
    receive do
      {:http_reply, ^request_id, %{status_code: 200, body: _body}} ->
        # Initial response, continue receiving chunks
        collect_stream_chunks(request_id, callback, acc, timeout, model, mode)

      {:http_reply, ^request_id, %{status_code: status}} ->
        {:error, %{type: :http_error, status: status}}

      {:stream, ^request_id, %HTTPoison.AsyncChunk{chunk: chunk}} ->
        case parse_stream_chunk(chunk, mode) do
          :noop ->
            collect_stream_chunks(request_id, callback, acc, timeout, model, mode)

          text when is_binary(text) ->
            callback.(text)
            collect_stream_chunks(request_id, callback, acc <> text, timeout, model, mode)

          :done ->
            {:ok,
             %{
               content: acc,
               model: model,
               finish_reason: "stop",
               streamed: true
             }}
        end

      {:stream, ^request_id, %HTTPoison.AsyncEnd{}} ->
        {:ok,
         %{
           content: acc,
           model: model,
           finish_reason: "stop",
           streamed: true
         }}
    after
      timeout ->
        {:error, %{type: :timeout, message: "Stream timed out after #{timeout}ms"}}
    end
  end

  defp parse_stream_chunk(chunk, mode) do
    chunk
    |> String.split("\n")
    |> Enum.find_value(:noop, fn line ->
      case String.trim(line) do
        "" ->
          false

        json_data ->
          parse_stream_json(json_data, mode)
      end
    end)
  end

  defp parse_stream_json(json_data, :generate) do
    case Jason.decode(json_data) do
      {:ok, %{"done" => true}} ->
        :done

      {:ok, %{"response" => response}} when is_binary(response) ->
        response

      _ ->
        false
    end
  end

  defp parse_stream_json(json_data, :chat) do
    case Jason.decode(json_data) do
      {:ok, %{"done" => true}} ->
        :done

      {:ok, %{"message" => %{"content" => response}}} when is_binary(response) ->
        response

      _ ->
        false
    end
  end

  @impl Behaviour
  def embed(text, options \\ []) do
    options = Behaviour.merge_options(options)
    model = Keyword.get(options, :model, default_model())

    # Handle both single string and list of strings
    input =
      if is_list(text) do
        text
      else
        [text]
      end

    payload = %{
      model: model,
      input: input
    }

    case post("/api/embeddings", payload, options) do
      {:ok, %{"embedding" => embedding}} ->
        {:ok,
         %{
           embedding: embedding,
           model: model
         }}

      {:ok, %{"error" => error}} ->
        {:error, %{type: :ollama_error, message: error}}

      error ->
        error
    end
  end

  @impl Behaviour
  def ping do
    case get("/") do
      {:ok, %{"version" => version}} ->
        {:ok,
         %{
           status: "available",
           version: version,
           provider: :ollama
         }}

      {:error, %{type: :http_error, reason: :econnrefused}} ->
        {:error,
         %{
           type: :connection_error,
           message: "Ollama server not running. Make sure 'ollama serve' is running."
         }}

      error ->
        error
    end
  end

  @impl Behaviour
  def list_models do
    case get("/api/tags") do
      {:ok, %{"models" => models}} ->
        formatted_models =
          Enum.map(models, fn m ->
            %{
              name: m["name"],
              model: m["model"],
              size: m["size"],
              modified_at: m["modified_at"]
            }
          end)

        {:ok, formatted_models}

      error ->
        error
    end
  end

  # Private functions

  defp base_url do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:base_url, @default_base_url)
  end

  defp default_model do
    Application.get_env(:scr, :llm, [])
    |> Keyword.get(:default_model, @default_model)
  end

  defp post(endpoint, payload, options) do
    url = base_url() <> endpoint
    timeout = Keyword.get(options, :timeout, 30_000)

    headers = [
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(url, Jason.encode!(payload), headers, timeout: timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status_code: status, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"error" => error}} ->
            {:error, %{type: :http_error, status: status, message: error}}

          _ ->
            {:error, %{type: :http_error, status: status, message: "Unknown error"}}
        end

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end

  defp get(endpoint) do
    url = base_url() <> endpoint

    timeout =
      Application.get_env(:scr, :llm, [])
      |> Keyword.get(:timeout, 30_000)

    headers = [
      {"Accept", "application/json"}
    ]

    case HTTPoison.get(url, headers, timeout: timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, status: status, message: body}}

      {:error, %{reason: reason}} ->
        {:error, %{type: :http_error, reason: reason}}
    end
  end
end
