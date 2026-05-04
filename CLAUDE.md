# Claude Code Skills & Agents Repository

This is a shared library of Claude Code skills and agents. Each shared skill lives here **and** in every consumer that has adopted it, with identical content — this catalog is the canonical baseline.

This is **not** a one-way source of truth. Changes can originate in any consumer (where the skill is used in real work) and propagate outward; when a shared skill is updated anywhere, the catalog and every other mirroring consumer must be updated to match.

Skills are **not** consumed via symlinks. Consumers hold their own copies. When a project-specific skill is lifted into this catalog, it is **generalised** first — abstracting away project-specific config — so the catalog version is typically not identical to the project-specific original.

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
- **Updating a shared skill**: after merging here, propagate the change to every consumer that mirrors this skill (today: manual). Drift between catalog and consumers is a bug.
