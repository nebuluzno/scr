# SCR v0.3.0-alpha Release Notes

Release date: 2026-02-20

## Highlights
- Distributed runtime baseline now includes:
  - `libcluster` node discovery (EPMD topology support)
  - cross-node agent identity via global registration
  - distributed spec replication (`SCR.Distributed.SpecRegistry`)
  - node-down handoff manager (`SCR.Distributed.HandoffManager`)
  - watchdog/quarantine for flapping peers (`SCR.Distributed.NodeWatchdog`)
- Distributed placement and operations APIs:
  - watchdog-aware auto placement (`SCR.Distributed.start_agent/5`, `pick_start_node/1`)
  - explicit handoff (`SCR.Distributed.handoff_agent/3`)
  - remote health checks and cluster health summaries
- Hybrid tool architecture, policy enforcement, and execution-context propagation remain integrated and validated.
- Observability, docs quality gates, and visual regression checks remain in CI baseline.

## Notable Ops/Docs Additions
- Distributed hardening and handoff walkthrough in tutorials (`TUTORIALS.md`, Tutorial 11).
- Updated `README.md`, `QUICKSTART.md`, and `AGENTS.md` with distributed config and security guidance.

## Known Follow-ups (Post v0.3.0-alpha)
- Distributed placement strategy v2 (load/latency/failure weighted node scoring)
- Durable task queue backend with replay
- Provider failover policy across LLM backends
