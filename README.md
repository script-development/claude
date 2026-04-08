# Claude Code Skills & Agents

Shared library of reusable Claude Code skills and agents. Clone this repo to browse, use, and contribute.

## Quick Start

### Using a skill

Copy or symlink a skill folder into your project's `.claude/skills/` directory:

```bash
# Copy
cp -r skills/commit /path/to/your/project/.claude/skills/

# Or symlink (stays in sync with this repo)
ln -s /path/to/this/repo/skills/commit /path/to/your/project/.claude/skills/commit
```

Then use it in Claude Code with `/commit` (or whatever the skill name is).

### Using an agent

Same idea, but with `.claude/agents/`:

```bash
cp agents/reviewer.md /path/to/your/project/.claude/agents/
```

Agents are invoked as subagents by Claude when their description matches the task.

### Bulk setup

To add all generic skills and agents to a project at once:

```bash
# Symlink all generic skills
for skill in babysit catchup commit newbranch next plan-feature pr research retro review-branch review-mcp-descriptions task-writer; do
  ln -sf /path/to/this/repo/skills/$skill /path/to/your/project/.claude/skills/$skill
done

# Symlink all generic agents
for agent in agent-auditor docs-auditor librarian qa reviewer; do
  ln -sf /path/to/this/repo/agents/$agent.md /path/to/your/project/.claude/agents/$agent.md
done
```

## Skills Catalog

### Generic Skills

Work in any project, no configuration needed.

| Skill | Description |
|-------|-------------|
| [babysit](skills/babysit/) | Watch a PR's CI, auto-fix failures, push until green |
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [commit](skills/commit/) | Small, focused commits with conventional messages + push |
| [newbranch](skills/newbranch/) | Create a new branch from the default branch |
| [next](skills/next/) | Continue through TASKS.md — find next task, execute, mark done |
| [plan-feature](skills/plan-feature/) | Interrogate the developer, then produce a feature plan |
| [pr](skills/pr/) | Create a pull request for the current branch |
| [research](skills/research/) | Research a topic, produce a filed report, build cumulative knowledge |
| [retro](skills/retro/) | Write retrospectives capturing what went wrong, why, and what changed |
| [review-branch](skills/review-branch/) | Code review all changes on current branch vs base |
| [review-mcp-descriptions](skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for discoverability |
| [task-writer](skills/task-writer/) | Break down features into structured TASKS.md with verification |

### Kendo PM Skills

For any project using [Kendo](https://kendo.dev) for issue tracking. Requires the Kendo CLI or MCP server.

| Skill | Description |
|-------|-------------|
| [board-sync](skills/board-sync/) | Sync kendo board with GitHub branch/PR status |
| [kendo-cli](skills/kendo-cli/) | Kendo CLI for issues, sprints, epics, time tracking |
| [kendo-mcp](skills/kendo-mcp/) | Kendo MCP server integration for issue management |
| [prepare-issue](skills/prepare-issue/) | Prepare a kendo issue: assign, branch, link, move to In Progress |

### Project-Specific Examples

These are specific to the kendo.dev codebase. Included as reference implementations showing how to write monitoring, setup, and release skills.

| Skill | Description |
|-------|-------------|
| [nightwatch-mcp](skills/nightwatch-mcp/) | Nightwatch error monitoring and triage |
| [release-cli](skills/release-cli/) | Release the kendo Go CLI via GoReleaser |
| [startup](skills/startup/) | Full project setup with worktree support |

## Agents Catalog

### Generic Agents

| Agent | Description |
|-------|-------------|
| [agent-auditor](agents/agent-auditor.md) | Audit agent definitions for quality and consistency |
| [docs-auditor](agents/docs-auditor.md) | Audit CLAUDE.md and docs against codebase for drift |
| [librarian](agents/librarian.md) | Scan other repos for shareable skills/agents, grade and recommend imports |
| [qa](agents/qa.md) | Diagnose CI failures or evaluate implementations against acceptance criteria |
| [reviewer](agents/reviewer.md) | Review PRs for code quality, architecture, and pattern consistency |

### Project-Specific Examples

| Agent | Description |
|-------|-------------|
| [plan-reviewer](agents/plan-reviewer.md) | Review feature plans for codebase convention violations (kendo-specific) |

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
