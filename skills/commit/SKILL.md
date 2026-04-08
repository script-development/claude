---
name: commit
description: >
  Create small, focused commits with proper messages and push to remote. Use whenever the user
  wants to commit, save progress, push changes, or says "commit", "push", or "save my work".
---

# Commit

Create small, focused commits with proper messages and push to remote.

## Workflow

### 1. Branch safety check

Run `git branch --show-current` to check the current branch.
- If on a protected branch (`main`, `master`, `develop`, `development`), **warn the user** and
  suggest creating a feature branch first.
- Only proceed with committing once on a feature/fix branch.

### 2. Gather context

Run in parallel:
- `git status` — see all changes (never use `-uall` flag)
- `git diff` and `git diff --staged` — unstaged and staged changes
- `git log --oneline -5` — recent commit message style

### 3. Plan small commits

Group related changes into small, focused commits. Each commit should be a single logical unit:
- **Refactoring** separate from **new features**
- **Tests** separate from **implementation**
- **Config/CI** separate from **code changes**
- **Lint/formatting** separate from **logic changes**

### 4. For each commit

a. Stage only the files for this logical change with `git add <specific files>`
   - Do NOT commit files that likely contain secrets (.env, credentials.json, etc.)
   - Prefer specific file paths over `git add -A` or `git add .`

b. Create the commit using conventional commit format and a HEREDOC:
```bash
git commit -m "$(cat <<'EOF'
type(scope): description

Optional body with more details.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
   - Types: feat, fix, refactor, docs, test, chore, style, ci
   - Keep the first line under 72 characters
   - Focus on the "why" rather than the "what"

c. Repeat for each logical group of changes.

### 5. Push to remote

```bash
git push
```
- If the branch has no upstream, use `git push -u origin HEAD`
- **CRITICAL:** Verify the upstream tracks the correct remote branch (not a protected branch).
  Run `git rev-parse --abbrev-ref @{upstream}` — if it shows a protected branch like
  `origin/main` or `origin/develop`, fix it with `git push -u origin HEAD` before pushing.

### 6. Report the commit hashes and confirm the push was successful.
