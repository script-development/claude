---
name: kendo-cli
description: |
  Kendo CLI tool for managing issues, projects, sprints, epics, reports, and time tracking
  directly from the terminal. Use this skill whenever interacting with kendo issues,
  checking board status, creating or updating issues, searching across projects,
  logging time, managing sprints and epics, or triaging reports (bug reports, feedback) —
  especially when the MCP server is unavailable or when a quick CLI command is simpler
  than an MCP tool call. Also use when the user mentions "kendo cli", "kendo command",
  or wants to run kendo operations via the terminal.
---

# Kendo CLI

Manage kendo issues, projects, sprints, epics, reports, and time tracking via the `kendo` CLI.
The CLI communicates with the kendo REST API using OAuth Device Flow authentication.

## Installation

### Quick install (Linux / macOS)

```bash
curl -sSL https://central.kendo.dev/cli/install.sh | sh
```

The script detects OS/arch, downloads the correct binary, verifies checksums, and installs
to `~/.local/bin/kendo` (or `/usr/local/bin/kendo` with sudo).

### Update

```bash
kendo update           # Download and install latest version
kendo update --check   # Check for updates without installing
```

### Verify

```bash
kendo version
```

## Authentication

After installing, the user must log in interactively (Claude cannot do this step —
it requires stdin for the OAuth device flow):

```bash
kendo auth login
```

This will prompt for the tenant URL (e.g., `yourteam.kendo.dev`), then open a browser
for authorization. Tokens are stored in `~/.config/kendo/tokens.json`.

Check auth status or log out:
```bash
kendo auth status
kendo auth logout
```

## Active Project

Most commands require an active project. Set it once and it persists across sessions:

```bash
kendo project select <PROJECT_CODE>
```

The active project is stored in `~/.config/kendo/config.yaml`.

## Global Flags

These flags work on any command:

- `--json` — Output as JSON instead of table (use when you need to parse/extract specific fields)
- `--project <CODE>` — Override the active project for this single command

The `--project` flag is useful for quick cross-project lookups without switching the active project.

## Output Modes

- **Table** (default): Human-readable aligned columns with ANSI colors
- **JSON** (`--json`): Machine-readable, ideal for parsing in scripts

Table output is usually fine for displaying results to the user. Use `--json` only when you
need to programmatically extract specific fields (e.g., getting an issue ID to use in a follow-up
command). Always append `2>&1` to capture errors alongside output.

## Commands That Don't Need an Active Project

These commands work without `kendo project select` — they operate across all accessible projects:

- `kendo issue my` — issues assigned to current user across all projects
- `kendo search` — global search across all projects
- `kendo team list` — all teams

Don't waste time selecting a project before running these.

## Commands Reference

### Projects

```bash
kendo project list                    # List all projects (ID, code, name, issue count)
kendo project select <CODE>           # Set active project
kendo project view                    # View active project details
```

### Issues

```bash
kendo issue list                      # List all issues in active project
kendo issue list --lane "To Do"       # Filter by lane name or ID
kendo issue list --sprint active      # Filter by sprint ID or "active"
kendo issue list --type bug           # Filter by type
kendo issue list --priority high      # Filter by priority
kendo issue list --label bug          # Filter by label name or ID
kendo issue list --assignee "Jane Doe"  # Filter by user ID or full name
kendo issue list --epic 9             # Filter by epic ID or title
kendo issue view <REF>                # View issue by key (e.g. PROJ-0255) or ID (e.g. 390)
kendo issue my                        # List issues assigned to current user
kendo issue search <QUERY>            # Search issues by text (title, description, key); takes the same filter flags
kendo issue count --group-by lane     # Count issues per group, plus the total; takes the same filter flags
kendo issue create --title "Title"    # Create issue (see flags below)
kendo issue update <REF> [flags]      # Update issue fields
kendo issue move <REF> <LANE_ID>      # Move issue to a lane
kendo issue comment <REF> -m "text"   # Add comment to issue
kendo issue comment <REF> -m "text" --reply-to 41  # Reply to top-level comment 41
kendo issue comments <REF>            # Read the comments on an issue
kendo issue update-comment <REF> <COMMENT_ID> --content "text"  # Edit a comment
kendo issue delete-comment <REF> <COMMENT_ID>  # Delete a comment (destructive!)
kendo issue delete <REF>              # Delete issue (destructive!)
kendo issue link-branch <REF>         # Link current git branch to issue
```

