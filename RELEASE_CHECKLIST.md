# SCR Release Checklist
Doc Owner: SCR Maintainers

This checklist prepares the next release cut.  
Current docs version label: `v0.4.0-alpha`  
Suggested next target: `v0.4.1-alpha`

## 1. Pre-release validation
1. Run:
```bash
mix format
mix compile --warnings-as-errors
mix test
```
2. Validate docs:
```bash
npx -y markdownlint-cli@0.39.0 --config .markdownlint.json README.md QUICKSTART.md TUTORIALS.md DOCS_INDEX.md SCR_Improvements.md AGENTS.md docs/guides/SCR_UseCases.md docs/guides/SCR_Medium_Article.md docs/positioning/SCR_Competitive_Comparison.md docs/roadmap/FUTURE_TODO.md docs/release/RELEASE_NOTES_v0.4.0-alpha.md plans/*.md
```
3. Smoke-check MCP integration:
```bash
mix scr.mcp.smoke
```

## 2. Version alignment
1. Update `mix.exs` `version`.
2. Update version references in:
- `README.md`
- `AGENTS.md`
- `lib/scr_web/components/layouts/root.html.heex`
- `lib/scr/tools/mcp/client.ex`
- any release notes/changelog

## 3. Release notes
1. Summarize major delivered items since last version:
- Hybrid tools (native + MCP)
- Strict/demo policy + execution context propagation
- Queue + health + rate limiter + agent context lifecycle
- Web UI context visibility + monitoring polish
- Prometheus metrics, alert templates, Grafana dashboard, observability compose stack
2. Add known limitations and planned follow-ups.

## 4. Tag and publish
1. Commit final version updates.
2. Create annotated tag:
```bash
git tag -a v0.4.0-alpha -m "SCR v0.4.0-alpha"
```
3. Push branch and tags:
```bash
git push
git push --tags
```

## 5. Post-release sanity
1. Pull fresh clone and run quickstart.
2. Confirm Web UI + `/metrics/prometheus` + observability compose stack work as documented.
