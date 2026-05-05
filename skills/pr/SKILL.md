---
name: pr
description: >
  Create a pull request for the current branch, with optional issue feedback (when the branch
  links to a tracked issue) and optional review handoff (when a fresh review file exists in the
  plan directory). Use this skill whenever the user wants to create a PR, open a pull request,
  submit their work for review, or is done with a feature/fix branch. Also triggers on phrases
  like "make a PR", "open PR", "create pull request", "submit for review", "I'm done with this
  branch", or "push and PR".
---

# Pull Request

Create a PR targeting the base branch with a well-structured title and description. When the
branch links to a tracked issue, post structured feedback on it for the user-story training
corpus. When a fresh review handoff exists in the plan directory, embed each reviewer's summary
in the PR body so the reviewer doesn't have to dig.

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

### 3. Post issue feedback

This step builds a feedback loop for improving AI-generated user stories. Comparing what the
issue described against what was actually implemented captures learnings that can later inform
better story generation.

Skip this step silently if the branch name has no `{{ISSUE_KEY_PREFIX}}-` prefix (i.e. the branch
isn't issue-driven). Multi-project consumers can extend the prefix check to any of their project
keys.

**a. Find the issue**

Extract the issue key from the branch name (e.g. `{{ISSUE_KEY_PREFIX}}-0041` from
`{{ISSUE_KEY_PREFIX}}-0041-short-slug`).

Search for the issue using `mcp__kendo__search-issues-tool` with `project_id: {{PROJECT_ID}}`
and `query` set to the issue key. The key (e.g. `{{ISSUE_KEY_PREFIX}}-0041`) does not equal the
database ID — the search tool resolves this.

**b. Read the issue**

Read the full issue via `kendo://issues/{id}` to get the description and acceptance criteria.

**c. Compare and comment**

Compare the issue description against the actual diff (`git diff <base>...HEAD`). Post a
structured English feedback comment using `mcp__kendo__add-comment-tool`:

```markdown
## Feedback

### What was done
- [short summary of the actual implementation]

### Difference from description
- [deviations from the original description / acceptance criteria, or "No deviations"]

### What was missing or unclear
- [missing context, vague criteria, wrong assumptions]
- [scope that played out differently than described]
- [or "Description was clear and complete"]
```

**Feedback guidelines:**
- Be specific and actionable — "Acceptance criterion 3 was too vague about the expected behavior
  on an empty list" is better than "Description was unclear"
- Positive feedback matters too — if the description was clear and complete, say so explicitly
- Focus on what would help write a better user story next time
- Keep it concise: 2-5 bullet points per section max

### 4. Check for review handoffs

`/pr` does not spawn reviewer agents directly. It reads any review files that exist in the plan
directory. The on-disk format is fixed by the frozen contract in
[`../review-branch/references/review-file-format.md`](../review-branch/references/review-file-format.md):
each runner writes to its own `REVIEW_<RUNNER>.md` and the file carries a `Reviewed against
commit:` line as the staleness oracle. Catalog ships `/review-branch` (Claude) which writes
`REVIEW_CLAUDE.md`; consumers may run additional equivalent runners that produce parallel
`REVIEW_<RUNNER>.md` files. Multiple fresh review files are not voting — they are independent
opinions, both shown.

Derive the plan directory from the branch using the canonical algorithm in
[`../plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md).
If no plan directory exists, skip this step — the branch isn't plan-driven.

Glob the plan directory for `REVIEW_*.md`. For each file found, parse its `Reviewed against
commit:` field and compare against `git rev-parse --short HEAD`. Classify each as **fresh**
(matches HEAD) or **stale** (differs).

**No review files found** → prompt:

> No review handoff found for this branch. Run `/review-branch` first? [Y/n]

Default yes. If accepted, invoke `/review-branch` and wait for it to finish before continuing.

**At least one fresh review** → proceed. Embed every fresh review's summary in the PR body. If
multiple are fresh, show every block (informational — they're not voting, just both present).

**All found reviews are stale** → prompt:

> Review handoffs are stale:
> - `REVIEW_<RUNNER>.md` reviewed `<sha>` (now at `<sha>`)
> - …
>
> Re-run `/review-branch`? [Y/n]

Default yes.

**Fresh review contains blockers** → for each fresh review, parse the Executive Summary,
per-reviewer scores, and Required Fixes list. The frozen-format default threshold is `>= 7 / 10`;
if any reviewer is **below threshold** or **Required Fixes** is non-empty in any fresh file, warn
the user:

> Review blocks the PR (per `REVIEW_<RUNNER>.md`):
> - Acceptance: 6/10 (below threshold)
> - 2 required fixes listed
>
> Proceed with PR anyway? [y/N]

Default no. Pressing enter cancels so the user can fix first.

If everything meets threshold, proceed to step 5.

### 5. Create the pull request

Analyze ALL commits on the branch (not just the latest) to write:

- **Title**: Brief description of the overall change (under 70 characters)
- **Body**: Summary of what the PR accomplishes, plus a Review Handoff block per fresh reviewer
  (omit the section entirely if there's no plan directory or no fresh reviews).

```bash
gh pr create --base <base-branch> --title "PR title here" --body "$(cat <<'EOF'
## Summary
- Bullet points summarizing the changes

## Review Handoff
<!-- One block per fresh reviewer. Omit entire section if there's no plan / no fresh reviews. -->

**<Runner>** — reviewed YYYY-MM-DD against `<sha>`
- Overall: Ready for PR
- Acceptance: 9/10 (PASS)
- Simplicity: 8/10 (PASS)
- Silent Failure: N/A (not triggered)
- Efficiency: 10/10 (PASS)

See `<plan-directory>/REVIEW_<RUNNER>.md` for full findings and AC gaps.

## Test plan
- How to verify these changes work

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 6. Return the PR URL to the user