Filters can be combined for precise queries:
```bash
kendo issue list --sprint active --lane "In Progress"       # What's being worked on right now
kendo issue list --sprint active --type bug --priority high  # Urgent bugs in current sprint
kendo issue list --sprint active --lane "In Review"          # What's waiting for review
```

Every filter flag is repeatable (any of the values matches) and has an `--exclude-*` twin:
```bash
kendo issue list --lane "To Do" --lane "In Progress"         # Issues in either lane
kendo issue list --exclude-lane Done --exclude-type task     # Everything except done issues and tasks
kendo issue list --sprint active --assignee none             # Unassigned work in the current sprint
kendo issue count --group-by assignee --sprint active --exclude-lane Done  # Open sprint work per person
kendo issue count --group-by label --json                    # { total, groups: [{ key, label, count }] }
```

- `none` is a value for `--assignee`, `--epic`, `--sprint` and their `--exclude-*` forms:
  unassigned, no epic, backlog.
- Excluding a person, epic or sprint keeps the issues that have none, unless `none` is excluded
  too. A value both included and excluded is excluded.
- A name that matches nothing, or that two members or two epics share, fails before any issue is
  fetched.
- `--group-by` is required: `lane`, `assignee`, `sprint`, `epic`, `priority`, `type` or `label`.
  Grouped by label, the rows can sum above the total.
- `issue list` filters client-side over the full issue walk. `issue search` and `issue count`
  filter on the server (search is capped at `--limit`, max 500).

