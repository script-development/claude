---
name: pr
description: >
  Create a pull request for the current branch targeting the base branch, with automatic issue
  feedback (when the branch links to a tracked issue and this project has an issue tracker
  configured). Offers to run `/review-branch` when this session has no review for HEAD, gates bug
  branches on `bug-fix-verifier`'s verdict, and embeds that verdict in the PR body. Use this skill whenever the user wants to
  create a PR, open a pull request, submit their work for review, or is done with a feature/fix
  branch. Also triggers on phrases like "make a PR", "open PR", "create pull request", "submit
  for review", "I'm done with this branch", or "push and PR".
---

# Pull Request with Issue Feedback

Create a PR targeting the base branch and post structured feedback on the linked issue (when this
project has an issue tracker configured) to build a training corpus for improving future user
stories.

This skill reads `issue_tracker_skill` / `issue_tracker_project_id` (Step 3), `plan_root` /
`bug_root` (Step 4) from `.claude/project-context.md` — see this plugin's README for how that file
and its notation work.

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

This step builds a feedback loop for improving AI-generated user stories. By comparing what the
issue described against what was actually implemented, we capture learnings that will later
inform better story generation.

Read `issue_tracker_skill` from `.claude/project-context.md`. `none` skips this step entirely.
Otherwise, extract any leading issue-key-shaped prefix from the branch name (any `[A-Z]+-\d+`
token, e.g. `KD-0041` from `KD-0041-short-slug` — the same detection `catchup` and
`plan-directory.md` use). No such prefix: skip this step silently — the branch isn't issue-driven,
nothing to compare against.

**a. Find the issue**

**For the default tracker, `kendo-mcp`** (used when `issue_tracker_skill` is unset, provided that
skill is actually installed in the project): search using `mcp__kendo__search-issues-tool` with
`project_id: <project-id>` (`issue_tracker_project_id` from `.claude/project-context.md`) and
`query` set to the issue key. The key does not equal the database ID — the search tool resolves
this.

A different named tracker skill: follow that skill's own instructions for the equivalent search.

**b. Read the issue**

**For `kendo-mcp`:** read the full issue via `kendo://issues/{id}` to get the description and
acceptance criteria.

A different named tracker skill: follow that skill's own instructions for the equivalent read.

**c. Compare and comment**

Compare the issue description against the actual diff (`git diff origin/<base>...HEAD`). Post a
structured English feedback comment.

**For `kendo-mcp`:** use `mcp__kendo__add-comment-tool`.

A different named tracker skill: follow that skill's own instructions for the equivalent
comment/note.

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

### 4. Check the pre-PR review gate

`/pr` does not spawn the three pre-PR finders itself. A `/review-branch` report in this
session is optional. **Which gate applies depends on the branch type**, and the two are not
interchangeable:

| Branch | Gate | Artifact | Missing artifact |
|---|---|---|---|
| `<plan-root>/<slug>/` exists | none required | optional `/review-branch` report | **ask** whether to run `/review-branch` |
| `<bug-root>/<slug>/` exists | `bug-fix-verifier` | BUG.md `## Verification` | **never prompt** for `/review-branch` — see below |
| neither | none | — | skip the finder check |

Derive the directory using the canonical algorithm in
[`plan-directory.md`](../../references/plan-directory.md) (shipped with this plugin, shared with
`review-branch` and others), under `plan_root` then `bug_root` (defaults `docs/plans`,
`docs/bugs`).

### Plan-driven branches

Look in **this conversation** for a `/review-branch` report whose `Reviewed against commit:`
matches `git rev-parse --short HEAD`. **Fresh** means it matches HEAD.

**Not found** → prompt:

> No review in this session for HEAD `<sha>`. Run `/review-branch` first? [y/N]

Default **no**. If accepted, invoke `/review-branch` and wait for it before continuing. If
declined, proceed to step 5. A missing review does not block the PR.

**Stale** (a report exists but its sha is not HEAD) → prompt:

> Review is stale: reviewed `<sha>`, now at `<sha>`.
>
> Re-run `/review-branch`? [y/N]

Default **no**. **Fresh** or declined → proceed. Do **not** embed the review in the PR body.
The pushed code is the record.

Findings in the report do not block the PR. The parent session already saw them.

### Bug branches

`bug-fix-verifier`'s verdict in BUG.md's `## Verification` section **is** the gate — it
substitutes for the three finders, because a bug fix has no acceptance criteria to drift from,
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

Default no. This check applies even when `/pr` is invoked directly, without going through
`/fix-bug` in the same session — the Verification section is the durable record, not the
conversation.

**No `**Verdict:**` line found at all** — `bug-fix-verifier` has never run (e.g. `/pr` invoked
directly, skipping Phase 8). Treat this the same as a blocking verdict, not as "nothing to check":

> No bug-fix verification found in BUG.md § Verification. Run `bug-fix-verifier` (Phase 8 of
> `/fix-bug`) before creating this PR.
>
> Proceed with PR anyway? [y/N]

Default no.

**Never prompt for `/review-branch` on a bug branch.**

If a `/review-branch` report *is* in this session — it runs on bug branches when a developer asks
for it — the parent session has already seen its findings. They do not block the PR, and a stale
or absent report is not checked.

If the verifier gate passes, proceed to step 5.

### 5. Create or update the pull request

Analyze ALL commits on the branch (not just the latest) to write:
- **Title**: Brief description of the overall change (under 70 characters)
- **Body**: Summary of what the PR accomplishes, plus Bug Fix Verification when that gate
  applies. **No Review Handoff block.** The pushed code is the record.

If a PR already exists for this branch (`gh pr list --head "$(git branch --show-current)"`),
splice the body using **Refreshing an existing PR body** below. Always splice `## Summary`.
Also splice `## Bug Fix Verification` when **this run** just produced a new verifier verdict —
replace the heading if it is already in the body, insert it if it is missing. Do not add a
Review Handoff.

#### Refreshing an existing PR body

`gh pr edit --body` replaces the **whole** body. A Summary-only string wipes later `##`
sections. Always splice; never pass a partial body.

1. `old=$(gh pr view <n> --json body --jq .body)`
2. Note whether `$old` contains `## Bug Fix Verification`.
3. Build `$new` from `$old`. Replace from `## Summary` through (not including) the next
   `## ` heading, or through EOF if Summary is last.
4. When this run produced a new verifier verdict: replace from `## Bug Fix Verification`
   through the next `## `, or **insert** that heading after Summary if `$old` had none.
5. If `$old` had `## Bug Fix Verification` and `$new` does not, **abort**. A missing section
   may be added; a present one may not disappear unless step 4 replaced it with a new
   verdict.
6. `gh pr edit <n> --body "$new"`

Any skill that pushes to an open PR uses this same recipe. Splice Summary only, unless the run
just produced that verdict.

Otherwise:

```bash
gh pr create --base <base-branch> --title "PR title here" --body "$(cat <<'EOF'
## Summary
- Bullet points summarizing the changes

## Bug Fix Verification
<!-- Bug branches only. Omit on plan-driven and no-directory branches. -->
- Verifier: 9/10 (PASS) — defect no longer reproduces
- See `<bug-root>/<slug>/BUG.md` § Verification.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 6. Return the PR URL to the user
