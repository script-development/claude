# Claude Code Skills & Agents

Shared library of reusable Claude Code skills and agents.

## Skills Catalog

### Generic Skills

Work in any project, no configuration needed.

| Skill | Description |
|-------|-------------|
| [babysit](skills/babysit/) | Superseded by [shepard](skills/shepard/). Watch a PR's CI, auto-fix failures, push until green |
| [build-it](skills/build-it/) | Implement the last grill-me alignment: cut a worktree, write plan docs if chosen, build, run gates, open the PR |
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [commit](skills/commit/) | Small, focused commits with conventional messages + push |
| [fix-bug](skills/fix-bug/) | End-to-end bug-fix workflow: reproduce, diagnose, fix, verify via bug-fix-verifier, with a visual-risk gate before /pr |
| [grill-me](skills/grill-me/) | Interview the developer through AskUserQuestion before any code is written; ends with docs-or-not and build-or-stop |
| [implement-plan](skills/implement-plan/) | Execute a feature plan end-to-end without TASKS.md; gated by /review-branch (both reviewers ≥ 7) |
| [memory-hygiene](skills/memory-hygiene/) | Audit the project memory store for stale, codified, duplicate entries; dry-run proposal, then sync worktree memory stores |
| [newbranch](skills/newbranch/) | Create a new branch from the default branch |
| [next](skills/next/) | Continue through TASKS.md — find next task, execute, mark done |
| [plan-feature](skills/plan-feature/) | Interrogate the developer, verify citations, gate the Security & Cost Surface, then produce PLAN.md + DECISIONS.md reviewed by plan-reviewer + surface-reviewer |
| [pr](skills/pr/) | Create a pull request for the current branch; gates on REVIEW_CLAUDE.md for plan branches and on BUG.md's verdict for bug branches |
| [research](skills/research/) | Research a topic, produce a filed report, build cumulative knowledge |
| [retro](skills/retro/) | Write retrospectives capturing what went wrong, why, and what changed |
| [review-branch](skills/review-branch/) | Two-agent review of the branch vs base: runtime-integrity-reviewer + precedent-reviewer in parallel, synthesized into REVIEW_CLAUDE.md |
| [review-mcp-descriptions](skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for discoverability |
| [shepard](skills/shepard/) | Drive one PR to green and answered: fix red CI, dispose every review finding, push once per cycle, arm a live watch |
| [sync-worktrees](skills/sync-worktrees/) | Copy gitignored .env* files and refresh dependencies from the primary worktree into every secondary worktree; optional safe fast-forward |
| [task-writer](skills/task-writer/) | Break down features into phased TASKS.md with verification and a self-administered coverage checklist |
| [wireframe](skills/wireframe/) | Generate structured WIREFRAMES.md with ASCII layouts, design tokens, and interaction specs; self-gated by wireframe-reviewer |
| [worktree](skills/worktree/) | Cut a fresh git worktree: branch, deps, env files, per-repo house rules, then hand back the path |

### Stack-Specific Skills

Generic across any project on a given stack, but assume that stack is in use.

| Skill | Stack | Description |
|-------|-------|-------------|
| [nightwatch-mcp](skills/nightwatch-mcp/) | Nightwatch MCP | Error and performance monitoring, exception triage |
| [release-cli](skills/release-cli/) | Go + GoReleaser | Tag and release a Go CLI via GoReleaser on tag push |
| [startup](skills/startup/) | Laravel + Vue + MinIO | Full project setup: Docker services, .env files, then parallel backend/frontend/MCP setup, with worktree support |

### Kendo PM Skills

For any project using [Kendo](https://kendo.dev) for issue tracking. Requires the Kendo CLI or MCP server.

| Skill | Description |
|-------|-------------|
| [board-sync](skills/board-sync/) | Sync kendo board with GitHub branch/PR status |
| [kendo-cli](skills/kendo-cli/) | Kendo CLI for issues, sprints, epics, time tracking |
| [kendo-mcp](skills/kendo-mcp/) | Kendo MCP server integration for issue management |
| [lint-issues](skills/lint-issues/) | Audit every To Do / In Progress issue against the issue-writing standard via parallel issue-linter agents; post a summary on an audit issue |
| [prepare-issue](skills/prepare-issue/) | Prepare a kendo issue: assign, branch, link, move to In Progress |
| [triage-reports](skills/triage-reports/) | Walk pending Kendo reports one-by-one; promote, combine, park, or dismiss with a logged reason |

## Agents Catalog

### Generic Agents

| Agent | Description |
|-------|-------------|
| [agent-auditor](agents/agent-auditor.md) | Audit agent definitions for quality and consistency |
| [bug-fix-verifier](agents/bug-fix-verifier.md) | Verify a bug fix actually resolves BUG.md's defect; gates `/fix-bug` before PR |
| [docs-auditor](agents/docs-auditor.md) | Audit CLAUDE.md and docs against codebase for drift |
| [librarian](agents/librarian.md) | Scan other repos for shareable skills/agents, grade and recommend imports |
| [precedent-reviewer](agents/precedent-reviewer.md) | Review a branch against written standards, sibling implementations, and its own plan prose; PR-time pair with runtime-integrity-reviewer |
| [qa](agents/qa.md) | Diagnose CI failures or evaluate implementations against acceptance criteria |
| [reviewer](agents/reviewer.md) | Review PRs for code quality, architecture, and pattern consistency |
| [runtime-integrity-reviewer](agents/runtime-integrity-reviewer.md) | Review a branch for transaction, concurrency, lifecycle, scaling, and silent-failure defects; PR-time pair with precedent-reviewer |
| [surface-reviewer](agents/surface-reviewer.md) | Audit a plan's Security & Cost Surface section against six question-shaped rows; plan-time, runs beside plan-reviewer |
| [wireframe-reviewer](agents/wireframe-reviewer.md) | Verify WIREFRAMES.md completeness, token validity, and plan coverage |

### Stack-Specific Agents

| Agent | Stack | Description |
|-------|-------|-------------|
| [issue-linter](agents/issue-linter.md) | Kendo MCP | Grade one issue against `kendo-mcp`'s issue-templates.md; post suggested rewrites on the audit issue, never edit the target |
| [plan-reviewer](agents/plan-reviewer.md) | Laravel + Vue | Review feature plans for codebase convention violations against arch tests and CLAUDE.md |

## Maintaining This Repo

Maintenance happens from the private **mission-control** repo, which adds this repo and the consumer repos as submodules under `repos/`. From there, the **librarian** agent walks `repos/*/` looking for new skills and agents worth promoting into this catalog:

```
> Check my repos for new skills
```

It grades each candidate on quality and genericness, and recommends what to import.

## Contributing

See [docs/contributing.md](docs/contributing.md) for how to add new skills and agents.

Use the templates in `templates/` as a starting point:
- `templates/skill-template/` — skeleton for a new skill
- `templates/agent-template.md` — skeleton for a new agent
