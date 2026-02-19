# Phoenix Web Interface - Implementation Plan

## Vision
A web-based dashboard to monitor and interact with the SCR multi-agent system in real-time.

## Feature Ideas

### Phase 1: MVP (Simple but Functional)
1. **Agent Dashboard**
   - List all running agents with status
   - Show agent details (type, state, uptime)
   - Basic refresh mechanism

2. **System Status**
   - Show overall system health
   - Display active agent count
   - Show memory/storage usage

3. **Task Submission**
   - Simple form to submit new tasks
   - Input field for task description
   - Submit button to send to PlannerAgent

### Phase 2: Real-time Features
4. **Live Agent Updates**
   - WebSocket for real-time agent status
   - Auto-refresh when agents change state

5. **Task Tracking**
   - View task progress
   - See intermediate results
   - Task history

### Phase 3: Enhanced UI
6. **Agent Details View**
   - Individual agent pages
   - View agent memory/state
   - View message history

7. **LLM Metrics Dashboard**
   - Token usage charts
   - Cost tracking visualization
   - Cache hit rates

8. **Memory Browser**
   - Browse stored tasks
   - Browse agent states
   - Search functionality

### Phase 4: Advanced Features
9. **Agent Control**
   - Start/stop agents from UI
   - Trigger agent actions
   - View and clear memory

10. **Interactive Demo**
    - One-click demo runner
    - Visual task flow
    - Crash simulation

## Architecture

```
SCR Phoenix App
├── Web.Endpoint      # Phoenix endpoint
├── Router            # URL routing
├── Controllers       # HTTP handlers
│   ├── AgentController     # Agent CRUD
│   ├── TaskController      # Task submission
│   └── SystemController    # System status
├── LiveViews         # Real-time UI
│   ├── DashboardLive      # Main dashboard
│   ├── AgentLive           # Agent details
│   └── MetricsLive         # LLM metrics
└── PubSub            # Real-time updates
```

## Pages Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Dashboard | Main overview |
| `/agents` | Agent List | All agents |
| `/agents/:id` | Agent Detail | Single agent |
| `/tasks` | Task List | Task history |
| `/tasks/new` | New Task | Submit task |
| `/metrics` | Metrics | LLM stats |
| `/memory` | Memory Browser | View storage |

## Implementation Steps

### Step 1: Setup Phoenix
- [ ] Add Phoenix dependencies to mix.exs
- [ ] Create Phoenix app structure
- [ ] Configure endpoint
- [ ] Test basic server runs

### Step 2: Basic UI
- [ ] Create main layout
- [ ] Build agent list page
- [ ] Add system status section
- [ ] Style with CSS

### Step 3: Task Submission
- [ ] Create task form
- [ ] Connect to PlannerAgent
- [ ] Show submission feedback

### Step 4: Real-time
- [ ] Add PubSub for updates
- [ ] Implement WebSocket
- [ ] LiveView for dashboard

### Step 5: Metrics
- [ ] Connect to Metrics module
- [ ] Display token usage
- [ ] Show cache stats

### Step 6: Polish
- [ ] Add agent details pages
- [ ] Memory browser
- [ ] Better styling

## Tech Stack
- Phoenix 1.7+
- LiveView for real-time
- TailwindCSS for styling
- PubSub for updates