**Issue create flags:**

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--title` | **yes** | — | Issue title |
| `--description` | **yes** | — | Issue description (markdown) |
| `--type` | no | `feature` | `feature` or `bug` |
| `--priority` | no | `medium` | `highest`, `high`, `medium`, `low`, `lowest` |
| `--lane` | no | first lane | Lane ID |
| `--sprint` | no | — | Sprint ID |
| `--assignee` | no | — | User ID |

**Issue update flags** (all optional — only changed fields are updated):

| Flag | Type | Description |
|------|------|-------------|
| `--title` | string | Issue title |
| `--description` | string | Issue description (markdown) |
| `--type` | string | `feature` or `bug` |
| `--priority` | string | `highest`, `high`, `medium`, `low`, `lowest` |
| `--lane` | int | Lane ID |
| `--sprint` | int | Sprint ID |
| `--assignee` | int | User ID |

### Search (Cross-Project)

```bash
kendo search <QUERY>                  # Search across all projects
kendo search <QUERY> --project-id 1   # Filter by project
kendo search <QUERY> --type bug       # Filter by type (feature, bug, task)
kendo search <QUERY> --priority high  # Filter by priority
kendo search <QUERY> --lane 2         # Filter by lane ID
kendo search <QUERY> --sprint 12      # Filter by sprint ID
kendo search <QUERY> --epic 9         # Filter by epic ID
kendo search <QUERY> --assignee 1     # Filter by user ID
kendo search <QUERY> --limit 50       # Max results (1-500, default 25)
```

`kendo search` takes one ID per flag and has no `--exclude-*` forms or `none`. For several values,
exclusions or counts, select the project and use `kendo issue search` / `kendo issue count`.

### Board

```bash
kendo board                           # Visual kanban board for active sprint
kendo board --rows 10                 # Show more rows per column (default: 6)
kendo board --rows 0                  # Show all issues (no truncation)
kendo board --json                    # Structured JSON with all issues per lane
```

The board shows lanes as columns with issue counts. Issues assigned to you are marked
with `*` and sorted to the top. Columns truncate at 6 rows with `...+N` overflow.

### Sprints

```bash
kendo sprint list                     # List all sprints
kendo sprint active                   # Show current active sprint
kendo sprint todo                     # To Do issues in active sprint (sorted by priority)
```

### Epics

```bash
kendo epic list                       # Epics with status, issue and Done when progress
kendo epic view 9                     # Goal, Done when (wish ids, ticks, issues), What done looks like, assignee, status
kendo epic issues <epic>              # List issues in epic (by ID or name)
kendo epic issues "My Epic"           # By name (case-insensitive)
kendo epic issues 9                   # By ID
kendo epic create --title "Title"     # Create epic (defaults: color blue, order 0)
kendo epic create --title "T" --start 2026-03-17 --end 2026-04-01 --color red
kendo epic create --title "Checkout" --goal "Pay in one tap" --assignee "Jane Doe"
kendo epic update 9 --wish "The customer can pay [PROJ-0011, PROJ-0012]" --wish "The customer gets a receipt"
kendo epic update 9 --check "Browser look: checkout on desktop and phone"  # Set What done looks like
kendo epic update 9 --wish ""         # Clear Done when
kendo epic tick 9 21                  # Tick wish 21 (epic untick 9 21 undoes it)
kendo epic comments 9                 # Read the comments on an epic
kendo epic comment 9 -m "text"        # Comment on an epic (--reply-to <id> replies)
kendo epic attachments 9              # List attachments on an epic
kendo epic attach 9 ./roadmap.pdf     # Upload a file to an epic
kendo epic download 9 7               # Download attachment 7
kendo epic delete 9                   # Delete epic and its comments; issues stay (destructive!)
```

Needs CLI 0.16.0 or later for `view`, `tick`, `untick`, the epic comment commands and the
`--goal`, `--assignee`, `--wish` and `--check` flags: check with `kendo version`, then `kendo update`.

- `epic create` and `epic update` take `--goal`, `--assignee` (a user ID, a full name, or `none`),
  `--color` (`grey`, `green`, `blue`, `red`, `purple`, `yellow`, `orange`, `teal`, `pink`,
  `indigo`, or `0`-`9`) and the two lists. `epic update` also takes `--title`, `--description`
  and `--start`/`--end`, passed together; an empty value clears them.
- `--wish` sets Done when and `--check` sets What done looks like: repeat the flag once per line,
  in order. The lines you pass replace the whole list. A line with the same text as a stored one
  keeps that item, so a kept wish keeps its tick and its issues. `--wish ""` or `--check ""` alone
  clears that list; a flag you leave out leaves its list as it is.
- On `epic update`, a trailing bracket of issue keys or IDs links a wish to issues of the epic;
  `[]` unlinks them. `epic create` refuses a bracket: attach the issues first with
  `kendo issue update <REF> --epic <EPIC_ID>`.
- `epic update` sends only the flags you pass. `epic view` prints each wish's ID for `epic tick`
  and `epic untick`. A save never ticks a wish, and an epic's status is derived: with wishes it is
  Closed once every wish is ticked; without, when it has issues and all are in the last lane.
- `epic comments`, `comment`, `update-comment` and `delete-comment` work like their `issue`
  counterparts, with the epic ID in place of the issue key.

### Reports

```bash
kendo report list                                          # List all reports in active project
kendo report create --title "T" --description "D"          # Create a new report
kendo report promote <id> [id...] --title "T" --description "D"  # Promote reports to issue
kendo report promote 1 2 --title "Bug fix" --description "..." --priority high --type bug
kendo report dismiss <id>                                  # Dismiss report (soft-archive)
kendo report delete <id>                                   # Delete report permanently
```

**Report promote flags** (all optional except --title and --description):

| Flag | Type | Description |
|------|------|-------------|
| `--title` | string | Title for the new issue (required) |
| `--description` | string | Description for the new issue (required) |
| `--lane` | int | Lane ID (default: first lane) |
| `--priority` | string | `highest`, `high`, `medium`, `low`, `lowest` |
| `--type` | string | `feature` or `bug` |
| `--assignee` | int | User ID |
| `--sprint` | int | Sprint ID |
| `--epic` | int | Epic ID |
| `--estimate` | int | Estimated time in minutes |

### Lanes

```bash
kendo lane list                       # List board lanes (ID, title, order)
```

### Teams

```bash
kendo team list                       # List teams and member counts
```

### Time Tracking

```bash
kendo time log <REF> --minutes 60                        # Log 60 minutes on issue
kendo time log <REF> --minutes 30 --notes "Code review"  # With description
kendo time log <REF> --minutes 45 --date 2026-03-16      # Specific date
kendo time list                                           # This week's time entries
kendo time list --from 2026-03-01 --to 2026-03-31        # Custom date range
kendo time list <REF>                                     # All time logged on a specific issue
```

`time list` defaults to the current week (Monday through today). Pass `--from` and `--to`
(YYYY-MM-DD) for a custom range. Pass an issue ref to see all time logged on that issue
regardless of date. Output includes a total time summary (hours:minutes).

### Update

```bash
kendo update                          # Download and install latest version
kendo update --check                  # Check for updates without installing
```

### Utility

```bash
kendo version                         # Show CLI version
kendo commands --json                 # Machine-readable command manifest
kendo completion bash                 # Generate bash completions
kendo completion zsh                  # Generate zsh completions
kendo completion fish                 # Generate fish completions
kendo completion powershell           # Generate powershell completions
```

## Common Workflows

### Find and view an issue
```bash
kendo issue view PROJ-0255
# or search first:
kendo search "translation error" --json
```

### Create a bug report
```bash
kendo issue create \
  --title "Button not responding on mobile" \
  --type bug \
  --priority high \
  --description "The submit button on the login form does not respond to tap events on iOS Safari."
