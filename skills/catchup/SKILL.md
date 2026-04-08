---
name: catchup
description: |
  Load the full context of the current branch: git diff summary, commit history, plan/task files,
  and alignment with the base branch. Reports how far behind the base the branch is and offers to
  merge on confirmation. Resolves merge conflicts intelligently (auto-resolves obvious ones, asks
  on ambiguous ones). Use this skill whenever the user wants to understand what the current branch
  is about, needs context after a /clear, starts a new session, says "what am I working on",
  "load context", "catch me up", "branch context", "where was I", "summarize this branch",
  "catchup", "sync my branch", "update branch", or any variant of wanting to understand or sync
  the current state of work. Trigger on session start when the branch is not the default branch
  and the user's first message implies they want to resume work.
---

# Branch Catchup

Load everything about the current branch, check alignment with the base branch, and produce a
concise working summary so you (and the user) can hit the ground running.

## Step 1: Identify the branch and base

1. Run `git branch --show-current` to get the branch name
2. Determine the base branch:
   ```bash
   gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'
   ```
3. If on the default branch (main/master/develop), skip alignment reporting — just output context
4. Look for plan/task files — check common locations like `PLAN.md`, `TASKS.md`, or a `docs/plans/`
   directory. Use the branch name or any issue key in the branch name to find relevant files.

## Step 2: Gather context (run all in parallel)

Collect these data sources simultaneously:

| Source | Command / path | What to capture |
|--------|---------------|-----------------|
| **Commits** | `git log <base>..HEAD --oneline` | All commits on this branch |
| **Diff stat** | `git diff <base>...HEAD --stat` | Files changed + insertions/deletions |
| **Task file** | `TASKS.md` or similar | Progress: count completed vs total tasks |
| **Plan file** | `PLAN.md` or similar | High-level plan summary (first ~50 lines) |
| **Divergence** | `git fetch origin && git rev-list --left-right --count origin/<base>...HEAD` | Commits behind/ahead of base |

If any source doesn't exist, skip it silently — don't error.

## Step 3: Output a working summary

Present the summary in this format — keep it concise, not a wall of text:

```
## Branch: <branch-name>

### Alignment with <base>
<"Up to date" OR "X commits behind — say 'sync' to merge">

### What this branch does
<2-3 sentence summary derived from the plan and commits>

### Progress
<X/Y tasks complete>
- [x] Completed task summaries (one line each)
- [ ] **Next up:** <first incomplete task with brief description>
- [ ] Remaining tasks (one line each)

### Recent commits (last 5)
<short log>

### Files changed
<diff stat summary — e.g. "42 files changed across src/ and tests/">
```

**Important:**
- The summary should be scannable in under 30 seconds
- Don't reproduce full plan text — summarize it
- For tasks, show the status and what's next, not the full task details
- If all tasks are complete, say so and suggest next steps (PR, review, etc.)
- Always report the alignment status — the user should know whether they're on stale code

## Step 4: Align with base (only when the user confirms)

Do NOT merge automatically. After showing the summary, if the branch is behind the base, tell
the user how many commits behind they are and wait for confirmation (e.g., "sync", "merge it",
"yes", "go ahead").

When the user confirms alignment:

### 4a. Handle uncommitted changes

Run `git status --porcelain`. If there are uncommitted changes:
```bash
git stash push -m "catchup-auto-stash"
```
Remember to pop the stash after the merge completes.

### 4b. Merge the base branch

```bash
git merge origin/<base> --no-edit
```

Using merge (not rebase) because it's non-destructive and safe for branches already pushed to
origin. No force-push needed, history is preserved.

### 4c. If the merge succeeds cleanly

Report how many commits were pulled in and move on.

### 4d. If there are merge conflicts — resolve them

For each conflicting file:

1. **Read the conflict markers** — understand what both sides changed and why
2. **Check the git log for both sides** to understand the intent behind each change
3. **Read the surrounding code** for broader context
4. **Resolve based on clarity:**
   - **Clear-cut conflicts** (one side didn't touch the area, or changes are in different logical
     sections) → resolve automatically
   - **Ambiguous conflicts** (both sides changed the same logic) → describe the conflict to the
     user and ask for guidance before resolving
5. **Stage the resolved file** — `git add <file>`

After all conflicts are resolved:
```bash
git commit --no-edit
```

### 4e. Restore stashed changes

If changes were stashed in step 4a:
```bash
git stash pop
```
If the stash pop itself conflicts, resolve those using the same strategy.

### 4f. Report the result

```
### Alignment complete
Merged X commits from <base> (clean)
```
Or if conflicts were resolved:
```
### Alignment complete
Merged X commits from <base> — resolved conflicts in: file1.ts, file2.py
```
