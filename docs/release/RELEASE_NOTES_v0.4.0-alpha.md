# SCR v0.4.0-alpha Release Notes
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

## Notable Ops/Docs Additions
- Added telemetry + durable queue replay tutorial (`TUTORIALS.md`, Tutorial 12).
- Added future roadmap list (`docs/roadmap/FUTURE_TODO.md`).
- Added market positioning document (`docs/positioning/SCR_Competitive_Comparison.md`).
- Updated `README.md`, `QUICKSTART.md`, `AGENTS.md`, and `SCR_Improvements.md`.

## Known Follow-ups (Post v0.4.0-alpha)
- Cross-node backpressure-aware scheduling
- Failover policy hardening (fail-open/fail-closed modes + retry budgets + provider circuit visibility)
- Larger-scale durable memory backend options (beyond DETS)
