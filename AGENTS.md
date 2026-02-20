# AGENTS.md

> This file provides context for AI agents working with this codebase.

## Project Overview

**SCR (Supervised Cognitive Runtime)** is a fault-tolerant, multi-agent AI system built on the BEAM/OTP platform using Elixir. It provides a foundation for research-level work in scalable, long-lived AI agent systems with LLM integration.

### Core Philosophy

- **OTP Principles**: Agents are GenServers under a DynamicSupervisor
- **Fault Tolerance**: Automatic crash detection and recovery
- **Message Passing**: Structured communication between agents
- **LLM Integration**: Optional LLM-powered intelligence with fallback to mock responses
- **Tool Use**: Extensible tool system for agent capabilities

## Architecture

### Supervision Tree

```
SCR.Supervisor.Tree (Supervisor)
├── SCR.PubSub (Phoenix.PubSub)
├── SCR.LLM.Cache (GenServer)
├── SCR.LLM.Metrics (GenServer)
├── SCR.Tools.Registry (GenServer)
├── SCRWeb.Endpoint (Phoenix.Endpoint)
└── SCR.Supervisor (DynamicSupervisor)
    ├── MemoryAgent (permanent)
    ├── CriticAgent (permanent)
    ├── PlannerAgent (permanent)
    └── Dynamic Agents (spawned as needed)
        ├── WorkerAgent(s)
        ├── ResearcherAgent(s)
        ├── WriterAgent(s)
        └── ValidatorAgent(s)
```

### Agent Types

| Agent | Module | Description |
|-------|--------|-------------|
| PlannerAgent | `SCR.Agents.PlannerAgent` | Decomposes tasks, coordinates workflow, spawns workers |
| WorkerAgent | `SCR.Agents.WorkerAgent` | Executes subtasks with LLM + tools support |
| CriticAgent | `SCR.Agents.CriticAgent` | Evaluates results, provides quality feedback |
| MemoryAgent | `SCR.Agents.MemoryAgent` | Memory storage (ETS with optional DETS persistence), LLM-powered summarization |
| ResearcherAgent | `SCR.Agents.ResearcherAgent` | Web research, information gathering |
| WriterAgent | `SCR.Agents.WriterAgent` | Content generation, summarization |
| ValidatorAgent | `SCR.Agents.ValidatorAgent` | Quality assurance, fact-checking |

### Message Protocol

All inter-agent communication uses `SCR.Message` struct:

```elixir
%SCR.Message{
  id: UUID,
  type: :task | :result | :status | :stop,
  from: agent_id,
  to: agent_id,
  payload: %{...}
}
```

## Key Modules

### Core System

- `SCR` - Application module, starts supervision tree
- `SCR.Agent` - Base GenServer behaviour for all agents
- `SCR.Supervisor` - DynamicSupervisor for agent lifecycle
- `SCR.Message` - Message protocol definition

### LLM Integration (`lib/scr/llm/`)

- `SCR.LLM.Client` - Unified LLM client with caching and metrics
- `SCR.LLM.Ollama` - Ollama adapter for local LLMs
- `SCR.LLM.OpenAI` - OpenAI adapter (chat, tools, embeddings, streaming)
- `SCR.LLM.Cache` - Response caching (ETS-based)
- `SCR.LLM.Metrics` - Token usage and cost tracking
- `SCR.LLM.Behaviour` - Behaviour for LLM adapters

### Tool System (`lib/scr/tools/`)

- `SCR.Tools.Registry` - Tool registration and discovery
- `SCR.Tools.Behaviour` - Behaviour for tool modules
- Tools: `Calculator`, `HTTPRequest`, `Search`, `FileOperations`, `Time`, `Weather`, `CodeExecution`

### Web Interface (`lib/scr_web/`)

- `SCRWeb.Endpoint` - Phoenix endpoint
- `SCRWeb.Router` - Route definitions
- `SCRWeb.DashboardLive` - LiveView real-time dashboard

## Configuration

### Environment Variables

```bash
LLM_BASE_URL=http://localhost:11434  # Ollama server
LLM_MODEL=llama2                      # Model name
OPENAI_API_KEY=sk-...                 # OpenAI API key
OPENAI_MODEL=gpt-4o-mini              # OpenAI model
SCR_MEMORY_PATH=tmp/memory            # DETS persistence path (optional)
```

### Config Files

- `config/config.exs` - Base configuration
- `config/dev.exs` - Development settings
- `config/prod.exs` - Production settings
- `config/test.exs` - Test settings

