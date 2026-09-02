---
name: pr
description: >
  Create a pull request for the current branch targeting the base branch, with automatic issue
  feedback (when the branch links to a tracked issue) and the branch's review gate embedded in
  the PR body. Use this skill whenever the user wants to create a PR, open a pull request,
  submit their work for review, or is done with a feature/fix branch. Also triggers on phrases
  like "make a PR", "open PR", "create pull request", "submit for review", "I'm done with this
  branch", or "push and PR".
---

# Pull Request with Issue Feedback

Create a PR targeting the base branch and post structured feedback on the linked issue to build a
training corpus for improving future user stories.

## Workflow

### 1. Gather branch state

First, determine the base branch:

```bash
gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'
```

Then `git fetch origin <base>` — every diff/log command below compares against `origin/<base>`,
and fetching is what actually keeps that ref current. Naming the remote ref instead of the local
one doesn't help if it was never fetched.

Then run these commands in parallel:
- `git status` — check for uncommitted changes
- `git branch --show-current` — get current branch name
- `git log origin/<base>..HEAD --oneline` — all commits on this branch
- `git diff origin/<base>...HEAD --stat` — changed files summary

If there are uncommitted changes, ask the user if they want to commit first.

### 2. Push to remote

Check if the branch is pushed:
- If not, push with `git push -u origin HEAD`

### 3. Post issue feedback

This step builds a feedback loop for improving AI-generated user stories. By comparing what the issue
described against what was actually implemented, we capture learnings that will later inform better
story generation.

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

Compare the issue description against the actual diff (`git diff origin/<base>...HEAD`). Post a
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
- Be specific and actionable — "Acceptance criterion 3 was too vague about the expected behavior on
  an empty list" is better than "Description was unclear"
- Positive feedback matters too — if the description was clear and complete, say so explicitly
- Focus on what would help write a better user story next time
- Keep it concise: 2-5 bullet points per section max

### 4. Check for review handoffs

`/pr` does not spawn reviewer agents directly — it reads whatever gate artifact the branch's
pipeline produced. **Which gate applies depends on the branch type**, and the two are not
interchangeable:

| Branch | Gate | Artifact | Missing artifact |
|---|---|---|---|
| `docs/plans/<slug>/` exists | the pre-PR reviewer pair | `REVIEW_CLAUDE.md` | **prompt** to run `/review-branch` |
| `docs/bugs/<slug>/` exists | `bug-fix-verifier` | BUG.md `## Verification` | **never prompt** — see below |
| neither | none | — | skip this step |

Derive the directory using the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md).

### Plan-driven branches

Parse `REVIEW_CLAUDE.md`'s `Reviewed against commit:` line against `git rev-parse --short HEAD`.
**Fresh** means it matches HEAD.

**Not found** → prompt:

> No review handoff found for this branch. Run `/review-branch` first? [Y/n]

Default yes. If accepted, invoke `/review-branch` and wait for it before continuing.

**Stale** → prompt:

> Review handoff is stale: reviewed `<sha>`, now at `<sha>`.
>
> Re-run `/review-branch`? [Y/n]

Default yes. **Fresh** → proceed and embed its summary in the PR body.

### Bug branches

`bug-fix-verifier`'s verdict in BUG.md's `## Verification` section **is** the gate — it
substitutes for the reviewer pair, because a bug fix has no acceptance criteria to drift from,
only "does the defect still reproduce?". Embed that verdict in the PR body.

**Verdict blocks the PR** if the current one reads anything other than the exact string `PASS` —
including `FAIL`, `PARTIAL`, `BLOCKED` (the marker `/fix-bug`'s Phase 8.5 visual-risk gate writes
when a developer deferred a manual browser confirmation), and `PASS (requires developer
confirmation)` (the literal string path-3c reproductions get from `bug-fix-verifier` — this reads
as PASS at a glance but is exactly the unconfirmed case this gate exists to catch; don't treat a
verdict that merely starts with "PASS" as satisfying the check). Read only the **first**
`**Verdict:**` line under
`## Verification` — before any `### ... (superseded ...)` subheading. Re-verification passes leave
older verdicts in place marked superseded; those don't gate the PR. Warn the user:

> Bug fix verification blocks the PR (per BUG.md § Verification):
> - Verdict: BLOCKED — pending manual browser confirmation
>
> Proceed with PR anyway? [y/N]

Default no, same as the plan-driven below-threshold prompt. This check applies even when `/pr` is
invoked directly, without going through `/fix-bug` in the same session — the Verification section
is the durable record, not the conversation.

**No `**Verdict:**` line found at all** — `bug-fix-verifier` has never run (e.g. `/pr` invoked
directly, skipping Phase 8). Treat this the same as a blocking verdict, not as "nothing to check":

> No bug-fix verification found in BUG.md § Verification. Run `bug-fix-verifier` (Phase 8 of
> `/fix-bug`) before creating this PR.
>
> Proceed with PR anyway? [y/N]

Default no.

**Never prompt for a `/review-branch` handoff on a bug branch.** A missing `REVIEW_CLAUDE.md`
under `docs/bugs/` is the normal case, not a gap.

If one *is* present — `/review-branch` runs on bug branches when a developer asks for it — read
it and embed it alongside the verifier verdict. Apply the same freshness check, but on a stale or
absent file just note it; don't block.

**Fresh review contains blockers** → parse the Executive Summary, per-reviewer scores, and
Required Fixes list. If either reviewer is **below threshold (< 7 / 10)** or **Required Fixes**
is non-empty, warn the user:

> Review blocks the PR (per REVIEW_CLAUDE.md):
> - Runtime Integrity: 6/10 (below threshold)
> - 2 required fixes listed
>
> Proceed with PR anyway? [y/N]

Default no. Pressing enter cancels so the user can fix first.

If everything meets threshold, proceed to step 5.

### 5. Create the pull request

Analyze ALL commits on the branch (not just the latest) to write:
- **Title**: Brief description of the overall change (under 70 characters)
- **Body**: Summary of what the PR accomplishes, plus the gate block for this branch type.

```bash
gh pr create --base <base-branch> --title "PR title here" --body "$(cat <<'EOF'
## Summary
- Bullet points summarizing the changes

## Review Handoff
<!-- Plan-driven branches. Omit when there's no plan directory or no fresh review. -->

Reviewed <YYYY-MM-DD> against `<short-sha>`
- Overall: Ready for PR
- Runtime Integrity: 9/10 (PASS)
- Precedent: 8/10 (PASS)

See `docs/plans/<slug>/REVIEW_CLAUDE.md` for full findings.

<!-- Bug branches use this block INSTEAD — the verifier verdict is the gate. -->

## Bug Fix Verification
- Verifier: 9/10 (PASS) — defect no longer reproduces
- See `docs/bugs/<slug>/BUG.md` § Verification.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 6. Return the PR URL to the user
