# Claude Code Skills & Agents Repository

This is a shared library of Claude Code skills and agents. Other repos consume it as a git submodule and symlink the skills/agents they need into their own `.claude/` directory.

## Repository Structure

- `skills/<name>/SKILL.md` - Skill definitions (folder name = skill identifier)
- `agents/<name>.md` - Agent definitions (flat markdown files)
- `templates/` - Templates for creating new skills/agents
- `docs/` - Contributing guide and best practices

## When working in this repo

- **Finding skills**: Search `skills/` by folder name or grep frontmatter
- **Creating a new skill**: Copy `templates/skill-template/SKILL.md` into a new folder under `skills/`, rename the folder to the skill name
- **Creating a new agent**: Copy `templates/agent-template.md` into `agents/` with an appropriate name
- **After adding/removing skills or agents**: Update the catalog tables in `README.md`
- **Quality checks**: Flag skills with outdated references, missing metadata, or duplicate functionality
