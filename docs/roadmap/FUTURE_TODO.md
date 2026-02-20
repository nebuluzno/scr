# SCR Future TODO
Doc Owner: SCR Maintainers

Current planning target: **v0.6.0-alpha**

The v0.5.0-alpha roadmap cycle is complete. This file now tracks next-cycle candidates.

## Prioritized Backlog (v0.6.0-alpha)

1. `[planned][P0]` Distributed chaos automation in CI
- Scope:
  - Run scripted partition/flap/rejoin drills as repeatable CI jobs on a multi-node matrix.
  - Persist structured drill reports as CI artifacts.
- Acceptance criteria:
  - CI produces per-scenario pass/fail reports and key recovery timings.
  - Failures include drill phase and node-level diagnostics.

2. `[planned][P0]` Persistent tool audit backend hardening
- Scope:
  - Add retention/rotation policy for DETS audit logs.
  - Add export command (`mix scr.tools.audit.export`) for postmortem analysis.
- Acceptance criteria:
  - Audit retention bounds are configurable and tested.
  - Export produces deterministic JSONL output.

3. `[planned][P1]` Adaptive fairness weights
- Scope:
  - Add runtime API to tune class weights without restart.
  - Introduce fairness score metrics (served ratio vs configured weight).
- Acceptance criteria:
  - Weight updates are applied live and reflected in telemetry.
  - Starvation regression tests remain green under skewed workloads.

4. `[planned][P1]` Operator diagnostics bundle
- Scope:
  - Add `mix scr.diagnostics.bundle` to collect config/runtime/telemetry snapshots.
  - Include queue pressure, placement history, policy profile, and audit samples.
- Acceptance criteria:
  - Bundle command produces a reproducible archive in `tmp/diagnostics/`.
  - Sensitive env fields are redacted by default.

5. `[planned][P2]` Documentation IA pass
- Scope:
  - Split large tutorials into focused guide files under `docs/guides/`.
  - Add a short “choose your path” quickstart map for operators vs developers.
- Acceptance criteria:
  - `DOCS_INDEX.md` reflects the new structure.
  - Docs lint/link checks stay green with no stale references.
