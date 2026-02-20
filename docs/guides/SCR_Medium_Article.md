
# Building Fault-Tolerant AI Agents with Elixir/OTP: The Supervised Cognitive Runtime
Doc Owner: SCR Maintainers

> Runtime commands:
> - CLI: `mix run -e "SCR.CLI.Demo.main([])"`
> - Crash test: `mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"`
> - Web UI: `mix phx.server` and open `http://localhost:4000`

## Introduction

As AI agents become more complex and handle critical tasks, **fault tolerance** isn't optional — it's essential. When an AI agent crashes mid-task in production, the consequences can range from annoying to catastrophic.

What if we could apply the same reliability patterns that power telecommunications infrastructure to AI agents? That's exactly what the **Supervised Cognitive Runtime (SCR)** does.

## The Problem with Current AI Agent Architectures

Most AI agent frameworks today suffer from fundamental weaknesses:

1. **Single points of failure** — One crashed agent stops the entire workflow
2. **No automatic recovery** — Manual intervention required to restart failed agents
3. **State loss** — When an agent dies, its memory and context are lost
4. **No parallelism** — Sequential processing limits throughput

## Enter the BEAM: proven reliability for AI

The BEAM (Bogdan/Björn's Erlang Abstract Machine) has powered telecommunications for 40+ years with **five 9s of reliability**. Its secret? The **OTP framework** with supervision trees.

The core insight is simple: **let processes monitor each other**. When one fails, its supervisor can automatically restart it — possibly on a different machine.

## Introducing the Supervised Cognitive Runtime

SCR is a multi-agent AI system built on Elixir/OTP that demonstrates:

- ✅ **Fault-tolerant agents** with automatic crash recovery
- ✅ **Persistent memory** via ETS (Erlang Term Storage)
- ✅ **Dynamic agent spawning** for parallel task execution  
- ✅ **Supervision hierarchy** for monitoring and restart capabilities

### The Four Agent Types

```
┌─────────────────────────────────────────────────────────────┐
│                    SCR Architecture                          │
├─────────────────────────────────────────────────────────────┤
│  PlannerAgent ───▶ WorkerAgents (parallel) ──▶ CriticAgent │
│        │                                                    │
│        ▼                                                    │
│   MemoryAgent (ETS)                                        │
└─────────────────────────────────────────────────────────────┘
```

1. **PlannerAgent** — Decomposes complex tasks into subtasks
2. **WorkerAgent** — Executes subtasks in parallel (research, analysis, synthesis)
3. **CriticAgent** — Evaluates quality and requests revisions if needed
4. **MemoryAgent** — Persists all state and results in ETS

## Code Deep Dive

### The Base Agent Behavior

Every agent in SCR is a GenServer with built-in supervision:

```elixir
defmodule SCR.Agent do
  use GenServer
  
  # Agents receive messages and manage their own state
  def handle_cast({:deliver_message, message}, state) do
    case state.module.handle_message(message, agent_context) do
      {:noreply, new_agent_state} ->
        {:noreply, %{state | agent_state: new_agent_state}}
      {:stop, reason, new_agent_state} ->
        {:stop, reason, %{state | agent_state: new_agent_state, status: :crashed}}
    end
  end
end
```

### Message Protocol

Agents communicate via structured messages — no loose strings:

```elixir
defmodule SCR.Message do
  defstruct [:type, :from, :to, :payload, :timestamp, :message_id]
  
  # Task assignment
  def task(from, to, task_data) do
    new(:task, from, to, %{task: task_data})
  end
  
  # Result return
  def result(from, to, result_data) do
    new(:result, from, to, %{result: result_data})
  end
  
  # Quality critique
  def critique(from, to, critique_data) do
    new(:critique, from, to, %{critique: critique_data})
  end
end
```

### Dynamic Supervision

The supervisor manages agent lifecycle:

```elixir
defmodule SCR.Supervisor do
  use DynamicSupervisor
  
  def start_agent(agent_id, agent_type, module, init_arg) do
    spec = {SCR.Agent, {agent_id, agent_type, module, init_arg}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
```

## Running the Demo

```bash
# Install dependencies
mix deps.get

# Run the multi-agent demo
mix run -e "SCR.CLI.Demo.main([])"
```

### Output demonstrates:

1. **PlannerAgent** receives: "Research AI agent runtimes"
2. Decomposes into 3 subtasks (research, analysis, synthesis)
3. **WorkerAgents** spawn in parallel, each processing a subtask
4. Results flow back to **PlannerAgent**
5. **CriticAgent** evaluates quality
6. **MemoryAgent** stores everything in ETS

## Crash Recovery in Action

```bash
# Demonstrate crash recovery
mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"
```

This:
1. Starts a worker agent
2. Sends it a task
3. **Simulates a crash** 
4. The worker terminates
5. **Automatically restarts**
6. Continues processing

The system keeps running despite failures!

## Why This Matters for AI

Traditional AI frameworks treat agents as fragile snowflakes. SCR treats them as **resilient processes** that:

- **Recover automatically** from failures
- **Persist state** across restarts  
- **Scale horizontally** via dynamic spawning
- **Stay available** under partial failures

## Next Steps for SCR

The foundation is laid. Potential extensions include:

1. **LLM Integration** — Connect workers to GPT-4, Claude, or local models
2. **Distributed Mode** — Run agents across multiple nodes
3. **Persistence Layer** — Add DETS or PostgreSQL for durability
4. **More Agent Types** — Add specialized agents (retriever, coder, etc.)
5. **Web Interface** — Phoenix-based dashboard for monitoring
6. **Tool Use** — Give agents ability to call external APIs

## Conclusion

The BEAM's proven reliability patterns are perfectly suited for production AI agents. SCR demonstrates that **fault tolerance isn't opposed to intelligence** — it's the foundation it builds upon.

The future of AI agents isn't just about making them smarter. It's about making them **unbreakable**.

---

*Want to explore the code? Check out the GitHub repository. Contributions welcome!*

---

**Author:** Lars Eriksson - nebuluzno@gmail.com
