---
name: fix-bug
description: |
  Structured bug-fix workflow: identify the issue, reproduce the defect,
  confirm it isn't already fixed on the base branch, capture the investigation in
  docs/bugs/<slug>/BUG.md, propose the fix and wait for developer approval,
  implement it, and gate on the bug-fix-verifier agent before PR. Use whenever
  the user wants to fix a bug, says "fix bug", "bug fix", "debug this issue",
  "work on bug <key>", "/fix-bug", or is picking up a bug-type issue. Prefer
  this over /plan-feature for bugs — bugs don't have wireframes or acceptance
  criteria, they have "does the defect still reproduce?". This skill is the
  bug-side analogue of /plan-feature + /implement-plan collapsed into one
  lighter flow.
---

# Fix Bug

End-to-end bug-fix workflow. Lighter than `/plan-feature`: bugs don't need
interrogation, wireframes, task breakdown, or acceptance criteria — just a
confirmed reproduction, a root cause, an approved fix, and proof the fix held.

If a bug touches multiple domains with non-trivial design work (e.g. a race
condition that reveals a missing synchronisation primitive), promote it to
`/plan-feature` instead — the extra structure is worth it.

**Path 3b carve-outs.** Mechanical fixes (typo / off-by-one / null-deref
with a stack trace) skip the hypothesis-ranking ceremony in Phase 6 and
the post-mortem prompt in Phase 10. Carve-out details live inline in
those phases.

## Phase 0: Parse arguments

The developer may pass an issue key, an issue URL, or nothing.

**Issue key ≠ issue ID.** A key like `PROJ-0343` does NOT mean the database ID is
343 — never extract the number from a key and use it as an ID.

If no argument, auto-detect from the current branch — branches from
`/prepare-issue` typically look like `<KEY>-<slug>`. If the branch has no key,
ask which issue this is.

## Phase 1: Fetch the issue

Read the issue from your project's issue tracker (Linear, Jira, Kendo,
GitHub Issues, etc.). Keep in memory:

- **id**, **key**, **title**
- **type** — must be a bug. If it's a feature or task, stop and point the user
  at `/plan-feature`.
- **description**, **comments**, **attachments**

Note any existing **branch links** — a branch may already exist.

## Phase 2: Branch guard

This skill does **not** create branches — that's `/prepare-issue`'s job (or
`/newbranch` for projects without an issue tracker).

| Branch state | Action |
|---|---|
| On the base branch (e.g. `main`, `development`) | Stop. Tell the user to run `/prepare-issue <KEY>` or `/newbranch`. |
| Branch name contains the issue key | Proceed. |
| Any other branch | Stop. Ask if this is the right branch; if not, point at `/prepare-issue`. |

Hard stop — do not silently create a branch from here. The developer made a
choice at branch-creation time (primary vs. worktree, existing branch vs.
new) and this skill must not undo it.

## Phase 3: Capture a verifiable repro

First, read the code paths the bug touches — route → controller → service →
model on the backend, page → component → store on the frontend. You can't
pick a repro path without knowing what the feature is supposed to do.

Before picking a path, validate the issue's *Expected behaviour* / *Steps
to reproduce* section against the feature it touches — reporter writes
user-language and code encodes maintainer-language, so contradictions are
common. The validation rules and the contradiction-surfacing prompt live in
[references/repro-paths.md](references/repro-paths.md). Only after the
developer confirms the canonical model do you pick a path.

Every fix needs **something executable or describable that demonstrates the
defect** — that's what Phase 8's verifier checks against.

| Situation | Path |
|---|---|
| Stack trace / error log / clearly-broken line + mechanical fix | **3b** |
| "It's broken somewhere around X" — need to pin down behaviour | **3a** |
| Visual glitch, race condition, keyboard timing, browser-specific | **3c** |
| Report says "it's broken" with no specifics | Ask for more context — don't guess |

Path details — when each applies, what to write into BUG.md's "Reproduction
Steps", and the "cannot reproduce" stop condition — live in
[references/repro-paths.md](references/repro-paths.md). Load that file once
you've picked the path.

## Phase 4: Check if already fixed on the base branch

Before writing a fix, verify the bug still exists on the base branch
(`main`, `development`, etc.). Your branch may have diverged and a colleague
may have already fixed it.

- **Failing test (3a):** stash your test, `git fetch origin <base>`,
  check out the file(s) under test from `origin/<base>`
  (`git checkout origin/<base> -- <path>`), un-stash, run. Reset
  afterwards.
- **Clear diagnosis (3b) or manual (3c):** `git log origin/<base> -- <path>`
  for recent fix-language commits. If line numbers / typos already differ on
  the base branch, read the diff and confirm.

If the bug doesn't reproduce on the base branch, stop. Tell the user which
commit appears to have fixed it (link to the PR if you can find it) and
suggest merging the base branch in instead of writing a duplicate fix.

## Phase 5: Create docs/bugs/<slug>/BUG.md

Use the same naming as plans: `docs/bugs/<KEY>-<short-slug>/`. The slug is
2-5 words of kebab-case summarising the defect, not a copy of the title.

