---
name: newbranch
description: >
  Create a new branch from the default branch with a descriptive name. Use whenever the user wants
  to start a new feature, create a branch, begin work on an issue, or says "new branch",
  "start feature", "create branch".
argument-hint: "[branch name or description]"
---

# New Branch

Create a new git branch from the latest default branch with a well-formed name.

## Workflow

### 1. Fetch latest

Determine the default branch and fetch it:

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||')
git fetch origin "$DEFAULT_BRANCH"
```

If `refs/remotes/origin/HEAD` is not set, fall back to checking for `main` or `master`.

### 2. Determine the branch name

Use `$ARGUMENTS` if provided. Otherwise, ask the user what they're working on.

Construct a branch name following these rules:
- Use kebab-case (lowercase letters, numbers, hyphens only)
- If there's an issue/ticket number, prefix with it (e.g., `PROJ-123-add-user-auth`)
- If no issue number, use a descriptive slug (e.g., `add-user-authentication`)
- Keep it concise — max ~5 words after any prefix
- Optionally add a type prefix: `feature/`, `fix/`, `chore/` — follow the project's existing
  convention (check `git branch -a` for patterns)

### 3. Create the branch

```bash
git checkout -b <branch-name> --no-track origin/<default-branch>
git push -u origin HEAD
```

**CRITICAL:** Always use `--no-track` to prevent the new branch from inheriting the default
branch as its upstream. Then immediately push with `-u` to set tracking to the correct remote
branch. Without this, `git push` will push directly to the default branch.

### 4. Confirm

Tell the user:
- The branch name that was created
- That it's based on the latest default branch
- That tracking is set to the correct remote branch
