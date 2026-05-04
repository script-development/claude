---
name: kendo-mcp
description: |
  MCP integration for kendo project management. Use when creating, updating, moving, or
  searching issues via MCP tools. Also use when writing Dutch user stories, logging time,
  managing epics, linking branches to issues, or triaging reports (bug reports, feedback).
  Provides access to projects, issues, lanes, sprints, epics, reports, and teams through
  MCP resources and tools.
---

# Kendo MCP

Manage issues using the Kendo MCP server. Works with any project hosted on your Kendo tenant.

## Setup

Before using these tools, ensure the Kendo MCP server is configured. See
[references/setup.md](references/setup.md) for installation instructions.

## Discovering Your Project

Before using project-scoped resources, find your project ID:

```
Read kendo://projects → find your project's ID and code
```

Use this ID for all `project_id` parameters and resource URIs below.

## MCP Resources (Read-Only)

| URI | Description |
|-----|-------------|
| `kendo://projects` | List all accessible projects |
| `kendo://projects/{id}/issues` | List issues in a project |
| `kendo://projects/{id}/lanes` | List board lanes |
| `kendo://projects/{id}/sprints` | List sprints (status: 0=Planned, 1=Active, 2=Completed) |
| `kendo://projects/{id}/epics` | List epics for a project |
| `kendo://projects/{id}/members` | List project members (for assignee_id) |
| `kendo://projects/{id}/github-repos` | List linked GitHub repositories |
| `kendo://issues/{id}` | Get a single issue with details |
| `kendo://teams` | List teams and members |

## MCP Tools

### Issues

| Tool | Purpose |
|------|---------|
| `mcp__kendo.dev__create-issue-tool` | Create new issue |
| `mcp__kendo.dev__update-issue-tool` | Update issue fields (including lane changes via `lane_id`) |
| `mcp__kendo.dev__add-comment-tool` | Add comment to issue (max 2000 chars) |
| `mcp__kendo.dev__delete-issue-tool` | Delete issue (destructive) |
| `mcp__kendo.dev__link-branch-tool` | Link a git branch to an issue |

### Time Logging

| Tool | Purpose |
|------|---------|
| `mcp__kendo.dev__get-time-entries-tool` | Query time entries (filter by project, user, team, issue, sprint; group by user/project/team/issue/day) |
| `mcp__kendo.dev__create-time-entry-tool` | Log time spent on an issue (1-479 minutes) |

### Epics

| Tool | Purpose |
|------|---------|
| `mcp__kendo.dev__get-epics-tool` | Get epics with full issue details and progress (filter by status) |
| `mcp__kendo.dev__create-epic-tool` | Create a new epic (with color, dates, linked issues) |
| `mcp__kendo.dev__update-epic-tool` | Update epic details, status, dates, or issue assignments |
| `mcp__kendo.dev__delete-epic-tool` | Delete an epic (destructive). Issues are kept. |

### Sprints

| Tool | Purpose |
|------|---------|
| `mcp__kendo.dev__create-sprint-tool` | Create a new sprint (title, start/end dates). Created as Planned. |
| `mcp__kendo.dev__update-sprint-tool` | Update sprint title, dates, or status (partial updates supported) |
| `mcp__kendo.dev__complete-sprint-tool` | Complete the active sprint, move incomplete issues to target sprint |

### Reports

| Tool | Purpose |
|------|---------|
| `mcp__kendo.dev__list-reports-tool` | List reports (bug reports, feedback) for a project with triage status |
| `mcp__kendo.dev__create-report-tool` | Create a new report (bug report, feature request, feedback) |
| `mcp__kendo.dev__promote-reports-tool` | Promote/convert one or more reports into a single issue (core triage action) |
| `mcp__kendo.dev__dismiss-report-tool` | Dismiss a report as not actionable (soft-archive) |
| `mcp__kendo.dev__delete-report-tool` | Delete a report permanently (destructive) |

## Common Operations

### Create Issue

```
project_id: <your-project-id>
title: "Clear descriptive title"
description: "Markdown content"
lane_id: <lane-id> (optional, defaults to first lane)
priority: 0-4 (0=Highest, 2=Medium default, 4=Lowest)
type: 0-1 (0=Feature, 1=Bug)
assignee_id: <user_id> (optional)
sprint_id: <sprint_id> (optional)
```

**Important:** The response includes both `id` (database ID, e.g. `206`) and `key` (display
reference, e.g. `PROJ-0142`). These are different values — always use `key` for branch names and
user-facing references, and `id` for API calls to other tools.

### Move Issue (via update-issue)

```
issue_id: <issue-id>
lane_id: <target-lane-id>
```

### Link Branch

```
issue_id: <issue-id>
branch_name: "feature/my-branch"
# GitHub repo is auto-resolved from the issue's project (primary repo preferred)
```

### Log Time

```
issue_id: <issue-id>
time_spent: 60  # Minutes (1-479)
sprint_id: <sprint_id> (optional)
```

### Query Time Logs

```
date_from: "2026-01-01"
date_to: "2026-01-31"
group_by: "user"  # user, project, team, issue, day, or none
project_id: <your-project-id> (optional)
```

### Workflow

1. Read `kendo://projects` to find your project ID
2. Read `kendo://projects/{id}/lanes` to find lane IDs
3. Use tools to create/update issues

### Get Issue by ID

Use `ReadMcpResourceTool` with `server: "kendo"` and `uri: "kendo://issues/{id}"` to fetch a single
issue directly. This returns full details including comments, branch links, blocking relations,
and time spent. **Always prefer this over searching when you have the issue ID.**

### Search Issues

Use `mcp__kendo__search-issues-tool` for text-based discovery across title, description, and issue key.
Note: this searches text fields only — it does not match on numeric database IDs.

## References

| File | Content |
|------|---------|
| [setup.md](references/setup.md) | MCP server setup instructions |
| [user-story-format.md](references/user-story-format.md) | Dutch user story template |
