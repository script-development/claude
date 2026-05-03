---
name: pr
description: >
  Create a pull request for the current branch. Use this skill whenever the user wants to create
  a PR, open a pull request, submit their work for review, or is done with a feature/fix branch.
  Also triggers on phrases like "make a PR", "open PR", "create pull request", "submit for review",
  "I'm done with this branch", or "push and PR".
---

# Pull Request

Create a PR targeting the base branch with a well-structured title and description.

## Workflow

### 1. Gather branch state

Run these commands in parallel:
- `git status` — check for uncommitted changes
- `git branch --show-current` — get current branch name
- Determine the base branch:
  ```bash
  gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'
  ```
- `git log <base>..HEAD --oneline` — all commits on this branch
- `git diff <base>...HEAD --stat` — changed files summary

If there are uncommitted changes, ask the user if they want to commit first.

### 2. Push to remote

Check if the branch is pushed and up to date:
- If not pushed, push with `git push -u origin HEAD`
- If behind remote, push first

### 3. Create the pull request

Analyze ALL commits on the branch (not just the latest) to write:
- **Title**: Brief description of the overall change (under 70 characters)
- **Body**: Summary of what the PR accomplishes

```bash
gh pr create --base <base-branch> --title "PR title here" --body "$(cat <<'EOF'
## Summary
- Bullet points summarizing the changes

## Test plan
- How to verify these changes work

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 4. Return the PR URL to the user
