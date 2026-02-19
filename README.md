# Supervised Cognitive Runtime (SCR)

A **supervised multi-agent cognition runtime** built on **BEAM (Erlang VM)** using Elixir/OTP. This system demonstrates AI agents as fault-tolerant, persistent, and dynamically spawnable entities that collaborate to complete complex tasks.

## 🎯 Project Vision

SCR is a foundation for research-level work in scalable, long-lived AI agent systems. It provides:

- **Fault-tolerant agents** with automatic crash recovery via OTP supervision
- **Persistent memory** via ETS (Erlang Term Storage) 
- **Dynamic agent spawning** for parallel task execution
- **Supervision hierarchy** for monitoring and automatic restart capabilities
- **Structured message passing** between agents
- **LLM Integration** for intelligent task execution and evaluation

## 🏗️ Architecture

### Agent Types

| Agent | Icon | Description |
|-------|------|-------------|
| **PlannerAgent** | 🧠 | Decomposes complex tasks into subtasks and coordinates agent workflow |
| **WorkerAgent** | ⚙️ | Executes subtasks (research, analysis, synthesis) in parallel |
| **CriticAgent** | 🔍 | Evaluates worker outputs and provides quality feedback |
| **MemoryAgent** | 💾 | Persistent storage for tasks, results, and agent states using ETS |
| **ResearcherAgent** | 🔬 | Specialized for web research and information gathering |
| **WriterAgent** | ✍️ | Content generation, summarization, and formatting |
| **ValidatorAgent** | ✅ | Quality assurance, fact-checking, and verification |

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
└── Dynamic Agents (spawned as needed)
    ├── WorkerAgent(s)
    ├── ResearcherAgent(s)
    ├── WriterAgent(s)
    └── ValidatorAgent(s)
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

#### Command Comparison

| Command | Description | Use Case |
|---------|-------------|----------|
| `mix run -e "SCR.CLI.Demo.main([])"` | Runs CLI demo script - executes a task sequence and exits | Quick testing, CI/CD |
| `mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"` | Runs crash recovery test | Testing supervisor |
| `mix phx.server` | Starts Phoenix web server (continuous) | Web interface |

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
│   ├── llm/                    # LLM Integration Layer
│   │   ├── behaviour.ex       # Adapter contract (Behaviour)
│   │   ├── ollama.ex          # Ollama adapter (local models)
│   │   ├── client.ex          # Unified LLM client
│   │   ├── cache.ex           # Response caching
│   │   └── metrics.ex         # Usage metrics & cost tracking
│   ├── tools/                  # Tool Use System
│   │   ├── behaviour.ex       # Tool behaviour contract
│   │   ├── registry.ex        # Tool registry
│   │   ├── calculator.ex      # Calculator tool
│   │   ├── http_request.ex    # HTTP requests tool
│   │   ├── search.ex          # Web search tool
│   │   ├── file_operations.ex # File operations tool
│   │   ├── time.ex            # Time/date tool
│   │   ├── weather.ex         # Weather tool
│   │   └── code_execution.ex  # Code execution tool
│   ├── agents/
│   │   ├── memory_agent.ex    # Persistent storage (ETS) + summarization
│   │   ├── planner_agent.ex   # Task decomposition (LLM-powered)
│   │   ├── worker_agent.ex    # Subtask execution (LLM-powered)
│   │   ├── critic_agent.ex    # Result evaluation (LLM-powered)
│   │   ├── researcher_agent.ex # Web research & information gathering
│   │   ├── writer_agent.ex    # Content generation & summarization
│   │   └── validator_agent.ex # Quality assurance & verification
│   └── cli/
│       └── demo.ex             # CLI demo interface
├── scr_web/                    # Phoenix Web Interface
│   ├── endpoint.ex            # Phoenix endpoint
│   ├── router.ex              # Web router
│   ├── live/                  # LiveView components
│   │   └── dashboard_live.ex  # Real-time dashboard
│   └── controllers/           # HTTP controllers
│       ├── agent_controller.ex
│       ├── task_controller.ex
│       ├── metrics_controller.ex
│       └── page_controller.ex
├── config/                     # Configuration files
│   ├── config.exs             # Main config
│   ├── dev.exs               # Development settings
│   ├── test.exs              # Test settings
│   └── prod.exs              # Production settings
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

## 🤖 LLM Integration

SCR now supports LLM-powered agents! Connect to local or cloud LLM providers for intelligent task execution.

### Supported Providers

| Provider | Type | Description |
|----------|------|-------------|
| **Ollama** | Local | Run models locally (llama2, mistral, codellama, etc.) |
| **OpenAI** | Cloud | GPT-4, GPT-3.5 (coming soon) |
| **Anthropic** | Cloud | Claude (coming soon) |

### Quick Setup (Ollama)

1. **Install Ollama**: https://ollama.ai

2. **Start Ollama server**:
   ```bash
   ollama serve
   ```

3. **Pull a model** (in another terminal):
   ```bash
   ollama pull llama2
   ```

4. **Run the LLM-powered demo**:
   ```bash
   mix run -e "SCR.CLI.Demo.main([])"
   ```

### Configuration