### LLM Configuration

```elixir
config :scr, :llm,
  provider: :ollama,
  base_url: "http://localhost:11434",
  default_model: "llama2",
  api_key: System.get_env("OPENAI_API_KEY"),
  timeout: 60_000
```

## Common Tasks

### Starting the Application

```bash
# Phoenix web interface
mix phx.server

# CLI demo
mix run -e "SCR.CLI.Demo.main([])"
```

### Starting Agents Programmatically

```elixir
# Start a memory agent
{:ok, _} = SCR.Supervisor.start_agent("memory_1", :memory, SCR.Agents.MemoryAgent, %{})

# Start a worker agent
{:ok, _} = SCR.Supervisor.start_agent("worker_1", :worker, SCR.Agents.WorkerAgent, %{})

# List running agents
SCR.Supervisor.list_agents()
```

### Sending Messages

```elixir
# Create a task message
msg = SCR.Message.task("planner_1", "worker_1", %{
  task_id: UUID.uuid4(),
  type: :research,
  description: "Research AI agent runtimes"
})

# Send to agent
SCR.Supervisor.send_to_agent("worker_1", msg)
```

### Using Tools

```elixir
# List available tools
SCR.Tools.Registry.list_tools()

# Execute a tool
SCR.Tools.Registry.execute_tool("calculator", %{"expression" => "2 + 2"})
```

### LLM Operations

```elixir
# Simple completion
SCR.LLM.Client.complete("What is Elixir?")

# Chat completion
SCR.LLM.Client.chat([
  %{role: "system", content: "You are a helpful assistant"},
  %{role: "user", content: "What is pattern matching?"}
])

# Check cache stats
SCR.LLM.Cache.stats()

# Check metrics
SCR.LLM.Metrics.stats()
```

## ETS Tables

The application uses named ETS tables created by MemoryAgent (and can optionally restore data from DETS files):

- `:scr_memory` - Task results
- `:scr_tasks` - Task definitions
- `:scr_agent_states` - Agent status data

**Important**: Always check if tables exist before accessing:

```elixir
if :ets.whereis(:scr_tasks) != :undefined do
  # Safe to access
end
```

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/path/to/test.exs

# Run with coverage
mix test --cover
```

## Code Style

- Use `mix format` before committing
- Follow Elixir naming conventions
- Add `@moduledoc` and `@doc` attributes
- Use pattern matching in function heads
- Prefer explicit returns over implicit

## File Structure

```
lib/
├── scr.ex                    # Application entry point
├── scr/
│   ├── agent.ex              # Base agent behaviour
│   ├── message.ex            # Message protocol
│   ├── supervisor.ex         # DynamicSupervisor
│   ├── agents/               # Agent implementations
│   ├── llm/                  # LLM integration
│   ├── tools/                # Tool system
│   └── cli/                  # CLI interface
└── scr_web/                  # Phoenix web interface
    ├── endpoint.ex
    ├── router.ex
    ├── live/                 # LiveView components
    └── controllers/          # HTTP controllers
```

## Dependencies

Key dependencies from `mix.exs`:

- `:phoenix` - Web framework
- `:phoenix_live_view` - Real-time UI
- `:phoenix_pubsub` - PubSub for agent events
- `:httpoison` - HTTP client for LLM API calls
- `:jason` - JSON parsing
- `:elixir_uuid` - UUID generation

## Known Issues

1. **ETS Table Initialization**: Tables are created by MemoryAgent. If MemoryAgent hasn't started, accessing tables will fail. Always use defensive checks.

2. **Tool Testing**: The `/tools` page test functionality requires JavaScript and a running server.

3. **LLM Fallback**: If LLM is unavailable, agents fall back to mock responses. Check logs for fallback warnings.

## Future Roadmap

See `SCR_Improvements.md` for planned features:

- Anthropic adapter support
- Production JSON logging profile + OpenTelemetry log/trace export bridge
- Distributed agent support

## Related Documentation

- `README.md` - Project overview and features
- `QUICKSTART.md` - Getting started guide
- `SCR_UseCases.md` - Usage examples
- `SCR_LLM_Documentation.txt` - LLM integration details
- `SCR_Improvements.md` - Roadmap and planned features
- `plans/phoenix_web_interface_plan.md` - Web interface design

## Version

Current version: **v0.2.0-alpha**

This is an early alpha release for feedback and testing. Expect breaking changes.
