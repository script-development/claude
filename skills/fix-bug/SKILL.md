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

### 3.0 Validate the issue's expected behaviour against the existing feature

Before picking a path, read the issue's *Expected behaviour* / *Steps to
reproduce* section against the feature it touches. The reporter writes
user-language; the code encodes maintainer-language. Common gaps:

- A bullet says "X should always do Y" but the feature already supports a
  Y-overriding gesture (e.g. multi-select). The bullet may be the reporter's
  *symptom* description, not a behaviour contract.
- A bullet uses a name that resembles a code identifier but means something
  different in the user's head (e.g. "selected report" in the issue vs.
  `selectedReports` prop in code).
- Two bullets contradict each other under realistic feature usage.

If you spot any of these, **do not write failing tests yet**. Surface the
contradiction to the developer in plain prose and ask which model is
canonical:

> The issue says *"X should always do Y"*, but the feature uses gesture Z
> which would override Y in case W. Is bullet 3 the desired behaviour, or
> the reporter's symptom-language?

Only after the developer confirms the canonical model, pick a path and
write tests. Otherwise the failing tests become contractual on a contract
the developer never signed off on, and Phase 6 has to walk back the
assertions.

Every fix needs **something executable or describable that demonstrates the
defect** — that's what Phase 8's verifier checks against. Three valid paths:

| Situation | Path |
|---|---|
| Stack trace / error log / clearly-broken line + mechanical fix | **3b** |
| "It's broken somewhere around X" — need to pin down behaviour | **3a** |
| Visual glitch, race condition, keyboard timing, browser-specific | **3c** |
| Report says "it's broken" with no specifics | Ask for more context — don't guess |

### 3a. Failing test first (default)

Write a test that fails on HEAD for the exact reason the user reports, then
passes after the fix. Use this when the mechanism is fuzzy — writing the
test forces you to pin down the expected behaviour before patching. If the
project has a domain-specific testing skill, load it before writing the test.

The same test becomes the regression gate in Phase 8. Once the fix makes it
green, the bug cannot silently come back.

### 3b. Test alongside fix (clear diagnosis)

When the diagnosis is already done *for* you — stack trace pointing at a
line, visible typo, null deref staring at you in a recent diff — a
failing-test dance is ceremony. Skip it and ship the regression test in the
same commit as the fix.

**Use only if all of these hold:** the issue includes a stack trace / error
log / concrete file:line OR the defect is a self-evident
typo/off-by-one/missing null-check; the fix is mechanical (no design
judgment); the regression test ships with the fix (not before).

In BUG.md's Reproduction Steps, record diagnosis evidence in place of a
failing test:

> **Diagnosis evidence:** `NullPointerException` at
> `CreateIssueAction.php:87` — thrown when `$project` is null because the
> caller sends a deleted project ID. No reproduction ceremony; fix +
> regression test ship together.

### 3c. Manual reproduction (visual / race / cross-tab)

Visual glitches, keyboard interactions across tabs, races only seen in real
browsers — describe the steps in BUG.md and ask the developer to confirm
manually before fixing:

> **Repro:** open project settings → team, click Invite, press Escape
> mid-animation. **Expected:** modal closes cleanly. **Actual:** backdrop
> stays. Confirm?

Do **not** automate a browser to reproduce — `/playwright-browser` is for
verifying finished UI, not reproducing defects.

**If you cannot reproduce or diagnose at all** — stop. Ask for more context
(steps, browser, tenant, role, data state). Don't proceed on "probably this".

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

Write `BUG.md`:

```markdown
# <KEY>: <short bug title>

**Date:** <YYYY-MM-DD>
**Issue:** [<KEY>](link to issue)
**Status:** Investigating | Diagnosed | Fixing | Verified | Abandoned

## Problem
<2-4 sentences on the user-visible defect. Pulled from the issue's Problem
section, restated in your own words so this file reads independently.>

## Reproduction Steps
<Use exactly one of the headings below, matching the path you took.>

**Failing test (3a):** `path/to/test.spec.ts::<test name>`
Run with: `<exact command>`

**— or —**

**Diagnosis evidence (3b):**
- Stack trace / error log line: `<pasted trace>`
- Or concrete file:line reference: `<path:line>`
- Regression test that will ship with the fix: `<path/to/test.spec.ts::<test name>>`

**— or —**

**Manual steps (3c):**
1. <step>
2. <step>
3. <expected vs. actual>

## Root Cause
<Filled in Phase 6. 2-4 sentences on why the defect happens. Cite file:line
for the code at fault. Describe the mechanism, not the symptom.>

## Chosen Approach
<Filled at the end of Phase 6 once the developer accepts a candidate.
One line naming the picked solution — alternatives stay in chat, not here.>

## Fix
<Filled in Phase 7. What changed, in what files, why that addresses the
root cause. Not a diff dump — a short explanation a future reader can grasp
without opening the PR.>

## Verification
<Filled by bug-fix-verifier in Phase 8. Score, verdict, evidence. Empty
until the agent writes it.>

## Notes / Follow-ups
<Adjacent issues, missing tests elsewhere, refactors worth doing later.
Empty is fine.>
```

Write Problem and Reproduction now. Leave Root Cause, Chosen Approach, Fix,
and Verification empty — they get filled as you progress. Set Status:
`Investigating`.

## Phase 6: Diagnose & propose solution

