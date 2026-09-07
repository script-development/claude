---
name: pr
description: >
  Create a pull request for the current branch targeting the base branch, with automatic issue
  feedback (when the branch links to a tracked issue). Reads this session's `/review-branch`
  report as the pre-PR gate, and embeds the bug-fix and docs-accuracy verdicts in the PR body.
  Use this skill whenever the user wants to create a PR, open a pull request,
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

### 4. Check the pre-PR review gate

`/pr` does not spawn the always-on reviewer pair itself. It consumes a `/review-branch` report
**in this session** whose `Reviewed against commit:` sha matches `git rev-parse --short HEAD`.
**Which gate applies depends on the branch type**, and the two are not interchangeable:

| Branch | Gate | Verdict lives in | Missing |
|---|---|---|---|
| `docs/plans/<slug>/` exists | the pre-PR reviewer pair | this session's `/review-branch` report for HEAD | **prompt** to run `/review-branch` |
| `docs/bugs/<slug>/` exists | `bug-fix-verifier` | BUG.md `## Verification` | **never prompt** for `/review-branch` — see below |
| neither | none | — | skip the reviewer-pair check |

Derive the directory using the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md).

**One gate cuts across all three rows**: `docs-accuracy-reviewer`, triggered by the paths in the
diff rather than by the branch's shape. Run the check below on every branch, whichever row it
matched — including the `neither` row that otherwise skips this step.

```bash
git diff --name-only origin/{{DEFAULT_BRANCH}}...HEAD -- {{DOC_PATHS}}
```

Copy the `{{DOC_PATHS}}` pathspecs exactly. They are directory prefixes on purpose —
`<prefix>/**/*.md` looks equivalent and is not: git requires an intervening directory for that
`**`, so it misses `<prefix>/README.md` and every sibling sitting directly under `<prefix>`.

Empty output: nothing to do. Otherwise the branch ships user-facing text, and this step wants a
docs-accuracy verdict for it. That verdict is **in this session** (from `/review-branch` when
that run included the reviewer, or from a direct spawn) and is embedded in the PR body under
`## Docs accuracy`. Runtime Integrity and Precedent scores stay in chat. They do not go in the
PR body.

| Branch has | Verdict lives in | Missing |
|---|---|---|
| `docs/plans/<slug>/` | this session's `/review-branch` `## Docs Accuracy Review`, present and fresh vs HEAD | **prompt** to run `/review-branch` — including when the session review is fresh but carries no such section |
| `docs/bugs/<slug>/` | a **fresh** in-session `/review-branch` § Docs Accuracy if one is there, else the PR body | **prompt** to run the reviewer directly — never `/review-branch` |
| no directory | the PR body block this step writes | **prompt** to run the reviewer directly |

**A bug branch is never prompted for `/review-branch`, and this gate does not change that.**
The rule under § Bug branches below is absolute: `/pr` never asks for a pre-PR reviewer-pair
run on a bug branch. So on a bug branch that ships text, prompt for the *reviewer*, not for
`/review-branch` — the same way the no-directory row does. If the developer happened to run
`/review-branch` anyway in this session, its § Docs Accuracy section is read and no prompt is
needed.

**A docs-accuracy verdict counts only if it is both present and fresh**, on any branch shape.
Two separate checks, and passing one does not imply the other:

1. **Present** — this session's review actually contains a `## Docs Accuracy Review` section. A
   report without it is not a pass on the docs gate; it is a run where this reviewer did not
   fire. Treat the missing section exactly as a missing review — prompt.
2. **Fresh** — its `Reviewed against commit:` line matches `git rev-parse --short HEAD`.

Do not let a fresh reviewer-pair report stand in for a docs verdict that was never written.
Read for the section by name.

On a branch prompted for the reviewer directly:

> This branch changes user-facing text (`<the paths the trigger returned>`) and has no
> docs-accuracy verdict. Run `docs-accuracy-reviewer` before creating the PR? [Y/n]

List the paths the trigger actually returned, not a fixed example — the developer decides whether
to spend the run on what changed.

Default yes. If accepted, spawn the agent against `origin/{{DEFAULT_BRANCH}}...HEAD` and embed
its report — score, per-claim findings, compliance flags — in the PR body under
`## Docs accuracy`. **Below 7 blocks the PR** on the same terms as a below-threshold reviewer
score: warn, and default to not proceeding.

This is the one place `/pr` reaches for an agent rather than reading a session report, and it is
deliberate. A branch that only edits prose runs no `/plan-feature` and no `/fix-bug`, so it has
no pipeline that could have produced a review — and a branch with no pipeline is exactly the
branch this gate exists for.

