---
name: commit
description: >
  Create small, focused commits with proper messages and push to remote. Matches this project's
  own commit-message convention rather than imposing one, and reads .claude/project-context.md
  for this project's integration branch so the protected-branch check doesn't miss a
  non-default name. Keeps the branch's plan in step with the code it commits, follows the
  project's hook rules, and refreshes an open PR's Summary after pushing. Use whenever the user
  wants to commit, save progress, push changes, or says "commit", "push", or "save my work".
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

Read `.claude/project-context.md`'s **Worktrees › House rules** once, if it has them: hooks that
run on commit or push, formatters that run on edit, and any commit rule the project records
there all apply to every commit below.

**Keep the plan in step.** Resolve the branch's plan directory with the canonical algorithm in
[`references/plan-directory.md`](../../references/plan-directory.md) (shipped with this plugin),
under `plan_root` (default `docs/plans`). When one exists and a commit's diff changes behaviour
that `PLAN.md`'s Approach or Scope, or a `DECISIONS.md` entry, describes, patch those files **in
that same commit** — before `git commit`, not after the push. Lint fixes, tests and renames leave
the plan alone. A plan that no longer matches its diff is what `precedent-reviewer` flags at
`/core-skills:review-branch`, and a stale plan misleads every later session that resumes from it.

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

A hook that fails is the gate working: fix the underlying issue and commit again. Never bypass it
with `--no-verify`.

### 5. Push to remote

```bash
git push
```
- If the branch has no upstream, use `git push -u origin HEAD`
- **CRITICAL:** Verify the upstream tracks a feature branch, not one of Step 1's protected
  branches. Run `git rev-parse --abbrev-ref @{upstream}` — if it shows a protected branch (e.g.
  `origin/main`, or this project's `integration_branch`), fix it with `git push -u origin HEAD`
  before pushing.

### 6. Refresh the PR Summary when a PR is open

After a successful push, if `gh pr list --head "$(git branch --show-current)"` returns an open PR,
splice its `## Summary` so it describes the branch as it now stands, using the recipe in
[`pr/SKILL.md`](../pr/SKILL.md) § Refreshing an existing PR body. Summary only: never pass a
partial body, and never add or rewrite any other section. No `gh`, or no PR: skip this step.

### 7. Report the commit hashes and confirm the push was successful.
