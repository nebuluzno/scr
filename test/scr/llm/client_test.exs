defmodule SCR.LLM.ClientTest do
  use ExUnit.Case, async: false

  alias SCR.LLM.Client

  defmodule FailingAdapter do
    @behaviour SCR.LLM.Behaviour
    def complete(_prompt, _options), do: {:error, %{type: :connection_error, message: "down"}}
    def chat(_messages, _options), do: {:error, %{type: :connection_error, message: "down"}}
    def embed(_text, _options), do: {:error, %{type: :connection_error, message: "down"}}
    def ping, do: {:error, %{type: :connection_error, message: "down"}}
    def list_models, do: {:error, %{type: :connection_error, message: "down"}}

    def stream(_prompt, _callback, _options),
      do: {:error, %{type: :connection_error, message: "down"}}

    def chat_stream(_messages, _callback, _options),
      do: {:error, %{type: :connection_error, message: "down"}}

    def chat_with_tools(_messages, _tool_definitions, _options),
      do: {:error, %{type: :connection_error, message: "down"}}
  end

  defmodule SuccessAdapter do
    @behaviour SCR.LLM.Behaviour
    def complete(_prompt, _options), do: {:ok, %{content: "ok_complete"}}

    def chat(_messages, _options),
      do: {:ok, %{content: "ok_chat", message: %{content: "ok_chat"}}}

    def embed(_text, _options), do: {:ok, %{embedding: [0.0]}}
    def ping, do: {:ok, %{status: "available"}}
    def list_models, do: {:ok, [%{name: "success"}]}

    def stream(_prompt, callback, _options) do
      callback.("ok_stream")
      {:ok, %{content: "ok_stream"}}
    end

    def chat_stream(_messages, callback, _options) do
      callback.("ok_chat_stream")
      {:ok, %{content: "ok_chat_stream"}}
    end

    def chat_with_tools(_messages, _tool_definitions, _options),
      do: {:ok, %{content: "ok_tools", message: %{content: "ok_tools"}}}
  end

  setup do
    original = Application.get_env(:scr, :llm)

    on_exit(fn ->
      Application.put_env(:scr, :llm, original)
      Client.clear_failover_state()
    end)

    Client.clear_cache()
    Client.clear_failover_state()
    :ok
  end

  test "provider can be switched to openai through config" do
    Application.put_env(:scr, :llm, provider: :openai)
    assert Client.provider() == :openai
  end

  test "provider can be switched to anthropic through config" do
    Application.put_env(:scr, :llm, provider: :anthropic)
    assert Client.provider() == :anthropic
  end

  test "chat_stream delegates to adapter when provider supports streaming" do
    Application.put_env(:scr, :llm, provider: :mock)

    callback = fn chunk -> send(self(), {:chunk, chunk}) end

    assert {:ok, %{streamed: true, content: content}} =
             Client.chat_stream([%{role: "user", content: "hello"}], callback)

    assert content in ["mock chat stream", "mock chat"]
    assert_received {:chunk, chunk}
    assert chunk in ["mock chat stream", "mock chat"]
  end

  test "extract_tool_calls handles normalized tool call shape" do
    response = %{
      message: %{
        tool_calls: [
          %{
            id: "call_1",
            type: "function",
            function: %{name: "calculator", arguments: ~s({"operation":"add","a":1,"b":2})}
          }
        ]
      }
    }

    [call] = Client.extract_tool_calls(response)
    assert call.id == "call_1"
    assert call.function.name == "calculator"
  end

  test "failover retries next provider on eligible error" do
    Application.put_env(:scr, :llm,
      provider: :openai,
      failover_enabled: true,
      failover_providers: [:openai, :anthropic],
      failover_errors: [:connection_error],
      failover_cooldown_ms: 5_000,
      adapter_overrides: %{
        openai: FailingAdapter,
        anthropic: SuccessAdapter
      }
    )

    assert {:ok, response} = Client.chat([%{role: "user", content: "hello"}])
    assert response.content == "ok_chat"
    assert response.provider == :anthropic
  end

  test "failover disabled returns first provider error" do
    Application.put_env(:scr, :llm,
      provider: :openai,
      failover_enabled: false,
      failover_providers: [:openai, :anthropic],
      adapter_overrides: %{
        openai: FailingAdapter,
        anthropic: SuccessAdapter
      }
    )

    assert {:error, %{type: :connection_error}} = Client.chat([%{role: "user", content: "hello"}])
  end

  test "fail-open returns fallback response when provider chain is unavailable" do
    Application.put_env(:scr, :llm,
      provider: :openai,
      failover_enabled: true,
      failover_mode: :fail_open,
      failover_providers: [:openai],
      failover_fail_open_provider: :missing_provider,
      adapter_overrides: %{openai: FailingAdapter}
    )

    assert {:ok, response} = Client.chat([%{role: "user", content: "hello"}])
    assert response.degraded == true
    assert response.fail_open == true
    assert response.provider in [:fail_open, :missing_provider]
  end

  test "fail-closed returns retry budget exhausted error when budget is consumed" do
    Application.put_env(:scr, :llm,
      provider: :openai,
      failover_enabled: true,
      failover_mode: :fail_closed,
      failover_providers: [:openai, :anthropic],
      failover_errors: [:connection_error],
      failover_cooldown_ms: 0,
      failover_retry_budget: [max_retries: 1, window_ms: 60_000],
      adapter_overrides: %{
        openai: FailingAdapter,
        anthropic: SuccessAdapter
      }
    )

    assert {:ok, _} = Client.chat([%{role: "user", content: "hello"}])
    Client.clear_cache()

    assert {:error, %{type: :failover_retry_budget_exhausted}} =
             Client.chat([%{role: "user", content: "hello"}])
  end

  test "failover_state exposes circuit and budget info" do
    Application.put_env(:scr, :llm,
      provider: :openai,
      failover_enabled: true,
      failover_mode: :fail_closed,
      failover_providers: [:openai, :anthropic],
      failover_errors: [:connection_error],
      failover_cooldown_ms: 30_000,
      failover_retry_budget: [max_retries: 5, window_ms: 60_000],
      adapter_overrides: %{
        openai: FailingAdapter,
        anthropic: SuccessAdapter
      }
    )

    assert {:ok, _} = Client.chat([%{role: "user", content: "hello"}])
    state = Client.failover_state()
    openai = Enum.find(state.providers, &(&1.provider == :openai))

    assert state.mode == :fail_closed
    assert is_map(openai)
    assert openai.failures >= 1
    assert openai.circuit_open == true
    assert state.retry_budget.remaining < state.retry_budget.max_retries
  end
end
