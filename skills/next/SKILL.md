---
name: next
description: |
  Continue working through TASKS.md — find the next uncompleted task, execute it with TDD flow,
  and mark it done. Use this skill whenever the user wants to continue implementation work, pick up
  where they left off, resume after /clear, or work through a task list. Trigger on: "next task",
  "continue working", "keep going", "what's next", "pick up where I left off", "resume work",
  "next step", or any variant of wanting to progress through planned tasks.
---

# Next Task

Continue working through a TASKS.md file: locate it, find the next uncompleted task, execute it
following TDD flow, and mark it done with learnings.

> **No TASKS.md, just PLAN.md + DECISIONS.md?** Use `/implement-plan` instead. It runs the same
> context-recovery / TDD / verification machinery against the plan directly, without expecting a
> per-task checklist.

> **Review runs once per branch, not per task.** Do not spawn reviewer agents after each task —
> per-task reviews burn tokens for near-zero signal (first-pass scores are 9-10 the vast majority
> of the time). The gate for a task is **verification** (tests + types + lint). Reviewers run
> once via `/review-branch` before `/pr`.

## Step 1: Locate TASKS.md

Derive the plan directory from the current git branch using the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md), then
look for `TASKS.md` inside it.

If the plan directory exists but has no `TASKS.md`, fall back to `TASKS.md` in the repository
root. If neither exists, ask the user where their task file is.

## Step 2: Show progress and find next task

Read the TASKS.md file and report a quick progress summary:

```
Progress: 3/7 tasks complete — starting 2.1
```

Find the first task not marked with `[x]`. If all tasks are complete, summarize the work done and
ask if there's anything else needed.

## Step 3: Recover context

This is important when resuming after a `/clear` or at the start of a new session — the Context
block in each task is specifically designed for this.

Read the task's **Context** section to understand:

- **Why** — The business problem this task solves
- **Architecture** — How it fits in, which patterns to follow
- **Key refs** — File paths and line numbers to read as entry points
- **Watch out** — Edge cases and gotchas to keep in mind

Read the files mentioned in **Key refs** and **Touches** to build working understanding of the
code you'll be modifying. Also glance at the previous completed tasks to understand what's
already been done in this feature.

If the task Context references decisions (e.g., "see D2"), read `DECISIONS.md` in the same plan
directory to understand the reasoning behind the chosen approach — especially which alternatives
were rejected and why.

## Step 4: Execute the task

### Follow TDD ordering

Tasks use `[RED]` and `[GREEN]` tags in their action items to indicate TDD flow:

- **[RED]** — Write tests first (they should fail initially)
- **[GREEN]** — Implement code to make the tests pass

Always execute [RED] items before [GREEN] items.

### Load testing skills before any test work

If the project provides a domain-specific testing skill, invoke it **before** writing or modifying
test code. These skills typically carry the project's mock organization, AAA conventions, coverage
requirements, and test file structure — none of which are obvious from existing tests.

If the project doesn't have a testing skill, fall back to reading 1-2 existing tests in the area
you're touching and matching their conventions.

### Use task scope as guardrails

The **Scope**, **Touches**, and **Action items** define what this task covers. Stay within those
boundaries — don't start work that belongs to a later task. If you discover something that needs
doing but isn't in the current task, note it for later rather than doing it now.

## Step 5: Verify before completing

After implementation, check if the task has a **"Verify before complete"** section. If it does,
remind the user about the verification checks and run the ones you can (CI commands, test
suites, type checkers). Don't block on manual verification steps — flag them for the user.

Common verification patterns:
- `/ci --quick` (or equivalent lint + types check)
- Narrowed/pipeline test commands for the area you touched (avoid full-suite watch mode)
- Coverage check if the project enforces a threshold

**Verification is the per-task gate.** Reviewer agents (acceptance, simplicity, silent-failure,
efficiency) no longer run per task — they run once against the full branch via `/review-branch`
before `/pr`.

## Step 6: Mark complete with metadata

Update the TASKS.md file:

1. Change `[ ]` to `[x]` on the task
2. Add completion metadata below the task's existing content:

```markdown
- [x] **N.1** Implement feature X
    - [existing task content...]
    - **Completed:** YYYY-MM-DD
    - **Learnings:**
        - Key insight discovered during implementation
        - Gotcha or edge case encountered
    - **Key Changes:**
        - Created `path/to/new/file.ts`
        - Modified `path/to/existing/file.ts`
    - **Notes:** Any important context for future tasks
```

Write meaningful learnings — things that weren't obvious from the task description, edge cases
you hit, patterns you discovered. These help future tasks and context recovery.

## Step 7: Report and suggest commit

Summarize what was done, then suggest committing the work as a natural checkpoint:

```
Done: 2.1 — Implemented X with tests

Suggest committing before continuing. Want me to /commit?
```

If the user wants to continue, loop back to Step 2 for the next task.
