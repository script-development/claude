---
name: prepare-issue
description: >
  Prepare a kendo issue for development: assign to current user, create a feature branch,
  link it, and move to In Progress. Usage: /prepare-issue <issue_key_or_id>.
  Use whenever the user wants to start working on an issue, prepare an issue, pick up an issue,
  or says "prepare issue", "start issue", "work on issue". Also trigger when combining issue
  assignment with branch creation.
argument-hint: "<issue_key_or_id>"
---

# Prepare Issue

Prepare a kendo issue for development: assign it, create a branch, link it, and move to
In Progress — all in one step.

**Error handling:** If any step fails, report the error clearly and stop. Then ask the user
whether they want to reverse the steps that already completed.

Reversal steps (in reverse order):

| Completed step | Reversal |
|----------------|----------|
| Assigned issue | `mcp__kendo.dev__update-issue-tool` with original `assignee_id` (or `null`) |
| Moved to In Progress | `mcp__kendo.dev__update-issue-tool` with the original `lane_id` |
| Created branch | `git branch -D {branch_name}` and `git push origin --delete {branch_name}` |
| Linked branch | Tell the user to unlink manually via the kendo UI (no MCP tool available) |

## Step 1: Read the issue

Parse `$ARGUMENTS` for an issue key or numeric ID.

- If it looks like a key (contains letters, e.g. `PROJ-0244`), read `kendo://issues/{key}`
- If purely numeric, read `kendo://issues/{id}`

Extract the **id**, **title**, and **key** to confirm with the user. If the issue does not exist,
inform the user and stop.

## Step 2: Assign the issue to the current user

Read `kendo://projects/{project_id}/members` to get the team list. Detect the current user's email:

```bash
git config user.email
```

Match the email against the members list. If a match is found, confirm: "Assigning to **{name}** —
correct?" If no match, present the full list and let them pick.

Once confirmed, use `mcp__kendo.dev__update-issue-tool` with:
- `issue_key`: the issue key
- `assignee_id`: the confirmed member's ID

## Step 3: Determine the base branch

```bash
git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'
```

Fall back to asking the user if not set.

## Step 4: Check for existing branch

Before creating a new branch, check if one already exists for this issue:

```bash
git branch --list -a -i "*{issue_key}*"
```

Also check the current branch. Three outcomes:

### A. Clear match — branch contains the issue key

Skip branch creation. Check out the existing branch (if not already on it), link it to the issue
if not already linked, and ensure the issue is in the In Progress lane.

### B. Possible match — current branch name overlaps with issue title keywords

Ask the user: "The current branch `{branch_name}` looks like it might be related to
**{issue_key}** — *{issue_title}*. Use this branch, or create a new one?"

If "Use this branch", treat as case A.

### C. No match

Proceed to create a new branch (Step 5).

## Step 5: Create and link the branch

```bash
git fetch origin {base_branch}
git checkout -b {issue_key}-{slug} --no-track origin/{base_branch}
git push -u origin HEAD
```

Branch naming:
- Prefix with the full issue key (e.g., `PROJ-0141`)
- Append a kebab-case slug from the issue title (max ~5 words)
- Lowercase only

**CRITICAL:** Always use `--no-track` to prevent inheriting the base branch as upstream.
Then push with `-u` to set tracking correctly.

Link the branch to the issue:
```
mcp__kendo.dev__link-branch-tool
  issue_id: <issue_id>
  branch_name: "{branch_name}"
```

## Step 6: Move issue to In Progress

Read `kendo://projects/{project_id}/lanes` to find the In Progress lane ID.

Move the issue using `mcp__kendo.dev__update-issue-tool` with `lane_id`.

## Step 7: Confirm

Print a summary:

```
Issue {key} prepared!
  [x] Assigned to {user_name}
  [x] Branch: {branch_name} (from {base_branch})
  [x] Branch linked to issue
  [x] Moved to In Progress
```
