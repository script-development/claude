# Claude Code Skills & Agents

A Claude Code [plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) of reusable skills and agents.

## Quick Start

Add the marketplace once, then install the plugin in any repo:

```text
/plugin marketplace add script-development/claude
/plugin install core@claude-skills
```

Skills become available as `/core:commit`, `/core:plan-feature`, etc. Agents are auto-discovered as subagents.

To update later:

```text
/plugin marketplace update claude-skills
```

### Local development

If you're hacking on this repo locally:

```text
/plugin marketplace add /path/to/this/repo
```

## Skills

| Skill | Description |
|-------|-------------|
| [babysit](plugins/core/skills/babysit/) | Watch a PR's CI, auto-fix failures, push until green |
| [board-sync](plugins/core/skills/board-sync/) | Sync kendo board with GitHub branch/PR status |
| [catchup](plugins/core/skills/catchup/) | Load branch context, show progress, sync with base branch |
| [commit](plugins/core/skills/commit/) | Small, focused commits with conventional messages + push |
| [fix-bug](plugins/core/skills/fix-bug/) | End-to-end bug-fix workflow: reproduce, diagnose, fix, verify via bug-fix-verifier |
| [implement-plan](plugins/core/skills/implement-plan/) | Execute a feature plan end-to-end without TASKS.md, gated by acceptance-reviewer |
| [kendo-cli](plugins/core/skills/kendo-cli/) | Kendo CLI for issues, sprints, epics, time tracking |
| [kendo-mcp](plugins/core/skills/kendo-mcp/) | Kendo MCP server integration for issue management |
| [newbranch](plugins/core/skills/newbranch/) | Create a new branch from the default branch |
| [next](plugins/core/skills/next/) | Continue through TASKS.md — find next task, execute, mark done |
| [nightwatch-mcp](plugins/core/skills/nightwatch-mcp/) | Nightwatch error monitoring and triage |
| [plan-feature](plugins/core/skills/plan-feature/) | Interrogate the developer, then produce PLAN.md + DECISIONS.md |
| [pr](plugins/core/skills/pr/) | Create a pull request for the current branch |
| [prepare-issue](plugins/core/skills/prepare-issue/) | Prepare a kendo issue: assign, branch, link, move to In Progress |
| [release-cli](plugins/core/skills/release-cli/) | Release the kendo Go CLI via GoReleaser |
| [research](plugins/core/skills/research/) | Research a topic, produce a filed report, build cumulative knowledge |
| [retro](plugins/core/skills/retro/) | Write retrospectives capturing what went wrong, why, and what changed |
| [review-branch](plugins/core/skills/review-branch/) | Code review all changes on current branch vs base |
| [review-mcp-descriptions](plugins/core/skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for discoverability |
| [startup](plugins/core/skills/startup/) | Full project setup with worktree support |
| [task-writer](plugins/core/skills/task-writer/) | Break down features into structured TASKS.md with verification |
| [wireframe](plugins/core/skills/wireframe/) | Generate structured WIREFRAMES.md with ASCII layouts, design tokens, and interaction specs |

## Agents

| Agent | Description |
|-------|-------------|
| [acceptance-reviewer](plugins/core/agents/acceptance-reviewer.md) | Verify implementation satisfies plan's acceptance criteria and wireframe specs |
| [agent-auditor](plugins/core/agents/agent-auditor.md) | Audit agent definitions for quality and consistency |
| [bug-fix-verifier](plugins/core/agents/bug-fix-verifier.md) | Verify a bug fix actually resolves BUG.md's defect; gates `/fix-bug` before PR |
| [docs-auditor](plugins/core/agents/docs-auditor.md) | Audit CLAUDE.md and docs against codebase for drift |
| [efficiency-hunter](plugins/core/agents/efficiency-hunter.md) | Hunt N+1 queries, missed concurrency, hot-path bloat in branch diffs |
| [librarian](plugins/core/agents/librarian.md) | Scan other repos for shareable skills/agents, grade and recommend imports |
| [plan-reviewer](plugins/core/agents/plan-reviewer.md) | Review feature plans for codebase convention violations |
| [qa](plugins/core/agents/qa.md) | Diagnose CI failures or evaluate implementations against acceptance criteria |
| [reviewer](plugins/core/agents/reviewer.md) | Review PRs for code quality, architecture, and pattern consistency |
| [silent-failure-hunter](plugins/core/agents/silent-failure-hunter.md) | Hunt empty catches, swallowed errors, missing user feedback in branch diffs |
| [simplicity-reviewer](plugins/core/agents/simplicity-reviewer.md) | Verify the implementation is the simplest shape that meets the plan |
| [task-alignment-reviewer](plugins/core/agents/task-alignment-reviewer.md) | Verify TASKS.md fully covers PLAN.md — criteria, wireframes, scope |
| [wireframe-reviewer](plugins/core/agents/wireframe-reviewer.md) | Verify WIREFRAMES.md completeness, token validity, and plan coverage |

## Maintaining This Repo

Use the **librarian** agent to scan your other repos for new skills and agents worth sharing:

```
> Check my repos for new skills
```

It scans `~/Code/*/` for `.claude/skills/` and `.claude/agents/`, grades each candidate on quality and genericness, and recommends what to import.

## Contributing

See [docs/contributing.md](docs/contributing.md) for how to add new skills and agents.

Use the templates in `templates/` as a starting point:
- `templates/skill-template/` — skeleton for a new skill
- `templates/agent-template.md` — skeleton for a new agent

After adding a skill or agent, drop it into `plugins/core/skills/` or `plugins/core/agents/` and update the catalog tables above.
