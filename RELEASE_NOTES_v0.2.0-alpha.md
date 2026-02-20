# SCR v0.2.0-alpha Release Notes

Release date: 2026-02-20

## Highlights
- Unified hybrid tool architecture (native + MCP) with strict/demo policy path.
- Execution context propagation (`trace_id`, `task_id`, `parent_task_id`, `subtask_id`) through planner/worker/tools.
- Priority queue, health checks, shared agent context lifecycle, and tool rate limiting.
- Web UI improvements for task/memory context visibility and operational controls.
- Full observability baseline:
  - Prometheus scrape endpoint: `/metrics/prometheus`
  - Runtime telemetry for queue, tools, rate limits, health, and MCP outcomes
  - Grafana dashboard starter: `priv/grafana/scr-runtime-overview.json`
  - Prometheus alert rules + Alertmanager starter config
  - One-command observability stack via `docker-compose.observability.yml`
  - `Makefile` operational shortcuts (`obs-up`, `obs-down`, `obs-logs`, `obs-reset`)
- CI/doc quality improvements:
  - docs lint + link checks
  - visual snapshot artifact job
  - optional MCP smoke CI path (secret-gated)

## Notable Ops/Docs Additions
- Release process checklist: `RELEASE_CHECKLIST.md`
- Tutorials expanded with observability bring-up flow: `TUTORIALS.md`

## Known Follow-ups (Post v0.2.0-alpha)
- OpenAI/Anthropic adapters
- Streaming LLM responses
- persistent storage backend beyond ETS
- distributed agent support
- enhanced tool sandboxing
