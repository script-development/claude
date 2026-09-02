---
name: newbranch
description: >
  Create a new branch from `{{DEFAULT_BRANCH}}`, named after a Kendo issue (e.g. `{{ISSUE_KEY_PREFIX}}-0141-short-description`).
  Use whenever the user wants to start a new feature, create a branch, begin work on an issue,
  or says "new branch".
---

# New Branch

Create a new git branch from `origin/{{DEFAULT_BRANCH}}`, named after a Kendo issue — and prepare the
issue for work (assign to the developer, add to the active sprint, move to In Progress).

**Project:** project_id `{{PROJECT_ID}}`, issue key prefix `{{ISSUE_KEY_PREFIX}}`.

## Workflow

### 1. Fetch latest

```bash
git fetch origin {{DEFAULT_BRANCH}}
```

### 2. Find or create the issue

Ask the user which issue to branch from. Options:

- **User provides an issue number or key** — Read `kendo://issues/{id-or-key}` and use its `key` field.
- **User provides a search query as the argument** — Try `kendo://issues/{arg}` first; if that fails,
  use `mcp__kendo__search-issues-tool` with `project_id: {{PROJECT_ID}}` and the argument as the query.
- **User wants a new issue** — Create one via `mcp__kendo__create-issue-tool` with `project_id: {{PROJECT_ID}}`.
  **Follow the issue templates in
  [`kendo-mcp/references/issue-templates.md`](../kendo-mcp/references/issue-templates.md)** — that
  file is the single source of truth for the feature user-story format and the bug-report format
  used across this project. Don't improvise a structure; readers of the issue (reviewers, future
  developers searching the backlog) rely on the template being consistent.

After creating or resolving the issue, capture its **key** (for branch naming and the bundle call
in step 3).

### 3. Bundle the issue and project context (parallel)

Two MCP calls fired in one tool-call block replace the old four-resource fan-out across the
issue, lanes, sprints, and members resources, plus the legacy `git config user.email` heuristic:

```
parallel:
  mcp__kendo__prepare-project-context-tool
    project_id: {{PROJECT_ID}}
  mcp__kendo__prepare-issue-context-tool
    issue_key: "{{ISSUE_KEY_PREFIX}}-0141"
```

Together the responses carry everything the rest of the workflow needs:

From `prepare-issue-context`:
- `issue.id` / `issue.title` — branch slug source

From `prepare-project-context`:
- `lanes[]` — find the entry whose `title === "In Progress"` and capture its `id` for step 5
- `active_sprint` — `id` for step 5, or `null` if the project has no Active sprint (skip sprint then)
- `current_user` — authoritative MCP-auth'd developer; use `current_user.id` as the default
  `assignee_id`. No `git config user.email` heuristic needed — the token is bound to the user.
  Confirm with the user: "Assigning to **{current_user.name}** — correct?" If they want to assign
  to someone else, use `members[]` from the same project-context bundle and let them pick.

### 4. Create the branch

Use the issue `key` (e.g. `{{ISSUE_KEY_PREFIX}}-0141`) and a kebab-case summary of the title:

```bash
git checkout -b {{ISSUE_KEY_PREFIX}}-0141-short-description --no-track origin/{{DEFAULT_BRANCH}}
git push -u --no-verify origin HEAD
```

**Why `--no-track`:** Git's default `autosetupmerge=always` makes the new local branch inherit
`origin/{{DEFAULT_BRANCH}}` as its upstream. Without `--no-track`, a later `git push` would push directly
to `{{DEFAULT_BRANCH}}` and bypass PR review. `--no-track` breaks that link; the following `push -u` then
wires the branch to its own remote.

Branch naming rules:
- Prefix with the full issue key (e.g. `{{ISSUE_KEY_PREFIX}}-0141`, not `{{ISSUE_KEY_PREFIX}}-141`)
- Append a kebab-case slug from the issue title (max ~5 words)
- Use only lowercase letters, numbers, and hyphens

### 5. Start work on the issue (assign + sprint + lane + branch link in one call)

One idempotent write that bundles the four state changes the developer would otherwise make
separately. The GitHub repo is auto-resolved from the project's primary repo — don't pass it.

```
mcp__kendo__start-work-on-issue-tool
  issue_key:    "{{ISSUE_KEY_PREFIX}}-0141"
  branch_name:  "{{ISSUE_KEY_PREFIX}}-0141-short-description"
  assignee_id:  <current_user.id from step 3, or chosen alternate>
  lane_id:      <In Progress lane id from step 3>
  sprint_id:    <active_sprint.id from step 3>   # omit when active_sprint is null
```

**Sprint semantics:** omitting `sprint_id` preserves the existing value; passing `null` clears
the sprint; passing an id sets it. So omit when there is no active sprint — don't pass `null`.

**Idempotency:** re-running with the same inputs is a no-op per field — fine to retry.

### 6. Confirm

Tell the user in one concise block:
- The branch name (and its GitHub URL if you have it from the push output)
- The issue key + title + link
- Who it's assigned to (or "no assignment — could not resolve current user")
- The active sprint it was added to (or "no active sprint — skipped")
- That the lane is now In Progress
