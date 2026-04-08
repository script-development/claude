# Contributing

## Adding a new skill

1. Copy the template:
   ```bash
   cp -r templates/skill-template skills/your-skill-name
   ```

2. Edit `skills/your-skill-name/SKILL.md`:
   - **Frontmatter**: `name` and `description` are required. The description is the most important part — it determines when Claude triggers the skill. See [best-practices.md](best-practices.md) for how to write a good one.
   - **Body**: Write clear instructions using imperative form. Explain the *why* behind each step. Include at least one example.
   - **Resources** (optional): Add `scripts/`, `references/`, or `assets/` folders if the skill needs bundled files.

3. Test it on 2-3 realistic prompts before submitting.

4. Update the Skills Catalog table in `README.md`.

5. Open a PR.

## Adding a new agent

1. Copy the template:
   ```bash
   cp templates/agent-template.md agents/your-agent-name.md
   ```

2. Edit `agents/your-agent-name.md`:
   - Fill in the frontmatter (`name` and `description` required)
   - Define scope (what it should and shouldn't do)
   - Write the instructions

3. Update the Agents Catalog table in `README.md`.

4. Open a PR.

## Updating existing skills/agents

- Update the content and bump the `updated:` date in frontmatter
- If the description changed, update the `README.md` catalog too
- If the skill references specific APIs or libraries, verify they're still current

## Naming conventions

- **Skills**: lowercase, hyphen-separated folder names (`review-pr`, `run-tests`, `deploy-staging`)
- **Agents**: lowercase, hyphen-separated filenames (`code-reviewer.md`, `security-auditor.md`)
- Keep names short, descriptive, and action-oriented

## Skill folder structure

Minimal:
```
my-skill/
└── SKILL.md
```

With bundled resources:
```
my-skill/
├── SKILL.md
├── scripts/       # Executable code
├── references/    # Docs loaded on demand
└── assets/        # Templates, icons, etc.
```
