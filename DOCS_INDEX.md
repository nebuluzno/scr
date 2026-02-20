# SCR Documentation Index
Doc Owner: SCR Maintainers

Use this file as the canonical entry point for project documentation.

## Start Here

1. `/Users/lars/Documents/SCR/README.md`
- Product-level overview, capabilities, and core config.

2. `/Users/lars/Documents/SCR/QUICKSTART.md`
- Fast local setup and smoke validation.

3. `/Users/lars/Documents/SCR/TUTORIALS.md`
- Step-by-step operational labs.

## Architecture and Runtime

1. `/Users/lars/Documents/SCR/AGENTS.md`
- Agent/runtime architecture reference for contributors and coding agents.

2. `/Users/lars/Documents/SCR/docs/architecture/SCR_LLM_Documentation.txt`
- LLM integration details.

3. `/Users/lars/Documents/SCR/docs/guides/SCR_UseCases.md`
- Example scenarios and usage flows.

## Planning and Roadmap

1. `/Users/lars/Documents/SCR/SCR_Improvements.md`
- Delivered milestone log and current recommendations.

2. `/Users/lars/Documents/SCR/docs/roadmap/FUTURE_TODO.md`
- Forward-looking backlog for upcoming work.

## Releases and Operations

1. `/Users/lars/Documents/SCR/docs/release/RELEASE_NOTES_v0.4.0-alpha.md`
- Current release highlights and follow-ups.

2. `/Users/lars/Documents/SCR/RELEASE_CHECKLIST.md`
- Release validation and cut process.

## Comparative Positioning

1. `/Users/lars/Documents/SCR/docs/positioning/SCR_Competitive_Comparison.md`
- Practical comparison against common alternatives.

## Documentation Cleanup Rules (Adopted)

1. Single-source ownership
- Keep each topic primarily in one file; link instead of duplicating long sections.

2. Stable progression
- `README` for overview, `QUICKSTART` for first run, `TUTORIALS` for depth.

3. Config consistency
- Every new config key must be documented in `README` and, when operationally relevant, in `QUICKSTART`.

4. Release alignment
- Version strings, release notes, and checklist targets must be updated together.

5. Future work isolation
- Keep upcoming ideas only in `docs/roadmap/FUTURE_TODO.md`; keep `SCR_Improvements.md` focused on delivered history.

## Docs Changelog

- 2026-02-20: Created docs index and standardized doc ownership lines.
- 2026-02-20: Moved long-form guides/architecture/roadmap/positioning/release docs under `docs/`.
- 2026-02-20: Added docs CI version-drift check (`mix.exs` vs README/AGENTS/UI footer/MCP client).
