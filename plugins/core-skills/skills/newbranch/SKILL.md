---
name: newbranch
description: >
  Create a new branch from this project's integration branch. If this project has an issue
  tracker configured, resolve or create the issue first and prepare it for work (assign, add to
  the active sprint, move to In Progress, link the branch). Use whenever the user wants to start
  a new feature, create a branch, begin work on an issue, or says "new branch".
---

# New Branch

Create a new git branch from this project's integration branch — and, if this project has an
issue tracker configured, prepare the linked issue for work (assign to the developer, add to the
active sprint, move to In Progress).

This skill is project-agnostic: it never assumes a specific tracker, tracker project id, or
issue-key format. What it reads from `.claude/project-context.md`, if present — `integration_branch`
(Step 1) and `issue_tracker_skill` / `issue_tracker_project_id` (Step 2). Missing file, or a
missing field within it, degrades to the generic behavior described inline — never a hard
failure.

## Step 1: Fetch latest

```bash
git fetch origin <integration-branch>
```

`<integration-branch>` is `integration_branch` from `.claude/project-context.md` if set,
otherwise auto-detect (`origin/development`, `origin/develop`, then the remote's default branch)
— the same detection `worktree` uses.

## Step 2: Find or create the issue

Read `issue_tracker_skill` from `.claude/project-context.md`. Defaults to `kendo-mcp` — this
org's in-house tracker — when unset, provided that skill is actually installed in the project;
`none` opts out explicitly (skip to Step 2b); any other value names a different tracker skill to
use in its place.

### 2a. Tracker resolved

Ask the user which issue to branch from. Options:

- **User provides an issue number or key** — resolve it through the tracker skill and read its
  `key` field.
- **User provides a search query** — search the tracker, scoped to `issue_tracker_project_id`
  from `.claude/project-context.md`.
- **User wants a new issue** — create one, scoped to the same project id. If the tracker skill
  ships its own issue-writing template (`kendo-mcp` does, at `references/issue-templates.md` —
  the feature-story and bug-report shapes used across this project) follow it; don't improvise a
  structure — reviewers and future developers searching the backlog rely on it being consistent.
  No such template shipped: use a generic title + description + acceptance-criteria shape.

Capture the issue's **key** and **title** — used for the branch name in Step 3 and the
start-of-work call in Step 4.

**For the default tracker, `kendo-mcp`:** fire the project-context and issue-context gather
tools in one parallel block (replaces separate reads of the project's lanes/sprints/members plus
the legacy `git config user.email` heuristic):

```
parallel:
  mcp__kendo__prepare-project-context-tool
    project_id: <issue_tracker_project_id>
  mcp__kendo__prepare-issue-context-tool
    issue_key: "<issue-key>"
```

From `prepare-issue-context`: `issue.id` / `issue.title` — branch slug source.

From `prepare-project-context`:
- `lanes[]` — find the entry whose `title === "In Progress"` and capture its `id` for Step 4
- `active_sprint` — its `id` for Step 4, or `null` if the project has no Active sprint (skip
  sprint then)
- `current_user` — authoritative MCP-auth'd developer; use `current_user.id` as the default
  `assignee_id`. Confirm with the user: "Assigning to **{current_user.name}** — correct?" If
  they want someone else, use `members[]` from the same bundle and let them pick.

A different named tracker skill: follow that skill's own instructions for the equivalent gather
step.

### 2b. No tracker resolved

Ask the user for a short kebab-case description to use as the branch slug directly. Skip issue
assignment, sprint, lane, and branch-link entirely — Step 4 doesn't apply.

## Step 3: Create the branch

Use the issue `key` (Step 2a) or the user-provided slug (Step 2b), plus a kebab-case summary of
the title (max ~5 words):

```bash
git checkout -b <issue-key>-short-description --no-track origin/<integration-branch>
git push -u --no-verify origin HEAD
```

**Why `--no-track`:** Git's default `autosetupmerge=always` makes the new local branch inherit
`origin/<integration-branch>` as its upstream. Without `--no-track`, a later `git push` would
push directly to `<integration-branch>` and bypass PR review. `--no-track` breaks that link; the
following `push -u` then wires the branch to its own remote.

Branch naming rules:
- If an issue key was resolved, prefix with the full key (e.g. `PROJ-0141`, not `PROJ-141`) — a
  truncated key can silently break a tracker's auto-link; if this project's tracker documents its
  own key format under `.claude/project-context.md`'s House Rules, follow that instead.
- Append a kebab-case slug from the issue title, or the user-provided description (Step 2b)
- Use only lowercase letters, numbers, and hyphens

## Step 4: Start work on the issue (skipped in 2b)

One idempotent write that bundles the state changes the developer would otherwise make
separately.

**For `kendo-mcp`:** the GitHub repo is auto-resolved from the project's primary repo — don't
pass it.

```
mcp__kendo__start-work-on-issue-tool
  issue_key:    "<issue-key>"
  branch_name:  "<issue-key>-short-description"
  assignee_id:  <current_user.id from Step 2, or chosen alternate>
  lane_id:      <In Progress lane id from Step 2>
  sprint_id:    <active_sprint.id from Step 2>   # omit when active_sprint is null
```

**Sprint semantics:** omitting `sprint_id` preserves the existing value; passing `null` clears
the sprint; passing an id sets it. So omit when there is no active sprint — don't pass `null`.

**Idempotency:** re-running with the same inputs is a no-op per field — fine to retry.

A different named tracker skill: follow that skill's own instructions for the equivalent
"start work" action (assign, sprint/iteration, lane/status, branch link).

## Step 5: Confirm

Tell the user in one concise block:
- The branch name (and its GitHub URL if you have it from the push output)
- The issue key + title + link, if a tracker resolved (else say no issue was linked)
- Who it's assigned to (or "no assignment — could not resolve current user")
- The active sprint it was added to (or "no active sprint — skipped")
- That the lane is now In Progress (only if a tracker resolved)
