# Supervised Cognitive Runtime (SCR)

A **supervised multi-agent cognition runtime** built on **BEAM (Erlang VM)** using Elixir/OTP. This system demonstrates AI agents as fault-tolerant, persistent, and dynamically spawnable entities that collaborate to complete complex tasks.

## 🎯 Project Vision

SCR is a foundation for research-level work in scalable, long-lived AI agent systems. It provides:

- **Fault-tolerant agents** with automatic crash recovery via OTP supervision
- **Persistent memory** via ETS (Erlang Term Storage) 
- **Dynamic agent spawning** for parallel task execution
- **Supervision hierarchy** for monitoring and automatic restart capabilities
- **Structured message passing** between agents

## 🏗️ Architecture

### Agent Types

| Agent | Description |
|-------|-------------|
| **PlannerAgent** | Decomposes complex tasks into subtasks and coordinates agent workflow |
| **WorkerAgent** | Executes subtasks (research, analysis, synthesis) in parallel |
| **CriticAgent** | Evaluates worker outputs and provides quality feedback |
| **MemoryAgent** | Persistent storage for tasks, results, and agent states using ETS |

### Message Protocol

Agents communicate via structured messages:

```elixir
:task     - Work assignment from planner to workers
:result  - Task completion result from workers to planner
:critique - Quality evaluation feedback from critic to planner
:status  - Health/status updates between agents
:ping/pong - Heartbeat for agent liveness
:stop    - Graceful shutdown signal
```

### Supervision Tree

```
SCR.Supervisor (DynamicSupervisor)
├── Registry (SCR.AgentRegistry)
├── MemoryAgent (permanent)
├── CriticAgent (permanent)  
├── PlannerAgent (permanent)
└── WorkerAgent (dynamic, spawned as needed)
    ├── WorkerAgent
    ├── WorkerAgent
    └── WorkerAgent
```

## 🚀 Quick Start

### Prerequisites

- Elixir 1.14+ 
- Erlang/OTP 24+

### Installation

```bash
# Clone the repository
cd scr

# Install dependencies
mix deps.get

# Compile the project
mix compile
```

### Running the Demo

#### Basic Demo - Multi-Agent Task Execution

```bash
mix run -e "SCR.CLI.Demo.main([])"
```

This runs the example scenario:
1. User inputs: "Research AI agent runtimes and produce structured output"
2. PlannerAgent decomposes the task into subtasks
3. WorkerAgents gather information in parallel
4. CriticAgent evaluates output quality
5. MemoryAgent stores all intermediate results
6. Final structured output is produced

#### Crash Recovery Test

```bash
mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"
```

This demonstrates:
1. Agent spawning and task execution
2. Simulated worker crash
3. Automatic recovery and restart
4. Continued task execution after recovery

## 📁 Project Structure

```
lib/
├── scr.ex                      # Application entry point
├── scr/
│   ├── message.ex              # Structured message protocol
│   ├── agent.ex                # Base Agent behavior (GenServer)
│   ├── supervisor.ex           # DynamicSupervisor for agent lifecycle
│   ├── agents/
│   │   ├── memory_agent.ex    # Persistent storage (ETS)
│   │   ├── planner_agent.ex   # Task decomposition
│   │   ├── worker_agent.ex    # Subtask execution
│   │   └── critic_agent.ex    # Result evaluation
│   └── cli/
│       └── demo.ex             # CLI demo interface
├── mix.exs                     # Project configuration
└── README.md                   # This file
```

## 🔧 Key Features

### Fault Tolerance

- Agents are supervised by `SCR.Supervisor`
- Crashed agents can be automatically restarted
- Memory persists across agent restarts via ETS
- Task state preserved in MemoryAgent

### Message Passing

- All communication via structured `SCR.Message` tuples
- Async message passing via `GenServer.cast`
- Request-response via `GenServer.call`

### Persistence

- ETS tables for in-memory storage
- Task history and results stored
- Agent states tracked
- Disk persistence available as extension

## 🔨 Extending SCR

### Adding New Agent Types

1. Create module in `lib/scr/agents/`
2. Implement `init/1`, `handle_message/2`, `handle_heartbeat/1`, `terminate/2`
3. Start via `SCR.Supervisor.start_agent/4`

Example:
```elixir
defmodule SCR.Agents.CustomAgent do
  def start_link(agent_id, init_arg \\ %{}) do
    SCR.Agent.start_link(agent_id, :custom, __MODULE__, init_arg)
  end

  def init(init_arg) do
    {:ok, %{custom_state: %{}}}
  end

  def handle_message(message, state) do
    # Process message
    {:noreply, state}
  end

  def handle_heartbeat(state), do: {:noreply, state}
  def terminate(_reason, _state), do: :ok
end
```

### Custom Task Types

Extend WorkerAgent's `process_task/3` function to handle new task types:

```elixir
defp process_task(:custom_type, description, task_id) do
  # Custom processing logic
  %{task_id: task_id, output: "custom result"}
end
```

### Persistence Backend

Replace ETS with:
- `DETS` for disk-backed storage
- `Mnesia` for distributed storage
- External database (PostgreSQL, etc.)

## 📊 Example Output

```
╔═══════════════════════════════════════════════════════════════╗
║   Supervised Cognitive Runtime (SCR) - Demo                   ║
║   Multi-agent cognition runtime on BEAM                      ║
╚═══════════════════════════════════════════════════════════════╝

📋 Running SCR Demo...
Task: Research AI agent runtimes and produce structured output

1️⃣ Starting MemoryAgent...
✓ Started memory agent: memory_1
2️⃣ Starting CriticAgent...
✓ Started critic agent: critic_1
3️⃣ Starting PlannerAgent...
✓ Started planner agent: planner_1

4️⃣ Sending main task to PlannerAgent...

🧠 PlannerAgent received main task: "Research AI agent runtimes..."
👷 WorkerAgent initialized
✓ Started worker agent: worker_42
🧠 Assigned research task to worker_42
🔍 Performing research on: Research AI agent runtimes...
🧠 All subtasks completed, sending to CriticAgent
📝 CriticAgent reviewing result
🧠 Task approved! Finalizing...

============================================================
📊 System Status
============================================================

Active agents: 4

✅ Demo completed!
```

## 🧪 Running Tests

```bash
mix test
```

## 📦 Dependencies

- **elixir_uuid** (~> 1.2) - UUID generation for messages and tasks

## 📄 License

MIT License

## 👤 Author

Lars Eriksson - nebuluzno@gmail.com

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📋 TODO - Future Enhancements

- [ ] **LLM Integration** - Connect WorkerAgents to GPT-4, Claude, or local models (Ollama, llama.cpp)
- [ ] **Phoenix Web Interface** - Add a web dashboard for monitoring agent activity and system health
- [ ] **Distributed Mode** - Run agents across multiple nodes for horizontal scaling
- [ ] **Persistent Storage** - Add DETS or PostgreSQL adapter for durability beyond memory
- [ ] **More Agent Types** - Add specialized agents:
  - RetrieverAgent (RAG/vector search)
  - CoderAgent (code generation)
  - BrowserAgent (web automation)
- [ ] **Tool Use** - Give agents ability to call external APIs and tools
- [ ] **Agent Communication** - Add agent-to-agent direct messaging
- [ ] **Metrics & Telemetry** - Add OpenTelemetry integration for observability
- [ ] **Tests** - Add comprehensive test suite with ExUnit
