# Distributed Resilience Runbook
Doc Owner: SCR Maintainers

This runbook defines the local workflow for deterministic resilience validation.

## Test Suites

1. Single-node resilience checks:
```bash
mix test --only distributed_resilience --exclude multi_node
```

2. Multi-node resilience checks:
```bash
SCR_RUN_MULTI_NODE_TESTS=true mix test --only distributed_resilience --only multi_node
```

3. Full distributed folder:
```bash
mix test test/scr/distributed
```

## What Is Validated

1. Node partition and rejoin drill
- A peer node is disconnected and then reconnected.
- Cluster connectivity is re-established (`Node.list/0` includes peer).

2. Node flap quarantine and recovery
- Repeated down events quarantine a node in watchdog state.
- Rejoin/up event clears quarantine and restores placement eligibility.

3. Queue recovery after saturation
- Queue rejection path is exercised deterministically.
- Queue resumes accepting work after drain/dequeue recovery step.

4. Cross-node queue pressure recovery
- Remote queue reaches saturation and is visible in pressure report.
- After remote drain, saturation and utilization metrics recover.

## Expected Outcomes

1. All resilience tests pass with zero failures.
2. Multi-node drill tests are stable across repeated runs.
3. CI matrix job `Distributed Resilience` passes both:
- `single-node`
- `multi-node`

## Troubleshooting

1. If multi-node tests fail early with distribution errors:
```bash
epmd -daemon
```

2. If peer startup fails repeatedly:
- Verify local hostname resolution for short names.
- Re-run tests in a clean shell session.

3. If CI and local behavior diverge:
- Run each matrix command locally in the same order as CI.
- Capture `Node.self()` and `Node.list()` during failures for diagnostics.
