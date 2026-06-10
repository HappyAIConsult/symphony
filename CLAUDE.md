# Symphony — memory for Claude Code

Symphony turns a Linear board into a control plane for coding agents: it polls
Linear, creates an isolated per-issue workspace, and runs a coding agent (Codex
or Claude, selected by `agent.kind`) inside it.

When working on tasks in this repository, treat the following as authoritative:

- Product spec: @SPEC.md
- Elixir implementation conventions (env, `@spec` rules, quality gates, PR
  requirements): @elixir/AGENTS.md

Key rules carried over from AGENTS.md:

- Public `def` functions in `elixir/lib/` must have an adjacent `@spec`
  (`defp` and `@impl` callbacks are exempt). Validate with `mix specs.check`.
- Runtime config comes from `WORKFLOW.md` front matter via
  `SymphonyElixir.Config`; prefer config access over ad-hoc env reads.
- Workspace safety is critical: never run an agent turn cwd in the source repo;
  workspaces must stay under the configured workspace root.
- Keep changes narrowly scoped; follow existing module/style patterns.
- Main quality gate: `make all` (format check, lint, coverage, dialyzer).
