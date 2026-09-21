---
name: commit
description: >
  Create small, focused commits with proper messages and push to remote. Matches this project's
  own commit-message convention rather than imposing one, and reads .claude/project-context.md
  for this project's integration branch so the protected-branch check doesn't miss a
  non-default name. Use whenever the user wants to commit, save progress, push changes, or says
  "commit", "push", or "save my work".
---

# Commit

Create small, focused commits with proper messages and push to remote.

## Workflow

### 1. Branch safety check

Run `git branch --show-current` to check the current branch against the protected set:
`main`, `master`, `develop`, `development`, plus `integration_branch` from
`.claude/project-context.md`'s Worktrees section, if this project sets one. That field exists
for projects whose integration branch isn't one of the four defaults (`trunk`, `staging`, ...) —
without it, a commit to that branch would slip through unwarned.

- If on a protected branch, **warn the user** and suggest creating a feature branch first.
- Only proceed with committing once on a feature/fix branch.

### 2. Gather context

Run in parallel:
- `git status` — see all changes (never use `-uall` flag)
- `git diff` and `git diff --staged` — unstaged and staged changes
- `git log --oneline -10` — this project's actual commit-message convention. Step 4b follows
  whatever this shows, not a fixed format — a wider window than 5 gives a fairer read before
  concluding there's no clear pattern.

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

b. Match this project's own message convention — the one Step 2's `git log` showed:
   - **If recent commits follow a clear pattern** (conventional-commit types, a ticket-number
     prefix, a particular structure), match it, not the default below.
   - **If there's no clear pattern**, default to conventional commits:
```bash
git commit -m "$(cat <<'EOF'
type(scope): description

Optional body with more details.

<attribution trailer, exactly as the harness injects it for this session>
EOF
)"
```
     Types: feat, fix, refactor, docs, test, chore, style, ci.
   - Either way: keep the first line under 72 characters, focus on the "why" rather than the
     "what", and keep whatever trailer convention the harness injects for this session — do not
     hardcode a model name here, it goes stale.

c. Repeat for each logical group of changes.

### 5. Push to remote

```bash
git push
```
- If the branch has no upstream, use `git push -u origin HEAD`
- **CRITICAL:** Verify the upstream tracks a feature branch, not one of Step 1's protected
  branches. Run `git rev-parse --abbrev-ref @{upstream}` — if it shows a protected branch (e.g.
  `origin/main`, or this project's `integration_branch`), fix it with `git push -u origin HEAD`
  before pushing.

### 6. Report the commit hashes and confirm the push was successful.
