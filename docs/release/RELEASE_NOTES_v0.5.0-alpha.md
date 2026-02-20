# SCR v0.5.0-alpha Release Notes
Doc Owner: SCR Maintainers

Release date: 2026-02-20

## Highlights
- Completed all remaining high-value backlog items from the previous cycle:
  - telemetry event stream (`SCR.Telemetry.Stream`) with recent-event API and PubSub feed
  - Prometheus telemetry tags expanded for per-agent tool/health visibility
  - `PartitionSupervisor`-backed sharded `SCR.AgentContext`
  - durable/replayable queue backend via DETS (`SCR.TaskQueue` `backend: :dets`)
  - persistent-term hot-path config cache (`SCR.ConfigCache`)
  - distributed placement strategy v2 with weighted scoring (`SCR.Distributed.placement_report/2`, `pick_start_node/1`)
- Distributed runtime remains integrated with:
  - discovery (`libcluster`)
  - spec replication and handoff (`SCR.Distributed.SpecRegistry`/`HandoffManager`)
  - node watchdog quarantine (`SCR.Distributed.NodeWatchdog`)
  - placement strategy v3 with rolling growth penalties + hard constraints (`placement_constraints`, growth weights)
  - cross-node queue pressure propagation and scheduler throttling (`SCR.Distributed.queue_pressure_report/2`, `cluster_backpressured?/2`)
- LLM failover policy hardening now includes:
  - fail-open/fail-closed runtime mode (`failover_mode`)
  - retry budget windows (`failover_retry_budget`)
  - explicit provider circuit state API (`SCR.LLM.Client.failover_state/0`)
- Memory persistence now supports optional SQLite backend in `MemoryAgent` (`config :scr, :memory_storage, backend: :sqlite`).
- Memory persistence now supports optional Postgres backend in `MemoryAgent` (`config :scr, :memory_storage, backend: :postgres`).
- Distributed task routing now supports optional at-least-once semantics with dedupe keys (`config :scr, :distributed, routing: [...]`).
- Placement observability now includes dashboard history snapshots for placement scoring and quarantine state (`SCR.Distributed.PlacementHistory`, `DashboardLive`).
- Workload class routing added for capability-aware node selection (`SCR.Distributed.pick_start_node_for_class/2`, `workload_routing` config).
- Automatic capacity tuning added for adaptive queue sizing (`SCR.Distributed.CapacityTuner`, `capacity_tuning` config).
- Recovery drills added for scripted chaos validation (`SCR.Distributed.RecoveryDrills`).
- Added memory migration + verification tooling:
  - `mix scr.memory.migrate` (backend migration)
  - `mix scr.memory.verify` (integrity/consistency checks)
- Added tool governance v2:
  - policy profiles (`strict`, `balanced`, `research`) with runtime switching API
  - per-tool profile overrides in policy engine
  - tool audit trail (`SCR.Tools.AuditLog`) with dashboard visibility
- Added scheduler fairness + smarter capacity tuning:
  - weighted class-aware dequeue fairness in `SCR.TaskQueue`
  - dequeue fairness telemetry labels
  - capacity tuning decisions now account for estimated latency SLO
  - tuning telemetry includes explicit decision reason labels
- Expanded mature tutorial track:
  - distributed resilience drills
  - memory backend migration + verify workflow
  - tool policy profile + audit workflow
  - production hardening runbook flow
- Docs CI now includes command-smoke checks for key tutorial commands.

## Notable Ops/Docs Additions
- Added telemetry + durable queue replay tutorial (`TUTORIALS.md`, Tutorial 12).
- Added future roadmap list (`docs/roadmap/FUTURE_TODO.md`).
- Added market positioning document (`docs/positioning/SCR_Competitive_Comparison.md`).
- Updated `README.md`, `QUICKSTART.md`, `AGENTS.md`, and `SCR_Improvements.md`.

## Known Follow-ups (Post v0.5.0-alpha)
- Populate next-cycle roadmap candidates in `docs/roadmap/FUTURE_TODO.md`.