```

### Move an issue through the board
```bash
# Check available lanes
kendo lane list
# Move to In Progress (lane 2)
kendo issue move PROJ-0255 2
```

### Link current branch to an issue
```bash
# Auto-detects current git branch via `git rev-parse`
kendo issue link-branch PROJ-0255
```

### Daily standup overview
```bash
kendo board                           # Full sprint board at a glance (your issues marked with *)
kendo issue my                        # What's assigned to me across all projects
kendo sprint todo                     # What's in the sprint backlog (sorted by priority)
```

### Board overview for current sprint
```bash
kendo board                           # Visual kanban board — all lanes, counts, your issues on top
kendo board --json                    # Full board data for programmatic use
```

### Quick cross-project lookup
```bash
# Check another project without switching active project
kendo issue list --project OTHER --type bug
kendo search "deploy" --project-id 8
```

### Triage incoming reports
```bash
kendo report list                                       # See what's pending
kendo report promote 5 --title "Fix login bug" --description "..." --type bug --priority high
kendo report dismiss 3                                  # Not actionable
```

### Time tracking
```bash
kendo time log PROJ-0255 --minutes 90 --notes "Refactored adapter store"
kendo time list                                         # This week's entries
kendo time list --from 2026-03-01 --to 2026-03-31      # Monthly summary
kendo time list PROJ-0255                               # All time on one issue
```

## Tips for Claude Code Usage

- **Table vs JSON**: Table output is readable enough for displaying to users. Only use `--json`
  when you need to programmatically extract a specific field (e.g., getting a sprint ID to use
  in a follow-up filter command).
- **Error capture**: Always append `2>&1` so error messages are visible in the output.
- **Command discovery**: Run `kendo commands --json` to get a machine-readable list of all
  commands and their flags — useful if you're unsure about a command's exact syntax.
- **Board command**: Use `kendo board` for a quick sprint overview instead of running multiple
  `kendo issue list` commands with different `--lane` filters.
- **No project needed**: `kendo issue my`, `kendo search`, and `kendo team list` work without
  an active project — don't waste a step on `kendo project select` before using them.

## Relation to MCP

The CLI and MCP server access the same backend API. Key differences:

| | CLI | MCP |
|-|-----|-----|
| **Invocation** | `Bash` tool — single command | MCP tool call — structured params |
| **Dependencies** | `kendo` binary + auth token | MCP server running |
| **Output** | Table or `--json` | Structured JSON |
| **Best for** | Quick lookups, scripting, batch ops | Programmatic integration, resource URIs |

Use whichever is available. If both are, the CLI is often simpler for quick reads (one
bash command vs. MCP tool invocation), while MCP is better for writes that benefit from
structured parameter validation.

## Issue References

Issues can be referenced by **key** (e.g., `PROJ-0255`) or **numeric ID** (e.g., `390`).
The backend accepts both formats. Prefer keys for readability.

## User Stories

When creating issues, you **must** write the description against the canonical templates in
[`kendo-mcp`'s `references/issue-templates.md`](../kendo-mcp/references/issue-templates.md) —
Feature (User Story / Context / Acceptance Criteria / Scope / Testing) or Bug (Problem /
Cause-or-repro / Acceptance Criteria / Scope / Testing), in English. Don't improvise a structure
or stop at the `As a [role]…` opening line.
