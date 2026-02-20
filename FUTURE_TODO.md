# SCR Future TODO

This list is intentionally forward-looking and does **not** duplicate already-delivered items.

## High Priority

1. Cross-node backpressure propagation
- Publish per-node queue pressure into distributed scheduler decisions.
- Throttle new subtasks when cluster saturation exceeds threshold.

2. Placement strategy v3
- Extend weighted placement with rolling latency and throughput trends from telemetry history.
- Add configurable hard constraints (max agents per node, max queue per node).

3. Failover policy hardening
- Add fail-open/fail-closed modes, retry budgets, and explicit provider circuit state endpoints.

## Medium Priority

1. Durable memory backend expansion
- Add optional SQLite/Postgres backend for `MemoryAgent`/context persistence at larger scale.

2. Distributed task routing semantics
- Add optional at-least-once delivery with dedupe keys for inter-node task messages.

3. Placement observability
- Add dashboard panel for node quarantine state and placement decisions over time.

## Nice to Have

1. Workload class routing
- Allow declaring classes (`cpu`, `io`, `external_api`) and map them to node capabilities.

2. Automatic capacity tuning
- Adapt partition counts and queue limits based on observed throughput/latency.

3. Recovery drills
- Add scripted chaos scenarios for node flapping and partial network partitions.
