defmodule SCR.LLM.Mock do
  @moduledoc """
  Mock LLM adapter for deterministic tests.
  """

  @behaviour SCR.LLM.Behaviour

  @impl true
  def complete(_prompt, _options \\ []) do
    {:ok, %{content: "mock completion", model: "mock", raw: %{}}}
  end

  @impl true
  def chat(_messages, _options \\ []) do
    {:ok, %{content: "mock chat", message: %{content: "mock chat"}, raw: %{}}}
  end

  @impl true
  def embed(text, _options \\ []) do
    count = if is_list(text), do: length(text), else: 1
    {:ok, %{embedding: List.duplicate(0.0, count), model: "mock"}}
  end

  @impl true
  def ping do
    {:ok, %{status: "available", provider: :mock, version: "1"}}
  end

  @impl true
  def list_models do
    {:ok, [%{name: "mock"}]}
  end

  @impl true
  def stream(_prompt, callback, _options \\ []) do
    callback.("mock stream")
    {:ok, %{content: "mock stream", streamed: true}}
  end

  @impl true
  def chat_stream(_messages, callback, _options \\ []) do
    callback.("mock chat stream")
    {:ok, %{content: "mock chat stream", streamed: true}}
  end

  @impl true
  def chat_with_tools(_messages, _tool_definitions, _options \\ []) do
    {:ok, %{content: "mock tool response", message: %{content: "mock tool response"}}}
  end
end
