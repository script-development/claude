---
name: nightwatch-mcp
description: |
  Nightwatch error and performance monitoring. Use when checking production or staging
  errors, triaging exceptions, investigating slow routes, reviewing application health, or managing
  issue status (resolve/ignore). Also use when the user mentions Nightwatch, production errors,
  exceptions, slow endpoints, or application monitoring. ALWAYS use this skill before calling any
  mcp__nightwatch__ tool.
---

# Nightwatch Monitoring

Triage production/staging issues using the Nightwatch MCP server.

## First-time setup: pre-resolve IDs for this project

Before any other call, resolve the application and environment IDs **once** so subsequent calls can pass them directly without lookup.

1. Look in the project's `CLAUDE.md` (root or `.claude/`) for a `Nightwatch` section listing pre-resolved IDs. If present, use those and skip the rest of this section.
2. Otherwise, call `mcp__nightwatch__list_applications` to find the application for this project (match by name or URL), then `mcp__nightwatch__list_environments` for that application.
3. Report the resolved IDs to the user and ask them to record the table below in their project `CLAUDE.md` so future sessions skip the lookup:

   ```markdown
   ## Nightwatch

   | Key | Value |
   |-----|-------|
   | Application | <name> |
   | Application ID | <uuid> |

   | Environment | ID | Deploys from | URL |
   |-------------|----|--------------|----|
   | Production  | <uuid> | <branch> | <url> |
   | Staging     | <uuid> | <branch> | <url> |
   ```

Once resolved, never call `list_applications` or `list_environments` again in the same project unless the user explicitly asks.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp__nightwatch__list_issues` | List issues sorted by most recently seen (filter by environment, status, type) |
| `mcp__nightwatch__get_issue` | Full diagnostics: stack trace, code context, occurrence stats, activity log |
| `mcp__nightwatch__update_issue` | Change status (open/resolved/ignored), priority, title, description, assignee |
| `mcp__nightwatch__add_issue_comment` | Add a comment (only when explicitly asked or recording meaningful findings) |
| `mcp__nightwatch__list_applications` | List apps (only on first-time setup — see above) |
| `mcp__nightwatch__list_environments` | List environments (only on first-time setup — see above) |

## Issue Types

Nightwatch tracks five types of issues:

| Type | Filter value | Description |
|------|-------------|-------------|
| Exception | `exception` | Unhandled exceptions and errors |
| Slow Route | `route` | HTTP requests exceeding the threshold |
| Slow Job | `job` | Queued jobs exceeding the threshold |
| Slow Command | `command` | Console commands exceeding the threshold |
| Slow Scheduled Task | `scheduled_task` | Scheduled tasks exceeding the threshold |

## Common Workflows

### Quick Health Check

1. Call `list_issues` with the application ID to see recent open issues
2. Summarize by type (exceptions vs slow routes) and recency
3. Flag anything that appeared in the last hour as potentially urgent

### Investigate an Exception

1. Call `get_issue` with the issue ref number and application ID
2. Review the stack trace and code context
3. Check occurrence statistics — is it new or recurring?
4. Cross-reference with the local codebase to find the root cause
5. If a fix is applied, mark as `resolved` (Nightwatch auto-reopens if it recurs)

### Environment-Specific Investigation

Pass `environment_id` to `get_issue` or `list_issues` to focus on one environment.
This is useful when an issue only occurs in production but not staging, or vice versa.

### Triage and Prioritize

Use `update_issue` to set priority (`none`, `low`, `medium`, `high`) and status:
- **open** — Active issue needing attention
- **resolved** — Fixed (auto-reopens if it recurs before deploy)
- **ignored** — Known/acceptable, suppress notifications

## Guidelines

- Do not call `list_applications` or `list_environments` unless this is first-time setup or the user explicitly asks.
- Only add comments when explicitly requested or when recording meaningful findings (root cause, fix applied). Do not comment just to acknowledge seeing an issue.
- When investigating exceptions, always read the relevant source file in the local codebase to provide actionable fix suggestions.
- Correlate deployment timing: if an issue appeared right after a deploy, check recent commits on the branch that environment deploys from (recorded in the project `CLAUDE.md`).
