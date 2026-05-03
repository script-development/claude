---
name: board-sync
description: |
  Synchronize the kendo board with GitHub branch and PR status. Use this skill whenever the
  user wants to check board alignment, sync the board, see what issues are stale, find merged PRs
  that haven't been moved to Done, or get an overview of branch status for open issues. Trigger on
  phrases like "sync board", "check board", "board status", "align board", "update board",
  "which issues are done", or "check branches".
---

# Board Sync

Cross-reference the kendo board with GitHub branches and PRs to find misaligned issues.

## Why This Exists

Issue boards drift out of sync when PRs get merged but nobody moves the card to Done. This skill
automates that check: it pulls open issues from the tracker, checks GitHub for matching
branches/PRs, and proposes board moves for anything that's already been merged.

## Workflow

### Step 1: Determine Project and Base Branch

1. Find the project — read `kendo://projects` and either use the active project or ask the user
   which one. Note the project ID and issue key prefix.
2. Determine the base branch (the main integration branch):
   ```bash
   git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'
   ```
   Fall back to asking the user if not set.

### Step 2: Gather Data (in parallel)

Fetch all of these simultaneously — they're independent:

1. **Issues**: `kendo://projects/{id}/issues` (MCP resource)
2. **Lanes**: `kendo://projects/{id}/lanes` (MCP resource) — identify the Done lane (last lane)
3. **Remote branches**: `gh api repos/{owner}/{repo}/branches --paginate --jq '.[].name'`
4. **All PRs**: `gh pr list --state all --limit 100 --json number,title,state,headRefName,mergedAt,baseRefName`

### Step 3: Filter Non-Done Issues

From the issues list, keep only issues NOT in the Done lane. For each, note:
- Issue ID, title, current lane, assignee

### Step 4: Match Issues to Branches/PRs

Match issues to GitHub branches and PRs using multiple strategies (try in order):

1. **Issue key in branch name** — e.g. branch `PROJ-0043-add-filtering` matches issue with key `PROJ-0043`
2. **Title-based fuzzy matching** — compare slugified issue title against branch names for strong
   word overlap
3. **PR title overlap** — compare PR titles against issue titles

For each matched issue, determine:
- **Has branch?** Does a remote branch exist?
- **Has PR?** Is there an associated pull request?
- **PR state?** OPEN, MERGED, or CLOSED
- **Merged into base branch?** Check `baseRefName` matches the base branch

### Step 5: Categorize and Report

Group issues into these categories and present as a table:

#### Category 1: Move to Done (PR merged into base branch)
Issues where the matching PR is merged but the issue is not in Done.
These are the actionable items.

#### Category 2: No Action — Open PRs
Issues with an open PR. Work is in progress, board position is probably correct.

#### Category 3: No Action — Branch exists, no PR
Issues with a branch on the remote but no PR created yet. Still in development.

#### Category 4: No Action — No matching branch
Issues with no identifiable branch. Either not started or using an unrecognizable branch name.

### Step 6: Propose Actions

Present the Category 1 issues as a numbered action list:

```
## Proposed Actions

These issues have merged PRs but are not in Done:

| Issue | Title | Current Lane | Merged PR |
|-------|-------|-------------|-----------|
| PROJ-0053 | Add user filtering | In Review | PR #257 (Feb 20) |
| ...   | ...                     | ...       | ...               |

Move these N issues to Done?
```

Wait for user confirmation before executing any moves.

### Step 7: Execute (only after confirmation)

Move confirmed issues to the Done lane using `mcp__kendo.dev__update-issue-tool` with `lane_id`.
Execute all moves in parallel since they're independent.

Report the result:

```
| Issue | Title | Moved from |
|-------|-------|------------|
| PROJ-0053 | Add user filtering | In Review -> Done |
```

## Edge Cases

- **Multiple PRs for one issue**: If an issue has both open and merged PRs, the merged one takes
  precedence — the work is done.
- **PR merged into non-base branch**: Don't count these as "done". Only PRs merged into the
  base branch indicate completed work.
- **Closed but not merged PRs**: Ignore these — the work was abandoned or redone elsewhere.
- **No MCP connection**: If MCP resources fail, tell the user to check MCP connectivity
  (`/mcp` command).

## Notes

- The matching is fuzzy and may miss some connections. When in doubt, include the "no matching
  branch" category so the user can spot any misses.
- The issues list from MCP can be large. Use a subagent to parse the full issue list if the
  output is too big for inline processing.
