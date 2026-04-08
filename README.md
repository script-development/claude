# Claude Code Skills & Agents

Shared library of Claude Code skills and agents for the team. Clone this repo to browse, use, and contribute skills.

## Quick Start

### Using a skill

1. Copy the skill folder into your project's `.claude/skills/` directory:
   ```bash
   cp -r skills/skill-name /path/to/your/project/.claude/skills/
   ```

2. Or symlink it:
   ```bash
   ln -s /path/to/this/repo/skills/skill-name /path/to/your/project/.claude/skills/skill-name
   ```

3. Use it in Claude Code with `/skill-name`

### Using an agent

1. Copy the agent file into your project's `.claude/agents/` directory:
   ```bash
   cp agents/agent-name.md /path/to/your/project/.claude/agents/
   ```

2. Or symlink it:
   ```bash
   ln -s /path/to/this/repo/agents/agent-name.md /path/to/your/project/.claude/agents/agent-name.md
   ```

## Skills Catalog

### Generic Skills

| Skill | Description |
|-------|-------------|
| [babysit](skills/babysit/) | Watch a PR's CI, auto-fix failures, push until green |
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [commit](skills/commit/) | Small, focused commits with conventional messages + push |
| [newbranch](skills/newbranch/) | Create a new branch from the default branch |
| [next](skills/next/) | Continue through TASKS.md — find next task, execute, mark done |
| [plan-feature](skills/plan-feature/) | Interrogate the developer, then produce a feature plan |
| [pr](skills/pr/) | Create a pull request for the current branch |
| [review-branch](skills/review-branch/) | Code review all changes on current branch vs base |
| [review-mcp-descriptions](skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for discoverability |
| [task-writer](skills/task-writer/) | Break down features into structured TASKS.md with verification |

### Kendo PM Skills

Skills for working with [Kendo](https://kendo.dev) project management. Usable in any project that uses Kendo for issue tracking.

| Skill | Description |
|-------|-------------|
| [board-sync](skills/board-sync/) | Sync kendo board with GitHub branch/PR status |
| [kendo-cli](skills/kendo-cli/) | Kendo CLI for issues, sprints, epics, time tracking |
| [kendo-mcp](skills/kendo-mcp/) | Kendo MCP server integration for issue management |
| [prepare-issue](skills/prepare-issue/) | Prepare a kendo issue: assign, branch, link, move to In Progress |

### Project-Specific Examples

These are specific to the kendo.dev codebase. They serve as examples of how to write monitoring, setup, and release skills.

| Skill | Description |
|-------|-------------|
| [nightwatch-mcp](skills/nightwatch-mcp/) | Nightwatch error monitoring and triage |
| [release-cli](skills/release-cli/) | Release the kendo Go CLI via GoReleaser |
| [startup](skills/startup/) | Full project setup with worktree support |

## Agents Catalog

| Agent | Description |
|-------|-------------|
| [plan-reviewer](agents/plan-reviewer.md) | Review feature plans for codebase convention violations (kendo-specific) |

## Contributing

See [docs/contributing.md](docs/contributing.md) for how to add new skills and agents.

Use the templates in `templates/` as a starting point.
