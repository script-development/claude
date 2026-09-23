---
name: prepare-issue
description: >
  Prepare a kendo issue for development: assign to current user, create a feature branch,
  link it, move to In Progress, and optionally check out in a worktree with full setup.
  Usage: /prepare-issue <issue_key_or_id_or_url> [N]. Use whenever the user wants to start working
  on an issue, prepare an issue, pick up an issue, or says "prepare issue", "start issue",
  "work on issue". Also trigger when combining issue assignment with branch creation, or when
  the user wants to set up a worktree for an issue.
argument-hint: "<issue-key-or-id-or-url> [worktree-number]"
arguments: [issue, worktree]
allowed-tools: Bash(git *) Bash(kendo *) Bash(gh *) Read Grep Glob
---

Task preparation assistant. Arguments: `$issue` (required), `$worktree` (optional, may be empty).

## Prerequisites

- Reads `issue_tracker_project_id` from `.claude/project-context.md` (see this plugin's own
  [README](../../README.md)) for the project to prepare issues in. If unset, discover it via
  `kendo-mcp`'s own `kendo://projects` resource and ask the user which project to use.
- Step 6 invokes `/newbranch`, a `core-skills` skill — declared as a dependency in this plugin's
  manifest, so installing `kendo-pm` installs `core-skills` automatically; no separate setup step
  needed.
- Step 7 Option C optionally invokes the consumer's own `/startup` skill to set up a new
  worktree. Not every consumer ships one: when it's absent, the worktree menu in Step 3 collapses
  to "primary or existing" and Option C is never offered.

- `$issue` — accepts three forms:
  - **Issue key** (e.g. `PROJ-0244`) — used verbatim.
  - **Numeric ID** (e.g. `244`) — used verbatim against `issue_id` in Step 1.
  - **Kendo URL** (e.g. `https://<your-tenant>.kendo.dev/projects/<project-id>/issues/PROJ-0631`)
    — extract the segment after `/issues/` and use that as the key. Strip any trailing `?…` query
    string or `#…` fragment.
