---
name: implement-plan
description: |
  Implement a feature directly from PLAN.md and DECISIONS.md without a TASKS.md breakdown.
  Use this for smaller plans where the plan's Approach section is already a good enough
  roadmap and a separate task file would be overkill. Loads the full plan context
  (goal, decisions, scope, approach, acceptance criteria, wireframes), executes the work
  end-to-end with TDD discipline, runs verification and the acceptance-reviewer agent,
  then captures learnings in IMPLEMENTATION.md so future sessions can resume.
  Trigger on: "implement the plan", "implement plan", "build this plan", "execute the plan",
  "/implement-plan", "ship this plan", "just do the plan", or whenever the user wants to
  build a feature straight from a plan document without writing TASKS.md first.
  Prefer /next when TASKS.md already exists in the plan directory.
---

# Implement Plan

Execute a feature plan end-to-end without a TASKS.md intermediary. Built for smaller plans where
the Approach section in PLAN.md already gives enough structure that a separate task breakdown
would be busywork.

This skill is the sibling of `/next`. The two share most of their machinery — context recovery,
testing-skill loading, TDD ordering, verification, acceptance review, learnings capture — but
diverge on iteration shape: `/next` walks a checklist, this one walks a plan.

## When to use this vs. /next

| Situation | Use |
|-----------|-----|
| TASKS.md already exists in the plan dir | `/next` (don't re-plan; execute the existing breakdown) |
| Plan is small (~5 or fewer Approach steps, single domain) | `/implement-plan` |
| Plan touches many files across multiple layers, will span several commits | `/task-writer` first, then `/next` |
| Plan has no PLAN.md at all | Stop. Run `/plan-feature` first. |

If unsure, err toward `/implement-plan` for tight focused changes and `/task-writer` → `/next`
for anything that genuinely benefits from per-task acceptance gating.

## Step 1: Locate the plan directory

Derive the plan directory from the current git branch:

1. Run `git branch --show-current`
2. Strip prefix up to and including the first `/` (e.g. `claude/` → removed, `feature/` → removed)
3. Strip any random suffix — e.g. a trailing `-XXXXX` segment where X is alphanumeric
4. Look for `docs/plans/<result>/PLAN.md`
5. If not found, ask the user where the plan lives — don't guess

**Example:** Branch `PROJ-0461-listeners-apply-payload-directly` → directory
`PROJ-0461-listeners-apply-payload-directly` → file
`docs/plans/PROJ-0461-listeners-apply-payload-directly/PLAN.md`

If you find a `TASKS.md` next to PLAN.md, **stop and tell the user** — they probably want `/next`,
not this skill. Confirm before continuing.

## Step 2: Load the full plan context

Read every plan document that exists in the directory. Each one carries information the others
intentionally omit:

| File | Why it matters |
|------|---------------|
| `PLAN.md` | The contract — goal, scope (in/out), approach, acceptance criteria, files touched |
| `DECISIONS.md` | The reasoning — alternatives rejected, tradeoffs, why the plan looks the way it does |
| `WIREFRAMES.md` | The UI spec — screen layouts, design tokens, component refs (only if the feature has UI) |
| `IMPLEMENTATION.md` | Prior progress — only present if a previous session already did partial work |

If `IMPLEMENTATION.md` exists, read it first and report what's already done before redoing
anything. Resume rather than restart.

After loading, read the files referenced in PLAN.md's Approach section so you have a working
mental model of the code you'll be modifying — not just the file paths but the surrounding
patterns. The plan tells you *what*; the code tells you *how it currently is*.

## Step 3: Show your understanding

Before writing any code, send the user a short orientation message — under 8 lines — covering:

- The goal in one sentence
- The Approach steps as a numbered list (paraphrased, not copy-pasted)
- Anything in the plan that looks ambiguous or stale relative to the current code

This is a cheap checkpoint. If your understanding is off, the user catches it now instead of
after you've written tests against the wrong behaviour.

If anything looks wrong, **ask before proceeding**. If it all looks fine, proceed without
waiting for an explicit "yes" — the user can interrupt.

## Step 4: Load the right testing skill — mandatory if one exists

**Before writing or modifying any test code**, invoke the project's testing skill if one
exists. These skills carry conventions (mock organization, AAA format, coverage rules, file
structure) that aren't in the plan and aren't obvious from existing tests. Look in
`.claude/skills/` for any skill whose name matches a testing convention (e.g. unit-test,
integration-test, frontend-test).

If the plan touches multiple layers, load the testing skill for each layer.

If the project doesn't have testing skills, fall back to reading existing tests in the area
you're touching and matching their conventions.

## Step 5: Execute the Approach

Walk the plan's Approach steps in order. For each step:

- **Tests first** — if the step adds or changes behaviour, write the failing test before the
  implementation. The plan's acceptance criteria are your spec; translate them into assertions.
- **Stay inside the In Scope list** — if you discover something that needs doing but is in
  Out of Scope (or unmentioned), note it for later rather than expanding the change. Scope creep
  is the #1 way small plans become big ones.
- **Honour the decisions** — DECISIONS.md exists because the team already evaluated alternatives.
  Don't re-litigate them mid-implementation; if a decision genuinely no longer fits, surface it
  to the user as a question, don't silently deviate.
- **Keep commits in mind** — if the Approach has natural breakpoints (e.g. "rename helper" then
  "rewire callers"), pause at each one. The user may want to commit before continuing.

For UI work, also check WIREFRAMES.md as you build each screen — token names, component
variants, layout structure all live there.

## Step 6: Verify

Once the implementation is in place, run the verification gauntlet in order of cost:

1. `/ci --quick` — lint + types (cheap, fast, catches the obvious stuff)
2. Domain-narrow tests for the area you touched (use the project's single-run / pipeline
   variant, not watch mode)
3. Anything the plan calls out under a "Verify" or "Acceptance Criteria" section that you can
   run yourself

Don't run the full CI suite locally — CI runs that on the PR. Local runs are for the
narrow domain you changed.

For frontend changes, also drive the feature in a real browser via `/playwright-browser` before
declaring done. Code that compiles and tests-green can still be visually broken.

## Step 7: Acceptance review

Spawn the **acceptance-reviewer** agent in PR mode against the full plan. Because there's no
per-task scoping, you check everything in one pass:

```
Agent({
  subagent_type: "acceptance-reviewer",
  prompt: `Review the implemented work against the full plan.

Mode: pr
Plan directory: docs/plans/<slug>/
Branch diff: this branch vs <base-branch>

Check every acceptance criterion in PLAN.md against the diff. Report PASS/PARTIAL/FAIL/SKIP
per criterion. If WIREFRAMES.md exists, verify the UI matches.`
})
```

**What to do with the result:**

- **Score 7+ / all PASS or SKIP** — Proceed to Step 8.
- **Score below 7 / any FAIL** — Fix the issues the reviewer identified, re-run verification
  (Step 6), then re-spawn the reviewer. Do not write IMPLEMENTATION.md or suggest a commit
  until the score is 7 or above. The threshold exists because shipping below it has historically
  meant follow-up work nobody scheduled.

## Step 8: Capture learnings to IMPLEMENTATION.md

Create or append `IMPLEMENTATION.md` in the plan directory. This file is what makes the next
session (or the next dev) able to resume without re-reading the diff.

Use this structure:

```markdown
# Implementation Log

## YYYY-MM-DD — <one-line summary of this session's work>

**Acceptance Score:** N/10 (from acceptance-reviewer)

**Key Changes:**
- Created `path/to/new/file.ts`
- Modified `path/to/existing/file.vue` — replaced X with Y
- Deleted `path/to/removed/file.ts` — superseded by the new helper

**Learnings:**
- Non-obvious thing discovered during implementation
- Edge case that wasn't in the plan but came up
- Pattern in the existing code that's worth knowing for the next change in this area

**Deviations from plan:**
- (Empty if none — write this section even when empty so future readers know nothing was skipped)

**Follow-ups noted but not done:**
- Anything you spotted that's out of scope but worth a future ticket
```

Write meaningful learnings — things that weren't obvious from PLAN.md, edge cases you hit,
patterns you discovered. "It worked" is not a learning. "The drag buffer needed to be a Map
because the existing Set lost the most-recent-update on rapid drops" is a learning.

If `IMPLEMENTATION.md` already existed (resumed session), append a new dated section rather than
overwriting.

## Step 9: Report and suggest commit

Summarise what shipped and offer to commit:

```
Implemented <KEY> — <one-sentence summary>
Acceptance score: 9/10. IMPLEMENTATION.md updated.

Suggest committing now. Want me to /commit?
```

If the user wants to keep iterating (e.g. spotted something during review), loop back to the
relevant earlier step rather than restarting the whole skill.