Explain the bug to the developer and get explicit approval before any
shipping code moves. **No shipping code is edited in this phase** — only
tagged debug instrumentation (see "Debug instrumentation hygiene" below).
The gate exists to catch a wrong diagnosis or a wrong choice of fix before
the diff starts growing.

### Generate hypotheses (skip for path 3b)

Before naming a single root cause, generate **3-5 ranked hypotheses** about
what's causing the defect. Anchoring on the first plausible idea is the
single most common debugging failure — multiple hypotheses force you to
actually compare instead of confirming.

Each hypothesis must be **falsifiable**:

> Format: "If `<X>` is the cause, then `<changing Y>` makes the bug
> disappear / `<changing Z>` makes it worse."

If you cannot state the prediction, the hypothesis is a vibe — discard or
sharpen it.

When the ranking is genuinely ambiguous and the developer is around,
surface the ranked list via `AskUserQuestion` before instrumenting — they
often have domain knowledge that re-ranks instantly ("we just changed #3
last week") or know what's already been ruled out. Don't block on it;
proceed with your top pick if no answer.

Skip this step for path 3b (stack trace + mechanical fix) — the trace
already tells you the cause; ranking strawmen wastes effort.

### Pin down the root cause

Read the code paths again with the repro evidence and the hypothesis
ranking in hand. Identify the mechanism, not the symptom. Write 2-4
sentences into BUG.md's **Root Cause**, citing `file:line`. If you can't
write a coherent root cause, you don't understand the bug yet — go back to
Phase 3 or sharpen your hypotheses.

Update BUG.md Status to `Diagnosed`.

### Debug instrumentation hygiene

If a hypothesis needs probes (extra logs, dumping a value, breakpoint
inspection), prefer a debugger / REPL / inline dump at a breakpoint when
the env supports it — one inspection beats ten logs. When you do add
temporary logs, **tag them** with a fresh 4-hex prefix per investigation:

```
log.info('[DEBUG-a4f2] handler reached', { id })
console.log('[DEBUG-a4f2]', 'broadcast payload', payload)
```

Cleanup at the end is then a single `grep -rn '\[DEBUG-a4f2\]'` across the
source tree — every hit is a leak. Untagged debug logs survive into PRs
and pollute production output; tagged logs die together. Run the grep
before Phase 8 — any leaked `[DEBUG-` in the diff is obvious regression
noise to the verifier and to human reviewers.

### Decompose the fix surface

Before writing candidates, list the **independent sub-concerns** the fix has
to address. For each, classify:

- **Settled** — every reasonable implementer would do the same thing. One
  line, no debate. (e.g. "remove dismissed id from set" — trivial regardless
  of the click-side decision.)
- **Ambiguous** — multiple defensible behaviours exist; the developer needs
  to pick. (e.g. "what should clicking do to the multi-select?")

Only **ambiguous** sub-concerns go through the candidate matrix below.
Settled sub-concerns are stated up front as "we're going to do X — anyone
object?" and implemented in Phase 7 without ceremony.

Bundling settled sub-concerns into the matrix makes the trivial part look
hard and dilutes the actual decision. If your candidate list contains
entries that all agree on most points, decompose first.

### Explain and propose

Post a chat message with this shape:

> **Bug:** <one-sentence symptom restatement>
> **Root cause:** <2-3 sentences on the mechanism, citing file:line>
> **Why now:** <if relevant — recent commit, edge case, race>

Then lay out every reasonable fix. Each candidate gets:

- **Name** — short label (e.g. "Guard at the boundary", "Fix the typo")
- **Change** — one sentence on what code moves
- **Trade-off** — what this approach costs (scope, complexity, risk)

Three rules:

1. **Always propose at least one** — even when obvious, name it explicitly
   so the developer can object before code changes.
2. **Don't invent fake alternatives.** Bugs with one good answer (typo,
   off-by-one, missing null check) get one candidate: "Single candidate —
   the typo at `Foo.php:87` is the only place that branch is reachable."
   Don't pad with strawmen to look thorough.
3. **Recommend one** when there are 2+ real candidates, with a one-line
   why.

Cap candidates at 4. More than that means the diagnosis isn't tight enough
— go back to root cause.

For Path 3b (stack-trace + mechanical fix), this collapses to a single
short message — don't ceremonialise a typo into a four-paragraph proposal.

### Get acceptance via AskUserQuestion

Present as a clickable question — never ask the developer to type. Use
`AskUserQuestion` with one option per candidate.

- **Single candidate:** "Proceed with this fix" / "No, let's discuss"
- **Multiple:** one option per candidate, plus "Other / discuss"

Keep labels short (a few words) — the trade-offs already live in the chat
message above the question, so labels don't need to repeat them.

If the developer picks "discuss" or "Other", iterate the proposal and
re-ask. Don't start coding. If the diagnosis itself was wrong, update Root
Cause before re-asking.

**If a question is rejected with a clarify-request** (i.e. the developer
dismisses the AskUserQuestion entirely rather than picking an option): drop
the AskUserQuestion shape on the next turn. Ask in plain prose: *"What would
you like to clarify about the candidates?"* The rejection signal means the
question *framing* is wrong — re-posing with extra options or rearranged
labels usually makes it worse. Two consecutive AskUserQuestion rejections
is a strong signal the diagnosis itself drifted; return to Root Cause and
re-pin before asking again.

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
