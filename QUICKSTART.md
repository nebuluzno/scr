# SCR Quick Start Guide

## Prerequisites

- Elixir 1.14+ and Erlang/OTP 24+
- (Optional) Ollama for LLM-powered features

## Installation

```bash
# Install dependencies
mix deps.get

# Compile the project
mix compile
```

## Running the Application

### Option 1: Phoenix Web Interface

```bash
mix phx.server
```

Then open http://localhost:4000 in your browser.

Features available:
- Real-time dashboard with agent status
- Task submission interface
- LLM metrics and cache statistics
- Tool testing interface

### Option 2: CLI Demo

```bash
# Basic demo (uses mock data if no LLM available)
mix run -e "SCR.CLI.Demo.main([])"

# Crash recovery test
mix run -e "SCR.CLI.Demo.main([\"--crash-test\"])"
```

## LLM Integration (Optional)

### Setting up Ollama

1. Install Ollama: https://ollama.ai

2. Start the Ollama server:
   ```bash
   ollama serve
   ```

3. Pull a model:
   ```bash
   ollama pull llama2
   ```

4. Configure (optional - defaults work for local Ollama):
   ```bash
   export LLM_BASE_URL=http://localhost:11434
   export LLM_MODEL=llama2
   ```

### Without LLM

The system works without an LLM connection - agents automatically fall back to mock responses. This is useful for:
- Development and testing
- CI/CD pipelines
- Learning the agent architecture

## Testing the System

### Test 1: Basic Agent Communication

```bash
iex -S mix
```

```elixir
# Start a memory agent
{:ok, _} = SCR.Supervisor.start_agent("memory_1", :memory, SCR.Agents.MemoryAgent, %{})

# Start a worker agent
{:ok, _} = SCR.Supervisor.start_agent("worker_1", :worker, SCR.Agents.WorkerAgent, %{})

# List running agents
SCR.Supervisor.list_agents()

# Check agent status
SCR.Supervisor.get_agent_status("worker_1")
```

### Test 2: Tool System

```bash
iex -S mix
```

```elixir
# List available tools
SCR.Tools.Registry.list_tools()

# Execute a calculator tool
SCR.Tools.Registry.execute_tool("calculator", %{"expression" => "2 + 2"})

# Get current time
SCR.Tools.Registry.execute_tool("time", %{"timezone" => "Europe/Stockholm"})
```

### Test 3: LLM Client (with Ollama)

```bash
iex -S mix
```

```elixir
# Check LLM connection
SCR.LLM.Client.ping()

# Simple completion
SCR.LLM.Client.complete("What is Elixir?")

# Check cache stats
SCR.LLM.Cache.stats()

# Check metrics
SCR.LLM.Metrics.stats()
```

### Test 4: Full Multi-Agent Workflow

```bash
mix run -e "SCR.CLI.Demo.main([])"
```

This will:
1. Start MemoryAgent, CriticAgent, PlannerAgent
2. Submit a research task
3. PlannerAgent decomposes into subtasks
4. WorkerAgents execute subtasks
5. CriticAgent evaluates results
6. Display final statistics

## Troubleshooting

### Port Already in Use

If port 4000 is taken:
```bash
# Kill the process using the port
lsof -ti:4000 | xargs kill -9

# Or use a different port
PORT=4001 mix phx.server
```

### ETS Table Errors

If you see ETS table errors, ensure the application started correctly:
```bash
# Stop any running instances
# Restart with
mix clean && mix compile && mix phx.server
```

### Ollama Connection Failed

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Start Ollama if not running
ollama serve
```

## Project Structure

```
lib/
├── scr.ex                    # Application entry point
├── scr/
│   ├── agent.ex              # Base agent behavior
│   ├── supervisor.ex         # Dynamic supervisor
│   ├── agents/               # Agent implementations
│   │   ├── memory_agent.ex
│   │   ├── planner_agent.ex
│   │   ├── worker_agent.ex
│   │   ├── critic_agent.ex
│   │   ├── researcher_agent.ex
│   │   ├── writer_agent.ex
│   │   └── validator_agent.ex
│   ├── llm/                  # LLM integration
│   │   ├── client.ex
│   │   ├── ollama.ex
│   │   ├── cache.ex
│   │   └── metrics.ex
│   └── tools/                # Tool system
│       ├── registry.ex
│       └── *.ex              # Individual tools
└── scr_web/                  # Phoenix web interface
    ├── endpoint.ex
    ├── router.ex
    └── live/                 # LiveView components
```
