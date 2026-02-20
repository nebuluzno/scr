# SCR Competitive Comparison

This document compares SCR to common agent/runtime options used in production and research workflows.

## Scope of Comparison

Systems considered:
- LangGraph (Python graph-based agent orchestration)
- AutoGen (multi-agent conversation framework)
- CrewAI (role-based multi-agent workflows)
- Temporal (durable workflow orchestration)
- Ray (distributed Python compute/runtime)
- Akka/Pekko actor systems (JVM actor runtime)

SCR baseline in this repo:
- OTP-native supervised agents on BEAM/Elixir
- Hybrid tool layer (native + MCP) with strict/demo policy modes
- Shared multi-agent context with sharded ownership
- Priority queue with optional DETS durability and replay
- Distributed support baseline (libcluster discovery + handoff + quarantine watchdog)
- Built-in telemetry, Prometheus metrics, dashboard, and alert starter configs

## Where SCR Is Strong

1. OTP fault-tolerance model as first-class runtime primitive
- Supervision trees, crash isolation, and restart semantics are native, not bolted on.

2. Long-lived process model for agent workloads
- BEAM process scheduling is efficient for high concurrency and message-driven flows.

3. Unified tool governance
- One registry and policy path for local deterministic tools and external MCP tools.

4. Local-first distributed experiments
- Discovery, node handoff, and watchdog quarantine are integrated for multi-node testing.

5. Operational visibility built in
- Queue/tool/health telemetry + Prometheus endpoint + Grafana starter dashboard.

## Where Other Systems Are Stronger Today

1. Ecosystem breadth
- Python ecosystems (LangGraph/AutoGen/CrewAI/Ray) have broader LLM/plugin examples.

2. Enterprise workflow guarantees
- Temporal provides mature workflow durability/versioning tooling for business-critical pipelines.

3. Out-of-the-box cloud integrations
- Some frameworks provide richer vendor adapters and managed-platform integrations.

4. Team familiarity
- Python/JVM stacks may be easier to staff for many organizations today.

## Practical Positioning

SCR is best when you need:
- OTP-grade resilience and actor-style runtime behavior
- Fine-grained control over safety/policy execution paths
- Research or production prototypes where process supervision and distributed behavior matter

A different stack may be better when you need:
- Immediate access to huge Python agent-template ecosystems
- Heavy existing investment in Temporal workflow tooling
- Team standardization on non-BEAM runtimes

## Decision Checklist

Choose SCR if most of these are true:
1. You need supervised long-running agents with restart isolation.
2. You want strict local governance of tools and external MCP access.
3. You need distributed experiments with node handoff/quarantine behavior.
4. You can operate Elixir/OTP in your environment.

Choose alternatives first if most of these are true:
1. You need broad third-party template ecosystems immediately.
2. Your organization is standardized on Python/JVM and cannot add BEAM.
3. You require a fully managed workflow platform with deep enterprise integrations now.
