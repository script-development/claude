---
name: nightwatch-mcp
description: |
  Nightwatch monitoring for the kendo application. Use when checking production or staging
  errors, triaging exceptions, investigating slow routes, reviewing application health, or managing
  issue status (resolve/ignore). Also use when the user mentions Nightwatch, production errors,
  exceptions, slow endpoints, or application monitoring. ALWAYS use this skill before calling any
  mcp__nightwatch__ tool — it contains pre-resolved IDs that skip unnecessary lookup calls.
---

# Nightwatch Monitoring

Monitor and triage production/staging issues for kendo using the Nightwatch MCP server.

## Application Context

| Key | Value |
|-----|-------|
| **Application** | Kendo |
| **Application ID** | `a1200a22-6414-4c04-9692-c42ffd66ce6c` |
| **Organization** | Script |

Always use this application ID directly — never call `list_applications` unless explicitly asked.

## Environments

| Environment | ID | Deploys from | URL |
|-------------|----|--------------|----|
| **Production** | `a1200a22-67cb-43f4-8009-115a63469706` | `main` branch | `script.kendo.dev` |
| **Staging** | `a1200adc-7b13-4444-9324-e4ba2770d324` | `development` branch | `staging-issue-tracker.fly.dev` |

Both environments are in `eu-central-1`, deployed on Fly.io (Amsterdam).

## MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp__nightwatch__list_issues` | List issues sorted by most recently seen (filter by environment, status, type) |
| `mcp__nightwatch__get_issue` | Full diagnostics: stack trace, code context, occurrence stats, activity log |
| `mcp__nightwatch__update_issue` | Change status (open/resolved/ignored), priority, title, description, assignee |
| `mcp__nightwatch__add_issue_comment` | Add a comment (only when explicitly asked or recording meaningful findings) |
| `mcp__nightwatch__list_applications` | List apps (rarely needed — ID is pre-resolved above) |
| `mcp__nightwatch__list_environments` | List environments (rarely needed — IDs are pre-resolved above) |

## Issue Types

Nightwatch tracks five types of issues:

| Type | Filter value | Description |
|------|-------------|-------------|
| Exception | `exception` | Unhandled exceptions and errors |
| Slow Route | `route` | HTTP requests exceeding 750ms threshold |
| Slow Job | `job` | Queued jobs exceeding threshold |
| Slow Command | `command` | Artisan commands exceeding threshold |
| Slow Scheduled Task | `scheduled_task` | Scheduled tasks exceeding threshold |

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

- Do not call `list_applications` or `list_environments` unless the user explicitly asks — use the pre-resolved IDs above.
- Only add comments when explicitly requested or when recording meaningful findings (root cause, fix applied). Do not comment just to acknowledge seeing an issue.
- When investigating exceptions, always read the relevant source file in the local codebase to provide actionable fix suggestions.
- Correlate deployment timing: if an issue appeared right after a deploy, check recent commits on the relevant branch (`main` for production, `development` for staging).
