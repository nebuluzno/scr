defmodule SCR.Tools.PolicyTest do
  use ExUnit.Case, async: false

  alias SCR.Tools.ExecutionContext
  alias SCR.Tools.Policy
  alias SCR.Tools.ToolDescriptor

  setup do
    original = Application.get_env(:scr, :tools)

    on_exit(fn ->
      Application.put_env(:scr, :tools, original)
    end)

    :ok
  end

  test "strict mode blocks risky native tool by default" do
    descriptor = %ToolDescriptor{
      name: "code_execution",
      source: :native,
      module: SCR.Tools.CodeExecution,
      description: "code",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :strict})

    assert {:error, :tool_not_allowed} = Policy.authorize(descriptor, %{"code" => "1+1"}, ctx)
  end

  test "strict mode allows MCP tool only when allowlisted" do
    Application.put_env(:scr, :tools,
      safety_mode: :strict,
      mcp: [enabled: true, servers: %{"github" => %{allowed_tools: ["search_issues"]}}]
    )

    descriptor = %ToolDescriptor{
      name: "search_issues",
      source: :mcp,
      server: "github",
      description: "search",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :strict})
    assert :ok = Policy.authorize(descriptor, %{"q" => "bug"}, ctx)
  end

  test "demo mode allows non allowlisted mcp tools" do
    Application.put_env(:scr, :tools,
      safety_mode: :strict,
      mcp: [enabled: true, servers: %{"github" => %{allowed_tools: []}}]
    )

    descriptor = %ToolDescriptor{
      name: "list_repos",
      source: :mcp,
      server: "github",
      description: "repos",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :demo})
    assert :ok = Policy.authorize(descriptor, %{}, ctx)
  end
end
