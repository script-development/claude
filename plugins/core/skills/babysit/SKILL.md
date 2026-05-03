---
name: babysit
description: |
  Watch a PR's GitHub Actions CI, automatically fix failures, and push until green. Use this skill
  whenever the user says "babysit", "watch ci", "fix ci", "make ci green", "monitor the PR",
  "keep pushing until green", or after creating a PR when they want hands-off CI resolution.
  Also use proactively after /commit or /pr when CI is likely to run and the user seems done coding.
argument-hint: "[PR number or branch name]"
---

# Babysit

Watch a PR's CI pipeline. When checks fail, read the logs, fix the code, commit, push, and repeat
until everything is green. The goal: the user invokes this once and walks away.

## Finding the PR

Parse `$ARGUMENTS` for a PR number or branch name. If empty, detect from the current branch:

```bash
# Get PR for current branch
gh pr list --head "$(git branch --show-current)" --json number,url,title --jq '.[0]'
```

If no PR exists for the branch, tell the user and stop.

Store the PR number and branch name — you'll need them throughout.

## The Loop

Run this cycle up to **5 times**. If CI still fails after 5 fix attempts, stop and report what's
left — the issue likely needs human judgment.

### Step 1: Wait for CI to finish

Poll the CI status. CI workflows typically take a few minutes.

```bash
gh pr checks <PR> --watch --fail-fast 2>&1
```

This blocks until all checks complete or one fails. If the command isn't available or hangs,
fall back to polling:

```bash
gh run list --branch <branch> --limit 1 --json status,conclusion,databaseId,name
```

Poll every 30 seconds. A run is done when `status` is `completed`.

### Step 2: Check the result

```bash
gh pr checks <PR> --json name,state,description
```

If all checks pass → **done**. Report success and stop.

If any check failed → continue to Step 3.

### Step 3: Get the failure logs

Find the failed run ID, then fetch only the failed output:

```bash
# Get the failed run ID
gh run list --branch <branch> --limit 1 --json databaseId,conclusion --jq '.[] | select(.conclusion == "failure") | .databaseId'

# Get failed job logs (this is the key command — only shows what broke)
gh run view <run-id> --log-failed 2>&1
```

`--log-failed` returns only the output from failed steps, which is exactly what you need to
diagnose the issue. Read it carefully.

### Step 4: Diagnose and fix

Categorize the failure and fix it.

#### Auto-fixable (just run the tool)

Many CI failures can be fixed by running a formatter or fixer tool locally. Examples (adapt to
the project's stack):

| Failure | Typical fix command |
|---------|---------------------|
| JS/TS lint with fixable errors | `npx eslint . --fix` / `prettier --write` |
| PHP style | `./vendor/bin/pint` / `php-cs-fixer fix` |
| PHP upgrade rules | `vendor/bin/rector` |
| Go format | `gofmt -w .` |
| Rust format | `cargo fmt` |
| Python format | `black .` / `ruff format` |

After running the fixer, verify the check passes locally before committing.

#### Requires code changes

| Failure | Diagnosis approach |
|---------|-------------------|
| Type errors (TS, mypy, phpstan, etc.) | Read the error lines, fix type mismatches, missing imports, narrowed types |
| Test failures | Read which test failed and why, fix the code or test |
| Build failures | Read bundler/compiler output, fix syntax or import errors |
| Spell check | Fix typos or add to the project's spell-check word list |
| Layer/boundary violations | Read which boundary was crossed, move the import |
| Coverage failures | Write missing tests for uncovered lines |

For code changes:
1. Read the relevant files to understand context
2. Make the minimal fix — do NOT refactor or improve unrelated code
3. Verify locally with the narrowest possible check (run just the failing test, or just the type
   checker on the affected file)

### Step 5: Commit and push

Stage only the fix files. Use a conventional commit message that references the CI failure:

```bash
git add <specific-files>
git commit -m "$(cat <<'EOF'
fix(<scope>): <what was fixed>

CI fix: <which check failed and why>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

**Important:** Verify upstream before pushing:
```bash
git rev-parse --abbrev-ref @{upstream}
```
If it shows a main/default branch instead of the feature branch, fix with `git push -u origin HEAD`.

### Step 6: Loop back

After pushing, go back to Step 1. The push triggers a new CI run automatically.

## Reporting

After each iteration, give a brief status update:

```
## Babysit — Iteration 2/5

Fixed: Type error in AuthService.ts (missing null check)
Pushed: abc1234
Waiting for CI run #12345...
```

When done (success or max iterations reached):

```
## Babysit — Complete

PR #42: Fix authentication flow
Status: All checks passing
Iterations: 2 (1 fix applied)

Fixes applied:
1. fix(auth): add null check for token expiry — TypeScript
```

Or if still failing after max iterations:

```
## Babysit — Stopped (5/5 iterations)

PR #42: Fix authentication flow
Status: 2 checks still failing

Remaining failures:
- test-unit: AuthServiceTest::testRefresh — assertion mismatch
- lint: 3 unresolved warnings in src/auth/

These likely need manual investigation. Run `gh run view <id> --log-failed` to see details.
```

## Edge Cases

- **Multiple failures**: Fix all failures in a single commit when possible. If they're unrelated,
  fix both before pushing — no need for separate commits per failure type.
- **Flaky tests**: If the same test fails with different errors across iterations, it may be flaky.
  Note this in the report and suggest a rerun: `gh run rerun <id> --failed`.
- **CI queued**: If a previous run is still in progress when you push, the new run will queue.
  That's fine — just wait for the latest one.
- **Unrelated failures**: If a check fails on code you didn't touch (e.g., a pre-existing issue
  on the base branch), note it and skip — don't fix other people's problems in this PR.
