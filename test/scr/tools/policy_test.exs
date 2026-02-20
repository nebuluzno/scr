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

  test "strict mode blocks file writes by default" do
    descriptor = %ToolDescriptor{
      name: "file_operations",
      source: :native,
      module: SCR.Tools.FileOperations,
      description: "file operations",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :strict})

    assert {:error, :write_not_allowed} =
             Policy.authorize(
               descriptor,
               %{"operation" => "write", "path" => "tmp/out.txt", "content" => "hello"},
               ctx
             )
  end

  test "strict mode allows file writes when sandbox config allows and path is allowlisted" do
    Application.put_env(:scr, :tools,
      sandbox: [
        file_operations: [
          strict_allow_writes: true,
          demo_allow_writes: true,
          allowed_write_prefixes: ["tmp/"],
          max_write_bytes: 10_000
        ]
      ]
    )

    descriptor = %ToolDescriptor{
      name: "file_operations",
      source: :native,
      module: SCR.Tools.FileOperations,
      description: "file operations",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :strict})

    assert :ok =
             Policy.authorize(
               descriptor,
               %{"operation" => "write", "path" => "tmp/out.txt", "content" => "hello"},
               ctx
             )
  end

  test "code execution rejects blocked sandbox patterns" do
    Application.put_env(:scr, :tools,
      strict_native_allowlist: ["code_execution"],
      sandbox: [code_execution: [max_code_bytes: 4_000, blocked_patterns: ["HTTPoison."]]]
    )

    descriptor = %ToolDescriptor{
      name: "code_execution",
      source: :native,
      module: SCR.Tools.CodeExecution,
      description: "code",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :strict})

    assert {:error, :blocked_code_pattern} =
             Policy.authorize(
               descriptor,
               %{"code" => "HTTPoison.get!(\"https://example.com\")"},
               ctx
             )
  end

  test "runtime profile switch updates current profile" do
    Application.put_env(:scr, :tools,
      policy_profile: :strict,
      profiles: %{strict: [], balanced: []}
    )

    assert Policy.current_profile() == :strict
    assert :ok = Policy.set_profile(:balanced)
    assert Policy.current_profile() == :balanced
  end

  test "profile override can disable a non-risky tool" do
    Application.put_env(:scr, :tools,
      policy_profile: :strict,
      profiles: %{strict: [tool_overrides: %{"calculator" => [enabled: false]}]}
    )

    descriptor = %ToolDescriptor{
      name: "calculator",
      source: :native,
      module: SCR.Tools.Calculator,
      description: "calc",
      schema: %{"type" => "object", "properties" => %{}}
    }

    ctx = ExecutionContext.new(%{mode: :strict})
    assert {:error, :tool_disabled_by_profile} = Policy.authorize(descriptor, %{"a" => 1}, ctx)
  end

  test "context policy_profile overrides global profile" do
    Application.put_env(:scr, :tools,
      policy_profile: :strict,
      profiles: %{
        strict: [tool_overrides: %{"calculator" => [enabled: false]}],
        balanced: [tool_overrides: %{"calculator" => [enabled: true]}]
      }
    )

    descriptor = %ToolDescriptor{
      name: "calculator",
      source: :native,
      module: SCR.Tools.Calculator,
      description: "calc",
      schema: %{"type" => "object", "properties" => %{}}
    }

    strict_ctx = ExecutionContext.new(%{mode: :strict})
    balanced_ctx = ExecutionContext.new(%{mode: :strict, policy_profile: :balanced})

    assert {:error, :tool_disabled_by_profile} =
             Policy.authorize(descriptor, %{"a" => 1}, strict_ctx)

    assert :ok = Policy.authorize(descriptor, %{"a" => 1}, balanced_ctx)
  end
end