### Plan-driven branches

Look in **this conversation** for a `/review-branch` report whose `Reviewed against commit:`
matches `git rev-parse --short HEAD`. **Fresh** means it matches HEAD.

**Not found** → prompt:

> No review in this session for HEAD `<sha>`. Run `/review-branch` first? [Y/n]

Default yes. If accepted, invoke `/review-branch` and wait for it before continuing.

**Stale** (a report exists but its sha is not HEAD) → prompt:

> Review is stale: reviewed `<sha>`, now at `<sha>`.
>
> Re-run `/review-branch`? [Y/n]

Default yes. **Fresh** → proceed. Do **not** embed Runtime Integrity or Precedent scores in the
PR body. The pushed code is the record.

Freshness here settles the reviewer pair only. If the docs trigger above fired, also confirm the
session report carries a `## Docs Accuracy Review` section before treating this step as
satisfied.

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

**Never prompt for `/review-branch` on a bug branch.** The docs-accuracy gate above is not an
exception to this: on a bug branch it prompts for `docs-accuracy-reviewer` itself and embeds the
verdict in the PR body, never for `/review-branch`.

If a `/review-branch` report *is* in this session — it runs on bug branches when a developer asks
for it — read it and treat it alongside the verifier verdict. Apply the same freshness check, but
on a stale or absent report just note it; don't block.

**Fresh review contains blockers** → parse the in-session Executive Summary, per-reviewer scores,
and Required Fixes list. If **any** reviewer is **below threshold (< 7 / 10)** or **Required
Fixes** is non-empty, warn the user.

Read the count from the report, not from memory: the Executive Summary's `Blocks threshold:`
line already names whichever reviewers ran.

> Review blocks the PR:
> - Runtime Integrity: 6/10 (below threshold)
> - Docs Accuracy: 5/10 (below threshold)
> - 2 required fixes listed
>
> Proceed with PR anyway? [y/N]

Default no. Pressing enter cancels so the user can fix first.

If everything meets threshold, proceed to step 5.

### 5. Create or update the pull request

Analyze ALL commits on the branch (not just the latest) to write:
- **Title**: Brief description of the overall change (under 70 characters)
- **Body**: Summary of what the PR accomplishes, plus Bug Fix Verification and Docs accuracy
  when those gates apply. **No Review Handoff block.** The pushed code is the record.

If a PR already exists for this branch (`gh pr list --head "$(git branch --show-current)"`),
splice the body using **Refreshing an existing PR body** below. Always splice `## Summary`.
Also splice `## Docs accuracy` and/or `## Bug Fix Verification` when **this run** just produced
a new verdict for that gate — replace the heading if it is already in the body, insert it if
it is missing. Do not add a Review Handoff.

#### Refreshing an existing PR body

`gh pr edit --body` replaces the **whole** body. A Summary-only string wipes later `##`
sections. Always splice; never pass a partial body.

1. `old=$(gh pr view <n> --json body --jq .body)`
2. Note whether `$old` contains `## Docs accuracy` and `## Bug Fix Verification`.
3. Build `$new` from `$old`. Replace from `## Summary` through (not including) the next
   `## ` heading, or through EOF if Summary is last.
4. When this run produced a new Docs accuracy verdict: replace from `## Docs accuracy`
   through the next `## `, or **insert** that heading after Summary if `$old` had none.
   Same for Bug Fix Verification when this run produced a new verifier verdict.
5. If `$old` had `## Docs accuracy` and `$new` does not, **abort**. Same for
   `## Bug Fix Verification`. A missing section may be added; a present one may not
   disappear unless step 4 replaced it with a new verdict.
6. `gh pr edit <n> --body "$new"`

Any skill that pushes to an open PR uses this same recipe. Splice Summary only, unless the run
just produced one of those two verdicts.

Otherwise:

```bash
gh pr create --base <base-branch> --title "PR title here" --body "$(cat <<'EOF'
## Summary
- Bullet points summarizing the changes

## Bug Fix Verification
<!-- Bug branches only. Omit on plan-driven and no-directory branches. -->
- Verifier: 9/10 (PASS) — defect no longer reproduces
- See `docs/bugs/<slug>/BUG.md` § Verification.

## Docs accuracy
<!-- Any branch whose diff touches {{DOC_PATHS}}. Omit otherwise. -->
<!-- Inline the findings — the PR body is the durable record for this gate. -->

- Score: 9/10 (PASS) — 14 claims audited across 2 files
- Findings: 1 PARTIAL — `<path>` › <heading>
- Compliance claims: none

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 6. Return the PR URL to the user
