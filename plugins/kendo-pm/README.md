# Kendo PM

## Goal

A plugin bundling Kendo project-management skills, installed via this repo's marketplace
instead of copied by hand. For any project using [Kendo](https://kendo.dev) for issue
tracking; requires the Kendo MCP server (see `kendo-mcp`'s own setup reference).

Unlike `core-skills`, this plugin is vendor-specific by design — every skill here assumes a
Kendo tenant, so a consumer without one has no reason to install it.

## `.claude/project-context.md`

This plugin has no template of its own — `core-skills` already owns the canonical one
([`references/project-context-template.md`](../core-skills/references/project-context-template.md)),
and a project only needs to maintain one file regardless of which plugins it installs. A skill
below that reads a field states which one, in backticks; that always means "read this field from
`.claude/project-context.md`, falling back to the stated default when the field or the file
itself is absent" — see `core-skills`' own README for the fuller degrade-not-fail explanation.
Reading a field this way is not a dependency on `core-skills` being installed: the file is a
plain project-owned document, and a `kendo-pm`-only consumer can set the field without ever
installing `core-skills`. `kendo-mcp` and `kendo-cli` read nothing from it — both discover their
project id at runtime instead. `triage-reports` reads `issue_tracker_project_id`. Add a
project-context mechanism of this plugin's own only if a future skill needs a fact
`core-skills`' template can't already cover.

## Skills

| Skill | Description |
|-------|-------------|
| [kendo-cli](skills/kendo-cli/) | Kendo CLI for issues, sprints, epics, time tracking — from the terminal, no MCP server required |
| [kendo-mcp](skills/kendo-mcp/) | Kendo MCP server integration for issue management: issues, sprints, epics, time tracking, reports, attachments |
| [triage-reports](skills/triage-reports/) | Walk pending Kendo reports one-by-one; promote, combine, park, or dismiss with a logged reason |

## Design record

`docs/plans/plugin-skills-rework/` in the [claude-2 catalog](https://github.com/script-development/claude)
tracks the decisions behind the `core-skills` conversion this plugin's own workflow reuses —
why `.claude/project-context.md` exists, and the per-skill conversion workflow.
