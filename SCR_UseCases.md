# SCR Agentic Use Cases

This document outlines three practical agentic use cases that can be implemented with the current SCR (Supervised Cognitive Runtime) system.

---

## Current Capabilities Summary

## Run These Use Cases

### CLI path
```bash
mix run -e "SCR.CLI.Demo.main([])"
```
Use this when you want a terminal-first execution trace.

### Web UI path
```bash
mix phx.server
```
Then open [http://localhost:4000](http://localhost:4000), go to `/tasks/new`, and submit a use-case prompt from this document.

### Agents
- **PlannerAgent** - Decomposes tasks, coordinates workers
- **WorkerAgent** - Executes subtasks with LLM + tool access
- **CriticAgent** - Evaluates results, provides feedback
- **MemoryAgent** - Persistent ETS-based storage

### Tools Available
| Tool | Capabilities |
|------|-------------|
| Calculator | Math operations (add, subtract, multiply, divide, power, sqrt, modulo) |
| HTTP Request | GET, POST, PUT, DELETE to any URL |
| Search | Web search via DuckDuckGo |
| File Operations | Read/write files in workspace |
| Time | Get current time in any format/timezone |
| Weather | Real-time weather for any location |
| Code Execution | Execute Elixir code safely |

### Infrastructure
- Phoenix Web Interface (dashboard, agents, tasks, tools, memory, metrics)
- LLM Integration (Ollama with function calling)
- Supervision Trees (crash recovery)
- ETS-based caching and memory

---

## Use Case 1: Research Assistant

### Description
An agent that researches a topic, gathers information from multiple sources, and produces a structured report.

### Flow
```
User Query → PlannerAgent
    ↓
    ├── WorkerAgent 1: Search for primary sources
    ├── WorkerAgent 2: Search for recent news
    ├── WorkerAgent 3: Get weather/context if location-related
    ↓
CriticAgent: Evaluate completeness and quality
    ↓
MemoryAgent: Store research results
    ↓
Final Report
```

### Example Prompts
- "Research the current state of AI agent frameworks and summarize key players"
- "What are the latest developments in quantum computing?"
- "Compare Elixir and Go for building distributed systems"

### Tools Used
- `search` - Find relevant information
- `http_request` - Fetch detailed content from URLs
- `file_operations` - Save research notes
- `time` - Timestamp research

### Implementation Notes
```elixir
# Example task submission
SCR.submit_task(%{
  type: :research,
  description: "Research AI agent frameworks",
  options: %{
    max_workers: 3,
    search_depth: 2,
    output_format: :markdown
  }
})
```

### Optimization Opportunities
1. **Parallel Worker Execution** - Run multiple workers concurrently using `Task.async_stream`
2. **Result Deduplication** - Use MemoryAgent to avoid re-searching same topics
3. **Source Credibility Scoring** - CriticAgent can rate source reliability
4. **Incremental Updates** - Store research state, allow resuming interrupted research

---

## Use Case 2: Data Analysis Pipeline

### Description
An agent that fetches data, performs calculations, and generates insights with visualizations.

### Flow
```
Data Request → PlannerAgent
    ↓
    ├── WorkerAgent 1: Fetch data (HTTP/API)
    ├── WorkerAgent 2: Transform/clean data (Code Execution)
    ├── WorkerAgent 3: Calculate statistics (Calculator)
    ↓
CriticAgent: Validate calculations, check for anomalies
    ↓
MemoryAgent: Store results with timestamps
    ↓
Analysis Report + Data Artifacts
```

### Example Prompts
- "Analyze the weather trends for Stockholm over the past week"
- "Calculate the compound interest for $10,000 at 5% over 10 years"
- "Fetch and summarize the latest from this API endpoint"

### Tools Used
- `http_request` - Fetch data from APIs
- `calculator` - Perform calculations
- `code_execution` - Transform data, run algorithms
- `weather` - Get weather data
- `file_operations` - Save results

### Implementation Notes
```elixir
# Example analysis task
SCR.submit_task(%{
  type: :analysis,
  description: "Analyze stock prices and calculate moving averages",
  data_source: "https://api.example.com/stocks",
  operations: [
    {:fetch, :http_request, %{url: "https://api.example.com/stocks"}},
    {:transform, :code_execution, %{code: "Enum.map(data, &Map.get(&1, \"price\"))"}},
    {:calculate, :calculator, %{operation: "average"}}
  ]
})
```

### Optimization Opportunities
1. **Streaming Data Processing** - Process large datasets in chunks
2. **Caching Layer** - Cache API responses to avoid redundant fetches
3. **Pipeline Optimization** - Chain operations without intermediate storage
4. **Error Recovery** - Resume from last successful step on failure

---

## Use Case 3: Intelligent Task Orchestrator

### Description
An agent that breaks down complex multi-step tasks, coordinates execution, and handles failures gracefully.

### Flow
```
Complex Task → PlannerAgent
    ↓
    Plan: [Step1, Step2, Step3, ...]
    ↓
    ├── WorkerAgent executes Step1
    │   └── Uses tools as needed
    ├── CriticAgent validates Step1
    ├── If failed: retry or replan
    ├── WorkerAgent executes Step2
    │   └── May spawn sub-workers
    ├── CriticAgent validates Step2
    ↓
    Continue until complete
    ↓
MemoryAgent: Store full execution trace
    ↓
Final Result with Provenance
```

### Example Prompts
- "Plan and execute a market research project for a new product"
- "Set up a monitoring system for server health"
- "Create a documentation website from code comments"

### Tools Used
- All tools available as needed
- MemoryAgent for state persistence
- CriticAgent for quality gates

### Implementation Notes
```elixir
# Example orchestration task
SCR.submit_task(%{
  type: :orchestration,
  description: "Deploy and test a new feature",
  steps: [
    %{action: :build, tools: [:code_execution]},
    %{action: :test, tools: [:code_execution]},
    %{action: :deploy, tools: [:http_request]},
    %{action: :verify, tools: [:http_request, :search]}
  ],
  failure_policy: :retry_with_replan,
  max_retries: 3
})
```

### Optimization Opportunities
1. **Adaptive Planning** - PlannerAgent adjusts plan based on intermediate results
2. **Resource Pooling** - Reuse WorkerAgents instead of spawning new ones
3. **Priority Queuing** - Execute critical path steps first
4. **Checkpointing** - Save state at each step for recovery

---

## Architecture Improvements

### 1. Agent Communication Optimization

**Current:** Synchronous message passing
**Improved:** Event-driven with pub/sub

```elixir
# Add to SCR.Application
children = [
  {Registry, keys: :unique, name: SCR.AgentRegistry},
  {Phoenix.PubSub, name: SCR.PubSub},
  # ... other children
]

# Agents subscribe to events
Phoenix.PubSub.subscribe(SCR.PubSub, "task:#{task_id}")

# Broadcast results
Phoenix.PubSub.broadcast(SCR.PubSub, "task:#{task_id}", {:result, result})
```

### 2. Tool Execution Caching

**Current:** Each tool call executes fresh
**Improved:** Cache identical tool calls

```elixir
defmodule SCR.Tools.Cache do
  use Agent
  
  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)
  
  def execute_cached(tool, params, ttl \\ 300_000) do
    key = {tool, :erlang.phash2(params)}
    
    case Agent.get(__MODULE__, &Map.get(&1, key)) do
      {:ok, cached, expires_at} when expires_at > System.system_time(:millisecond) ->
        {:ok, cached}
      _ ->
        result = tool.execute(params)
        Agent.update(__MODULE__, &Map.put(&1, key, {result, System.system_time(:millisecond) + ttl}))
        result
    end
  end
end
```

### 3. Parallel Worker Execution

**Current:** Sequential worker spawning
**Improved:** Concurrent execution with supervision

```elixir
defmodule SCR.WorkerPool do
  def execute_parallel(tasks, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    
    tasks
    |> Task.async_stream(
      fn task -> SCR.Agents.WorkerAgent.execute(task) end,
      max_concurrency: max_concurrency,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
```

### 4. LLM Response Streaming

**Current:** Wait for full LLM response
**Improved:** Stream tokens in real-time

```elixir
# Already implemented in SCR.LLM.Ollama.stream/3
# Can be used for real-time UI updates:

defmodule SCRWeb.Live.TaskProgress do
  use Phoenix.LiveView
  
  def handle_info({:token, token}, socket) do
    {:noreply, update(socket, :output, &(&1 <> token))}
  end
end
```

### 5. Memory Optimization

**Current:** All memory in ETS
**Improved:** Tiered storage

```elixir
# Hot data: ETS (in-memory)
# Warm data: DETS (disk-based)
# Cold data: PostgreSQL

defmodule SCR.Memory.Tiered do
  def store(key, value, tier \\ :hot) do
    case tier do
      :hot -> :ets.insert(:scr_memory_hot, {key, value})
      :warm -> :dets.insert(:scr_memory_warm, {key, value})
      :cold -> SCR.Repo.insert(%MemoryEntry{key: key, value: value})
    end
  end
end
```

---

## Quick Start Examples

### Run a Research Task
```bash
iex -S mix
```
```elixir
# Start the system
SCR.start_link([])

# Submit a research task
SCR.submit_task(%{
  type: :research,
  description: "What are the main features of Elixir's OTP?"
})

# Check memory for results
SCR.Agents.MemoryAgent.get_all()
```

### Run the Web Interface
```bash
mix phx.server
# Visit http://localhost:4000
```

### Test Tool Execution
```bash
# Via IEx
iex> SCR.Tools.Calculator.execute(%{"operation" => "add", "a" => 10, "b" => 20})
{:ok, 30}

iex> SCR.Tools.Weather.execute(%{"location" => "Stockholm"})
{:ok, %{location: "Stockholm, Sweden", temperature: 5.2, ...}}

iex> SCR.Tools.Time.execute(%{"format" => "pretty"})
{:ok, "February 19, 2026 at 10:19 PM UTC"}
```

---

## Next Steps

1. **Implement LiveView UI** - Real-time task progress visualization
2. **Add Workflow Definitions** - Pre-defined task templates
3. **Create Tool Chains** - Compose multiple tools into workflows
4. **Add Rate Limiting** - Prevent API abuse
5. **Implement Retries** - Automatic retry with exponential backoff
6. **Add Logging** - Structured logging for debugging and auditing
