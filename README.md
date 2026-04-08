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

| Skill | Description |
|-------|-------------|
| [babysit](skills/babysit/) | Watch a PR's CI, auto-fix failures, push until green |
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [commit](skills/commit/) | Small, focused commits with conventional messages + push |
| [next](skills/next/) | Continue through TASKS.md — find next task, execute, mark done |
| [plan-feature](skills/plan-feature/) | Interrogate the developer, then produce a feature plan |
| [review-branch](skills/review-branch/) | Code review all changes on current branch vs base |
| [review-mcp-descriptions](skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for discoverability |

## Agents Catalog

| Agent | Description |
|-------|-------------|
| *No agents yet - be the first to contribute!* | |

## Contributing

See [docs/contributing.md](docs/contributing.md) for how to add new skills and agents.

Use the templates in `templates/` as a starting point.
