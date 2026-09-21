# Core Skills

## Goal

A plugin bundling project-agnostic catalog skills, installed via this repo's marketplace
instead of copied by hand. Each skill's body is identical for every installer; anything
project-specific it needs is read at runtime from one file the consuming project owns:
`.claude/project-context.md`.

## `.claude/project-context.md`

One file per project, holding every fact any installed skill from this plugin needs — not
one file per skill. A missing file, or a missing field within it, means "use the generic
default" — a skill never fails just because the project hasn't set this up.

A starter template ships with this plugin at
[`references/project-context-template.md`](references/project-context-template.md). Copy it
to `.claude/project-context.md` in the project and fill in only the fields that project needs.

## Skills

| Skill | Description |
|-------|-------------|
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [worktree](skills/worktree/) | Cut a fresh git worktree: branch, deps, env files, project house rules, then hand back the path |
| [build-it](skills/build-it/) | Implement the last grill-me alignment: cut a worktree, write plan docs if chosen, build, run gates, open the PR |
| [commit](skills/commit/) | Small, focused commits matching this project's own message convention, + push |

## Design record

`docs/plans/plugin-skills-rework/` in the [claude-2 catalog](https://github.com/script-development/claude)
tracks the decisions behind this plugin — why `.claude/project-context.md` exists, why skills
are bundled into one plugin, and the workflow for converting the next catalog skill.
