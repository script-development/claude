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
kendo issue view <REF>                # View issue by key (e.g. PROJ-0255) or ID (e.g. 390)
kendo issue my                        # List issues assigned to current user
kendo issue search <QUERY>            # Search issues by text (title, description, key)
kendo issue create --title "Title"    # Create issue (see flags below)
kendo issue update <REF> [flags]      # Update issue fields
kendo issue move <REF> <LANE_ID>      # Move issue to a lane
kendo issue comment <REF> -m "text"   # Add comment to issue
kendo issue delete <REF>              # Delete issue (destructive!)
kendo issue link-branch <REF>         # Link current git branch to issue
```

Filters can be combined for precise queries:
```bash
kendo issue list --sprint active --lane "In Progress"       # What's being worked on right now
kendo issue list --sprint active --type bug --priority high  # Urgent bugs in current sprint
kendo issue list --sprint active --lane "In Review"          # What's waiting for review
```

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
kendo search <QUERY> --type bug       # Filter by type
kendo search <QUERY> --priority high  # Filter by priority
kendo search <QUERY> --lane 2         # Filter by lane
kendo search <QUERY> --sprint 12      # Filter by sprint
kendo search <QUERY> --epic 9         # Filter by epic
kendo search <QUERY> --assignee 1     # Filter by assignee
kendo search <QUERY> --limit 50       # Max results (1-100, default 25)
```

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
kendo epic list                       # List epics with issue counts and dates
kendo epic issues <epic>              # List issues in epic (by ID or name)
kendo epic issues "My Epic"           # By name (case-insensitive)
kendo epic issues 9                   # By ID
kendo epic create --title "Title"     # Create epic (defaults: color blue, order 0)
kendo epic create --title "T" --start 2026-03-17 --end 2026-04-01 --color red
```

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

When creating issues, write descriptions in Dutch following the user story format:
"Als [rol] wil ik [functionaliteit] zodat [doel]". See the kendo-mcp skill's
`references/user-story-format.md` for the full template.