Write `BUG.md` using the template at
[references/bug-md-template.md](references/bug-md-template.md). Fill
**Problem** and **Reproduction Steps** now from your Phase 3 work; leave
**Root Cause**, **Chosen Approach**, **Fix**, and **Verification** empty —
they get filled as you progress. Set Status: `Investigating`.

## Phase 6: Diagnose & propose solution

Explain the bug to the developer and get explicit approval before any
shipping code moves. **No shipping code is edited in this phase** — only
tagged debug instrumentation. The gate exists to catch a wrong diagnosis
or a wrong choice of fix before the diff starts growing.

The mechanics live in
[references/diagnose-and-propose.md](references/diagnose-and-propose.md):

- **Generate hypotheses** (3-5 ranked, falsifiable) — **skip for path 3b**
- **Pin down root cause** and write 2-4 sentences into BUG.md, citing
  `file:line`. Update Status to `Diagnosed`.
- **Debug instrumentation hygiene** — tag temporary logs with a
  `[DEBUG-xxxx]` 4-hex prefix so cleanup is one grep.
- **Decompose the fix surface** into settled vs. ambiguous sub-concerns
  before listing candidates.
- **Explain and propose** — bug summary, root cause, candidates with
  trade-offs, recommendation. Cap at 4 candidates.
- **Get acceptance via `AskUserQuestion`** — clickable options, plus the
  rejection-recovery rule for two consecutive dismissals.

For Path 3b this whole phase collapses to a single short message — don't
ceremonialise a typo into a four-paragraph proposal.

Once a candidate is picked, write a one-liner into BUG.md's **Chosen
Approach**, then proceed to Phase 7.

## Phase 7: Implement the fix

Normal implementation loop, using the **Chosen Approach** from Phase 6.

- **Stick to the chosen approach.** New evidence that contradicts the
  diagnosis or makes the approach unworkable means stop, update Root Cause,
  return to Phase 6 with a fresh proposal, re-ask. Don't quietly switch
  mid-fix.
- **Keep the diff minimal.** A bug fix is not a cleanup pass. Resist
  renaming variables, deleting comments, or refactoring helpers in the same
  diff — small fixes are cheap to review and cheap to revert. Spotted
  issues go in BUG.md Notes / Follow-ups.
- **Run your repro** — the failing test should now pass, manual steps
  should now behave correctly.
- **Run the narrow domain test suite** for the area you changed.
- **Run `/ci --quick`** (or equivalent lint + types check) before declaring
  done.

Update BUG.md as you go: fill in **Fix**, change Status to `Fixing`, then
to `Verified` only after Phase 8 passes.

## Phase 8: Spawn bug-fix-verifier

Spawn the `bug-fix-verifier` agent — it has no context from this
conversation and works purely from BUG.md and the diff. It confirms the bug
is gone; it doesn't re-plan or re-scope.

```
Agent({
  subagent_type: "bug-fix-verifier",
  prompt: `Verify the bug fix on this branch.

Bug directory: docs/bugs/<slug>/

Read BUG.md, re-run the repro against HEAD, confirm the bug no longer
reproduces, and glance at touched files for obvious regressions. Write
your verdict into the BUG.md Verification section and report back with
a score (1-10). Threshold: 7.`
})
```

- **Score ≥ 7 / PASS** — proceed to Phase 9. Update Status to `Verified`.
- **Score < 7 / FAIL** — fix what the verifier found, re-run your repro,
  re-spawn. Don't hand off to `/pr` until ≥ 7. Shipping a "fix" that still
  reproduces is worse than shipping no fix — it erodes trust in the issue
  tracker.

If the verifier can't run the repro for environmental reasons (missing
service, missing data), surface it to the user — don't lower the threshold.

## Phase 9: Hand off to /pr

Run `/pr`. It will push, post the standard feedback comment on the
linked issue, and skip the `/review-branch` handoff (bug fixes are gated by
`bug-fix-verifier`, not by `acceptance-reviewer` + `simplicity-reviewer`).
If `/pr` still asks for a review handoff because it can't find
`docs/plans/<slug>/`, answer "no" — bugs live under `docs/bugs/`, and the
verifier verdict in BUG.md is the gate.

PR title names the defect (`fix: modal backdrop sticks after escape during
open animation`) rather than the issue key alone. PR body cites the issue
key plus a one-paragraph summary lifted from BUG.md's Fix section so
reviewers can grasp the change without opening the file.

## Phase 10: Post-mortem prompt (optional)

Once `/pr` is open and the verifier has signed off, you have more
information than when Phase 3 started. Spend 30 seconds asking: **what
would have prevented this bug?**

If the answer is architectural — no good test seam (flagged in BUG.md
Notes), tangled callers, hidden coupling, a class of bug that keeps
recurring at the same boundary — surface it via `AskUserQuestion`:

> Would an architecture-improvement pass help here? Reason: `<one specific
> line — e.g. "no correct seam for the regression test" or "third null-deref
> at the controller→action boundary this quarter">`.

If "yes," hand off with the specific pointer — an architecture skill (if the
project has one) works best with a concrete starting point, not "improve
something."

**Skip this phase entirely for path 3b mechanical fixes** (typos,
off-by-ones, missing null checks). Asking after every trivial fix turns
the prompt into noise the developer learns to ignore. Reserve it for
fixes where the diagnosis surfaced a structural smell.
