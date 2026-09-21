# Kendo PM

## Goal

A plugin bundling Kendo project-management skills, installed via this repo's marketplace
instead of copied by hand. For any project using [Kendo](https://kendo.dev) for issue
tracking; requires the Kendo MCP server (see `kendo-mcp`'s own setup reference).

Unlike `core-skills`, this plugin is vendor-specific by design — every skill here assumes a
Kendo tenant, so a consumer without one has no reason to install it.

## `.claude/project-context.md`

`kendo-mcp` itself reads nothing from `.claude/project-context.md` — it discovers its
project id at runtime (`kendo://projects`) rather than hardcoding one, so it needs no
project-specific override. A later skill in this plugin that does need a project-scoped
default should reuse `core-skills`' `issue_tracker_project_id` field (see that plugin's
[`references/project-context-template.md`](../core-skills/references/project-context-template.md))
rather than inventing a second field for the same fact — add a project-context mechanism of
this plugin's own only if a skill needs a fact `core-skills`' template can't already cover.

## Skills

| Skill | Description |
|-------|-------------|
| [kendo-mcp](skills/kendo-mcp/) | Kendo MCP server integration for issue management: issues, sprints, epics, time tracking, reports, attachments |

## Design record

`docs/plans/plugin-skills-rework/` in the [claude-2 catalog](https://github.com/script-development/claude)
tracks the decisions behind the `core-skills` conversion this plugin's own workflow reuses —
why `.claude/project-context.md` exists, and the per-skill conversion workflow.
