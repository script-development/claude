# Claude Code Skills & Agents Repository

This repo is a Claude Code plugin marketplace. It exposes a single plugin (`core`) via `.claude-plugin/marketplace.json`.

## Repository Structure

- `.claude-plugin/marketplace.json` - Marketplace manifest
- `plugins/core/.claude-plugin/plugin.json` - Plugin manifest
- `plugins/core/skills/<name>/SKILL.md` - Skill definitions (folder name = skill identifier)
- `plugins/core/agents/<name>.md` - Agent definitions (flat markdown files)
- `templates/` - Templates for creating new skills/agents
- `docs/` - Contributing guide and best practices

## When working in this repo

- **Finding skills**: Search `plugins/core/skills/` by folder name or grep frontmatter
- **Creating a new skill**: Copy `templates/skill-template/SKILL.md` into a new folder under `plugins/core/skills/`, rename the folder to the skill name
- **Creating a new agent**: Copy `templates/agent-template.md` into `plugins/core/agents/` with an appropriate name
- **After adding/removing skills or agents**: Update the catalog tables in `README.md`
- **Quality checks**: Flag skills with outdated references, missing metadata, or duplicate functionality