- `$worktree` — worktree selection, skips the interactive question in Step 3:
  - `1` — use the primary worktree (default ports)
  - `2`, `3`, … — use or create worktree N (delegated to the consumer's `/startup` skill)
  - Empty — ask the user interactively (default behaviour)

**Normalise `$issue` before Step 1.** If `$issue` starts with `http://` or `https://`, set the
working issue value to the segment after `/issues/` (stripped of any `?` query or `#` fragment);
otherwise use `$issue` verbatim. All later steps reference the normalised value.

## Pre-resolved context

- **Current branch:** !`git branch --show-current`
- **Worktrees:** !`git worktree list`
- **Kendo CLI:** !`kendo --version 2>/dev/null || echo "not installed"`

These values are available immediately — do not re-run these commands during the steps below. If
**Kendo CLI** reads `not installed`, every kendo lookup must go through `mcp__kendo__*` tools.

**Error handling:** If any step fails, report the error clearly and stop — do not continue to the
next step. Then ask the user whether they want to reverse the steps that already completed.

If the user wants to reverse, undo completed steps in reverse order:

| Completed step | Reversal |
|----------------|----------|
| Started work on issue (assignee + lane + sprint + branch link) | `mcp__kendo__update-issue-tool` to restore the original `assignee_id` / `lane_id` / `sprint_id`; `mcp__kendo__unlink-branch-tool` to detach the branch |
| Created branch | `git branch -D {branch_name}` and `git push origin --delete {branch_name}` |

**Project:** project_id: `<project-id>` (`issue_tracker_project_id`, see Prerequisites)

## Step 1: Bundle the issue and project context (parallel)

Two MCP calls in one tool-call block replace the old fan-out across the issue, lanes, sprints,
and members resources:

```
parallel:
  mcp__kendo__prepare-project-context-tool
    project_id: <project-id>
  mcp__kendo__prepare-issue-context-tool
    issue_key: "PROJ-0244"     # or use issue_id when the argument is purely numeric
```

If the issue does not exist or returns an error, inform the user and stop. Otherwise capture
from the responses:

From `prepare-issue-context`:
- `issue.id`, `issue.key`, `issue.title` — to confirm with the user and to drive branch naming
- `issue.type` — `0` = Feature, `1` = Bug, `2` = Task. Used by Step 8's bug-workflow hint.

From `prepare-project-context`:
- `lanes[]` — find the entry where `title === "In Progress"` and remember its `id` for Step 6 / 5A
- `active_sprint.id` — for Step 6 / 5A; `null` means skip sprint (don't pass `null`, omit it)
- `current_user` — the authoritative MCP-auth'd developer
- `members[]` — for the assignee fallback in Step 2

Confirm the issue with the user: "Prepare **{key}** — *{title}*?"

## Step 2: Confirm the assignee

`current_user` from Step 1 is the developer running the skill (the MCP token is bound to the
user). Confirm: "Assigning to **{current_user.name}** — correct?"

If they want to assign to someone else, use `members[]` from the project context bundle to let
them pick. Capture the resulting `assignee_id` — the actual write happens later, in Step 6 (via
`/newbranch`) or Step 5A (existing-branch path), wrapped into the single `start-work-on-issue-tool`
call. **Do not** make a separate `update-issue-tool` call here — that doubles up with the work
done at the end.

## Step 3: Decide where to work

Use the **Worktrees** list from Pre-resolved context above — do not re-run `git worktree list`.

**If `$worktree` is non-empty**, skip the interactive question and use the value directly:
- `$worktree = 1` → primary worktree (Option A in Step 7)
- `$worktree >= 2` → check if that worktree already exists in the pre-resolved list. If it does,
  use it (Option B). If it doesn't exist, create it (Option C).

**If `$worktree` is empty**, present options using `AskUserQuestion`:

1. **Primary worktree** — check out the branch here (default)
2. Any **existing non-primary worktrees** detected, listed with their paths
3. **New worktree** — create a new worktree and set it up with `/startup`

If the consumer doesn't ship a `/startup` skill, the worktree options collapse to "primary or
existing"; remove Option C from the menu when no `/startup` is available.

## Step 4: Store the current branch

Use the **Current branch** value from Pre-resolved context — needed if the user chose a worktree
(to restore primary afterwards). Do not re-run `git branch --show-current`.

## Step 5: Check for existing branch

Before creating a new branch, check if a branch for this issue already exists. Users may create
branches manually with non-standard naming, so search broadly:

```bash
git branch --list -i "*PROJ-{issue_number}*" "*PROJ-0{issue_number}*" "*PROJ-00{issue_number}*"
```

Where `{issue_number}` is the numeric part of the key (e.g. `147` from `PROJ-0147`).
This catches variations like `PROJ-147-...`, `PROJ-0147-...`,
`fix/<prefix>-0147-...`, `feature/PROJ-0147-...`, etc.

Also check if the **current branch** might be related to the issue. Three outcomes:

### A. Clear match — branch contains the issue number (e.g. `PROJ-0147`, `PROJ-147`)

Skip `/newbranch` entirely. Check out the existing branch (if not already on it), then run a
single idempotent `start-work-on-issue-tool` call to align the issue state with the branch:

```
mcp__kendo__start-work-on-issue-tool
  issue_key:    "PROJ-0147"
  branch_name:  "{existing branch name}"
  assignee_id:  <assignee_id from Step 2>
  lane_id:      <In Progress lane id from Step 1>
  sprint_id:    <active_sprint.id from Step 1>   # omit when active_sprint is null
```

The tool no-ops per field — already-assigned, already-on-lane, and already-linked-branch all
short-circuit, so it's safe to run even when most of the state is already correct.

### B. Possible match — current branch does not contain the issue number, but the branch name overlaps with the issue title keywords

The user may have created a branch manually with a different naming convention (e.g.
`fix/workflow-setup` for issue *"Issue preparation skill for automated workflow setup"*).
Use `AskUserQuestion` to ask:

> "The current branch `{branch_name}` looks like it might be related to **{issue_key}** —
> *{issue_title}*. Is this the branch for this issue, or should I create a new one?"

Options: **Use this branch** / **Create new branch**

If the user picks "Use this branch", treat it as case A. Otherwise, proceed to Step 6.

### C. No match — no local branch contains the issue number and the current branch is unrelated

Proceed to create a new branch via `/newbranch` (Step 6).

## Step 6: Create branch via /newbranch (skip if branch exists)

Invoke the `/newbranch` skill with the issue key (e.g. `PROJ-0244`) as argument.
Pass through the `assignee_id` you confirmed in Step 2 if it differs from `current_user`
(otherwise `/newbranch` defaults to its own bundle of `current_user`).

`/newbranch` handles:
- Fetching latest from origin
- Creating the branch (`PROJ-XXXX-slug` from the project's integration branch)
- Calling `start-work-on-issue-tool` to assign, move to In Progress, add to the active sprint,
  and link the branch — all in one idempotent MCP call

After `/newbranch` completes, note the **branch name** it created.

## Step 7: Handle worktree choice

### Option A: Primary worktree

Nothing else to do — `/newbranch` already checked out the branch here.

### Option B: Existing worktree

The new branch is currently checked out in primary. Free it so the worktree can use it:

```bash
git checkout {previous_branch}
git -C {worktree_path} checkout {branch_name}
```

### Option C: New worktree

If `$worktree` is non-empty, use that value. Otherwise, determine the next worktree number N
from the **Worktrees** list in Pre-resolved context. The naming convention is project-specific —
consumers typically use `<repo-folder>-{N}` (e.g. `myapp-2`, `myapp-3`).

Free the branch from primary and create the worktree:

```bash
git checkout {previous_branch}
git worktree add ../{worktree_name} {branch_name}
```

Then invoke `/startup {N}` — passing N so startup skips its own worktree selection question and
goes directly to setup for worktree N (dependencies, env files, port patching, and whatever else
the consumer's `/startup` does for a secondary worktree).

## Step 8: Confirm

Print a summary:

```
Issue #{issue_id} ({key}) prepared!
  [x] Assigned to {user_name}
  [x] Branch: {branch_name} (from the integration branch)
  [x] Branch linked to issue
  [x] Moved to In Progress
  [x] Checked out on {location}
  [x] Worktree setup via /startup        ← only if new worktree
```

If the issue's `type` is `1` (Bug), append one extra line suggesting the bug
workflow — this skill doesn't run it, it just surfaces the next step:

```
  → Bug report detected. Next: /fix-bug {key}
```

For Feature (`type: 0`) or Task (`type: 2`) issues, skip the hint. The
developer already knows which workflow they want.
