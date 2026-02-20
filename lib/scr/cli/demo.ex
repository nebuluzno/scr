defmodule SCR.CLI.Demo do
  @moduledoc """
  CLI Demo for the Supervised Cognitive Runtime.

  Demonstrates:
  - Multi-agent coordination
  - Task decomposition
  - Crash recovery
  - Persistent memory
  """

  alias SCR.{Message, Supervisor}
  alias SCR.Agents.{MemoryAgent, PlannerAgent, WorkerAgent, CriticAgent}

  def main(args \\ []) do
    IO.puts("""
    ╔═══════════════════════════════════════════════════════════════╗
    ║   Supervised Cognitive Runtime (SCR) - Demo                   ║
    ║   Multi-agent cognition runtime on BEAM                      ║
    ╚═══════════════════════════════════════════════════════════════╝
    """)

    # Start the application
    {:ok, _} = Application.ensure_all_started(:scr)

    # Parse command line arguments
    mode = parse_args(args)

    case mode do
      :demo -> run_demo()
      :crash_test -> run_crash_test()
      :help -> IO.puts(help_text())
    end

    # Give time for async operations to complete
    Process.sleep(3000)

    IO.puts("\n✅ Demo completed!")
  end

  defp parse_args(args) do
    case args do
      ["--crash-test"] -> :crash_test
      ["--help"] -> :help
      _ -> :demo
    end
  end

  defp run_demo do
    IO.puts("\n📋 Running SCR Demo...")
    IO.puts("Task: Research AI agent runtimes and produce structured output\n")

    # Reset metrics for fresh demo
    SCR.LLM.Metrics.reset()
    SCR.LLM.Cache.clear()

    IO.puts("LLM Cache & Metrics initialized")

    # Start MemoryAgent first (other agents will store data here)
    IO.puts("1️⃣ Starting MemoryAgent...")
    {:ok, _} = Supervisor.start_agent("memory_1", :memory, MemoryAgent, %{})
    Process.sleep(500)

    # Start CriticAgent
    IO.puts("2️⃣ Starting CriticAgent...")
    {:ok, _} = Supervisor.start_agent("critic_1", :critic, CriticAgent, %{})
    Process.sleep(500)

    # Start PlannerAgent
    IO.puts("3️⃣ Starting PlannerAgent...")
    {:ok, _} = Supervisor.start_agent("planner_1", :planner, PlannerAgent, %{})
    Process.sleep(500)

    # Send the main task to PlannerAgent
    IO.puts("\n4️⃣ Sending main task to PlannerAgent...\n")

    task_msg =
      Message.task("cli", "planner_1", %{
        task_id: UUID.uuid4(),
        description: "Research AI agent runtimes and produce structured output"
      })

    Supervisor.send_to_agent("planner_1", task_msg)

    # Wait for task to complete - increased time for LLM calls
    IO.puts("\n⏳ Processing task (this may take a while for LLM calls)...\n")
    Process.sleep(15000)

    # Show LLM stats
    show_llm_stats()

    # Show final status
    show_system_status()
  end

  defp run_crash_test do
    IO.puts("\n💥 Running Crash Recovery Test...\n")

    # Start MemoryAgent
    IO.puts("1️⃣ Starting MemoryAgent...")
    {:ok, _} = Supervisor.start_agent("memory_1", :memory, MemoryAgent, %{})
    Process.sleep(300)

    # Start a WorkerAgent
    IO.puts("2️⃣ Starting WorkerAgent...")
    {:ok, _} = Supervisor.start_agent("worker_test", :worker, WorkerAgent, %{})
    Process.sleep(300)

    # Send a task to the worker
    IO.puts("3️⃣ Sending task to WorkerAgent...")

    task_msg =
      Message.task("cli", "worker_test", %{
        task_id: "test_1",
        type: :research,
        description: "Test task for crash recovery"
      })

    Supervisor.send_to_agent("worker_test", task_msg)
    Process.sleep(1500)

    # Crash the worker
    IO.puts("\n4️⃣ 💥 Simulating worker crash...")
    Supervisor.crash_agent("worker_test")
    Process.sleep(1000)

    # Show status
    IO.puts("\n5️⃣ Checking agent status after crash...")
    show_system_status()

    # Restart the worker (simulating supervisor recovery)
    IO.puts("\n6️⃣ 🔄 Supervisor restarting crashed worker...")

    case Supervisor.restart_agent("worker_test", :worker, WorkerAgent, %{}) do
      {:ok, _} ->
        :ok

      {:error, :already_started} ->
        IO.puts("⚠️ Worker already running after crash")
        :ok

      error ->
        IO.puts("Failed to restart: #{inspect(error)}")
        :ok
    end

    Process.sleep(500)

    # Send a new task to verify recovery
    IO.puts("\n7️⃣ Sending new task to restarted worker...")

    task_msg =
      Message.task("cli", "worker_test", %{
        task_id: "test_2",
        type: :research,
        description: "Test task after crash recovery"
      })

    Supervisor.send_to_agent("worker_test", task_msg)
    Process.sleep(1500)

    IO.puts("\n✅ Crash recovery test completed!")
  end

  defp show_system_status do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("📊 System Status")
    IO.puts(String.duplicate("=", 60))

    agents = Supervisor.list_agents()
    IO.puts("\nActive agents: #{length(agents)}")

    Enum.each(agents, fn agent_id ->
      case Supervisor.get_agent_status(agent_id) do
        {:ok, status} ->
          IO.puts("  • #{agent_id} (#{status.agent_type}) - #{status.status}")

        _ ->
          IO.puts("  • #{agent_id} - status unavailable")
      end
    end)

    IO.puts("\nMemory storage:")
    IO.puts("  Tasks: #{length(SCR.Agents.MemoryAgent.list_tasks())}")
    IO.puts("  Agent states: #{length(SCR.Agents.MemoryAgent.list_agents())}")
  end

  defp show_llm_stats do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("🤖 LLM Statistics")
    IO.puts(String.duplicate("=", 60))

    # Cache stats
    cache_stats = SCR.LLM.Cache.stats()
    IO.puts("\n💾 Cache:")
    IO.puts("  Enabled: #{cache_stats.enabled}")
    IO.puts("  Hits: #{cache_stats.hits}")
    IO.puts("  Misses: #{cache_stats.misses}")
    IO.puts("  Cached responses: #{cache_stats.size}")

    # Metrics stats
    metrics_stats = SCR.LLM.Metrics.stats()
    IO.puts("\n📈 Token Usage:")
    IO.puts("  Total calls: #{metrics_stats.total_calls}")
    IO.puts("  Prompt tokens: #{metrics_stats.total_prompt_tokens}")
    IO.puts("  Completion tokens: #{metrics_stats.total_completion_tokens}")
    IO.puts("  Total tokens: #{metrics_stats.total_tokens}")

    IO.puts(
      "  Total cost: $#{:erlang.float_to_binary(metrics_stats.total_cost, [{:decimals, 6}])} USD"
    )

    # Model breakdown
    if map_size(metrics_stats.by_model) > 0 do
      IO.puts("\n📊 By Model:")

      Enum.each(metrics_stats.by_model, fn {model, stats} ->
        IO.puts("  #{model}:")
        IO.puts("    Calls: #{stats.calls}")
        IO.puts("    Tokens: #{stats.prompt_tokens + stats.completion_tokens}")
        IO.puts("    Cost: $#{:erlang.float_to_binary(stats.cost, [{:decimals, 6}])} USD")
      end)
    end
  end

  defp help_text do
    """
    Usage: mix run lib/scr/cli/demo.exs [options]

    Options:
      --crash-test    Run crash recovery demonstration
      --help          Show this help message

    Examples:
      mix run lib/scr/cli/demo.exs
      mix run lib/scr/cli/demo.exs --crash-test
    """
  end
end