Configure LLM settings in `config/dev.exs` or via environment variables:

```elixir
config :scr, :llm,
  provider: :ollama,
  base_url: System.get_env("LLM_BASE_URL") || "http://localhost:11434",
  default_model: System.get_env("LLM_MODEL") || "llama2",
  timeout: 120_000
```

Or using environment variables:
```bash
export LLM_BASE_URL=http://localhost:11434
export LLM_MODEL=llama2
```

### LLM-Powered Agents

| Agent | LLM Capability |
|-------|---------------|
| **WorkerAgent** | Executes tasks with real LLM responses |
| **PlannerAgent** | Intelligent task decomposition |
| **CriticAgent** | Quality evaluation with natural language feedback |
| **MemoryAgent** | Memory summarization & retrieval |

### Fallback Mode

If LLM is unavailable, agents automatically fall back to mock data. This allows development without running an LLM server.

## 🔧 Tool Use

Agents can use tools to interact with external systems. The tool system provides a standardized way for LLM-powered agents to execute actions.

### Available Tools

| Tool | Icon | Description |
|------|------|-------------|
| **Calculator** | 🧮 | Mathematical calculations |
| **HTTP Request** | 🌐 | Make HTTP requests to external APIs |
| **Search** | 🔍 | Web search capabilities |
| **File Operations** | 📁 | Read, write, and manage files |
| **Time** | ⏰ | Get current time and date information |
| **Weather** | 🌤️ | Get weather information |
| **Code Execution** | 💻 | Execute code snippets safely |

### Using Tools

Tools are automatically available to LLM-powered agents through function calling:

```elixir
# Tools are invoked by the LLM during task execution
# Example: WorkerAgent with tools
alias SCR.LLM.Client

tools = SCR.Tools.Registry.list_tools()
|> Enum.map(fn name ->
  {:ok, module} = SCR.Tools.Registry.get_tool(name)
  apply(module, :to_openai_format, [])
end)

# LLM decides when to call tools
Client.chat_with_tools(messages, tools, model: "llama2")
```

### Adding Custom Tools

Create a new tool by implementing the `SCR.Tools.Behaviour`:

```elixir
defmodule SCR.Tools.MyTool do
  @behaviour SCR.Tools.Behaviour
  
  def name, do: "my_tool"
  def description, do: "Description of what the tool does"
  
  def parameters do
    %{
      type: "object",
      properties: %{
        input: %{type: "string", description: "Input parameter"}
      },
      required: ["input"]
    }
  end
  
  def execute(%{"input" => input}) do
    # Tool implementation
    {:ok, "Result: #{input}"}
  end
  
  def to_openai_format do
    %{
      type: "function",
      function: %{
        name: name(),
        description: description(),
        parameters: parameters()
      }
    }
  end
end
```

## 🌐 Phoenix Web Interface

SCR includes a Phoenix-based web interface with real-time updates via LiveView.

### Starting the Web Server

```bash
mix phx.server
```

Then open http://localhost:4000 in your browser.

### Features

- **Real-time Dashboard** - Live agent status updates via PubSub
- **Agent Management** - View and manage running agents
- **Task Submission** - Submit new tasks through the web UI
- **Metrics View** - Monitor LLM usage and costs
- **Memory Browser** - Explore stored tasks and results
- **Tool Testing** - Test tools directly from the web interface

### LiveView Dashboard

The dashboard shows:
- Active agent count and status
- LLM call statistics
- Cache hit rates
- Recent tasks
- Quick access to tools

Create a new adapter implementing `SCR.LLM.Behaviour`:

```elixir
defmodule SCR.LLM.OpenAI do
  @behaviour SCR.LLM.Behaviour
  
  def complete(prompt, options) do
    # Implement OpenAI API call
  end
  
  def chat(messages, options) do
    # Implement chat completion
  end
  
  # ... implement other callbacks
end
```

## 🧪 Running Tests

```bash
mix test
```

## 📦 Dependencies

- **elixir_uuid** (~> 1.2) - UUID generation for messages and tasks
- **httpoison** (~> 2.0) - HTTP client for LLM API calls
- **jason** (~> 1.4) - JSON parsing for LLM responses

## 📄 License

MIT License

## 👤 Author

Lars Eriksson - nebuluzno@gmail.com

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📋 TODO - Future Enhancements

- [x] **LLM Integration** - Connect WorkerAgents to GPT-4, Claude, or local models (Ollama, llama.cpp)
- [x] **Phoenix Web Interface** - Web dashboard with LiveView for real-time monitoring
- [x] **Tool Use** - 7 tools implemented (Calculator, HTTP, Search, File, Time, Weather, Code)
- [x] **More Agent Types** - ResearcherAgent, WriterAgent, ValidatorAgent
- [ ] **Distributed Mode** - Run agents across multiple nodes for horizontal scaling
- [ ] **Persistent Storage** - Add DETS or PostgreSQL adapter for durability beyond memory
- [ ] **Agent Communication** - Add agent-to-agent direct messaging
- [ ] **Metrics & Telemetry** - Add OpenTelemetry integration for observability
- [ ] **Tests** - Add comprehensive test suite with ExUnit
