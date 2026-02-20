defmodule SCR.LLM.ClientTest do
  use ExUnit.Case, async: false

  alias SCR.LLM.Client

  setup do
    original = Application.get_env(:scr, :llm)

    on_exit(fn ->
      Application.put_env(:scr, :llm, original)
    end)

    :ok
  end

  test "provider can be switched to openai through config" do
    Application.put_env(:scr, :llm, provider: :openai)
    assert Client.provider() == :openai
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
end
