---
name: fix-bug
description: |
  Structured bug-fix workflow: identify the issue, reproduce the defect,
  confirm it isn't already fixed on the base branch, capture the investigation in
  docs/bugs/<slug>/BUG.md, propose the fix and wait for developer approval,
  implement it, gate on the bug-fix-verifier agent, and gate styling/animation
  fixes on manual browser confirmation before PR. Use whenever the user wants
  to fix a bug, says "fix bug", "bug fix", "debug this issue", "work on bug
  <key>", "/fix-bug", or is picking up a bug-type issue. Prefer this over
  /plan-feature for bugs — bugs don't have wireframes or acceptance criteria,
  they have "does the defect still reproduce?". This skill is the bug-side
  analogue of /plan-feature + /implement-plan collapsed into one lighter flow.
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
the post-mortem prompt in Phase 10 unconditionally. Phase 8.5's
visual-risk gate is **not** unconditionally skipped for 3b — it still
fires if the diff touches styling. Carve-out details live inline in
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

**If diagnosis reveals it isn't actually a bug, or a duplicate of an
already-fixed/already-tracked defect** — stop here. Don't propose a
fix for a non-bug. Explain the finding to the developer (cite
`file:line` or the duplicate issue) and confirm via `AskUserQuestion`:

> Diagnosis suggests this isn't a bug — `<one-line reason, e.g. "the
> feature already handles this via gesture Z" or "duplicate of
> <KEY>, already fixed on the base branch">`. Abandon this branch?
> - **Yes, abandon** — update Status to `Abandoned`, note why in Notes
>   / Follow-ups, and stop the workflow. Do not proceed to Phase 7 or
>   `/pr`.
> - **No, the diagnosis is wrong / keep investigating** — stay in
>   Phase 6, revise Root Cause with the developer's correction.

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
- **Trust the hooks for lint and types.** If the repo runs lint at commit
  and type checks at push, a failing hook means fix the underlying issue
  and re-commit/re-push — don't pre-emptively rerun those checks here. If
  the repo has no such hooks, run its lint + types check before declaring
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

- **Score ≥ 7 AND Verdict reads `PASS`** (plain, or the literal `PASS
  (requires developer confirmation)` that path-3c reproductions get —
  Phase 8.5 is what resolves that string, so treat it as a pass here
  too) — check Phase 8.5's visual-risk gate, then proceed to Phase 9.
  Update Status to `Verified`.
- **Score < 7, OR Verdict reads `PARTIAL`/`FAIL`, OR "Required fixes
  before PR" is non-empty** — fix what the verifier found, re-run your
  repro, re-spawn. Don't hand off to `/pr` until the verdict reads a
  clean `PASS` (in either form above) with no outstanding required
  fixes. The score and the verdict are independently-written fields; a
  high score doesn't override a verdict or a required-fix list that
  says otherwise. Shipping a "fix" that still reproduces — or one the
  verifier flagged but wasn't waved through — is worse than shipping no
  fix — it erodes trust in the issue tracker.

If the verifier can't run the repro for environmental reasons (missing
service, missing data), surface it to the user — don't lower the threshold.

## Phase 8.5: Visual-risk gate

Claude cannot judge rendered styling or animation from source — only
describe what the code should do. A passing verifier score does not mean
the fix *looks* right.

Trigger this gate if either is true:

- `git diff origin/<base>...HEAD -- <component and stylesheet globs>`
  (e.g. `'*.vue' '*.tsx' '*.css' '*.scss'`) — read the actual diff
  content, not `--stat` (a path + line-count summary can't show whether
  the changed lines are styling) — contains `<style>` blocks, class
  bindings, utility classes, or animation/transition properties
  (`transition`, `animate-`, `@keyframes`, `duration-`, `ease-`), beyond
  a trivial one-line tweak.
- Reproduction Steps used **path 3c** (visual glitch / animation /
  browser-specific) — `bug-fix-verifier`'s 3c walkthrough only ever
  reaches "PASS (requires developer confirmation)" for these; it cannot
  close the loop itself (see `bug-fix-verifier.md` Step 2, "Manual steps
  (3c)").

Skip this gate when neither trigger condition above fired — path alone
(3a/3b/3c) doesn't determine visual risk, diff content does. A 3b fix
diagnosed from a stack trace or null-check stays exempt because it never
touches styling; a 3b fix for a visible typo still trips the first
trigger and still needs eyes on it.

When triggered, stop before Phase 9 and ask via `AskUserQuestion`. Word the
question around confirming the defect is gone, not just "does it render" —
path 3c also covers races and cross-tab timing, which have nothing to do
with rendering:

> This change touches styling, animation, or something else I can only
> confirm by eye. Have you re-run the reproduction steps and confirmed
> the bug is actually fixed?
> - **Yes, verified — proceed to /pr**
> - **Run a browser-driving skill or the Playwright MCP first** — good
>   for catching visual issues via screenshots, but take a look yourself
>   too; it won't catch timing or race-condition problems
> - **No — hold off, I'll check manually**

Each answer resolves BUG.md's `## Verification` section before Phase 9 can
run — a path-3c fix otherwise carries the verifier's literal `PASS
(requires developer confirmation)` string, which `/pr`'s gate does not
recognise as a plain `PASS`:

- **Yes** — update **Verdict:** to plain `PASS`. This is what actually
  unblocks `/pr`'s gate (see [`pr/SKILL.md`](../pr/SKILL.md) § Bug
  branches) — confirming here without rewriting the Verdict leaves the
  old string in place and `/pr` would ask for an override anyway.
- **Run a browser-driving skill or the Playwright MCP first** — after it
  finishes, re-ask the same question above. Don't fall through to Phase 9
  on completion alone; a screenshot is not a "Yes."
- **No — hold off** — stop the workflow here, do not hand off to `/pr`.
  Update **Verdict:** to `BLOCKED — pending manual browser confirmation`
  and set **Status:** back to `Fixing`. `/pr`'s bug-branch gate reads this
  section directly, so this is what actually stops a later `/pr` run in a
  fresh session — a note in Notes / Follow-ups alone would not.

## Phase 9: Hand off to /pr

Run `/pr`. It will push, post the standard feedback comment on the
linked issue, and embed `bug-fix-verifier`'s verdict from BUG.md's
`## Verification` section as the gate — bug fixes are gated by the
verifier, not by the pre-PR reviewer pair, so `/pr` will not ask for a
`/review-branch` handoff on a bug branch.

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
