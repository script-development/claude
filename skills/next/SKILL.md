---
name: next
description: |
  Continue working through a TASKS.md file — find the next uncompleted task, execute it,
  and mark it done. Use this skill whenever the user wants to continue implementation work, pick up
  where they left off, resume after /clear, or work through a task list. Trigger on: "next task",
  "continue working", "keep going", "what's next", "pick up where I left off", "resume work",
  "next step", or any variant of wanting to progress through planned tasks.
---

# Next Task

Continue working through a TASKS.md file: locate it, find the next uncompleted task, execute it,
and mark it done with learnings.

## Step 1: Locate TASKS.md

Search for the task file:

1. Check the current git branch name for clues (issue keys, feature names)
2. Look for `TASKS.md` in common locations:
   - Repository root
   - `docs/plans/<branch-name-or-issue>/TASKS.md`
   - Any `docs/plans/*/TASKS.md` that matches the branch
3. If not found, ask the user where their task file is

## Step 2: Show progress and find next task

Read the TASKS.md file and report a quick progress summary:

```
Progress: 3/7 tasks complete — starting task 4
```

Find the first task not marked with `[x]`. If all tasks are complete, summarize the work done and
ask if there's anything else needed.

## Step 3: Recover context

This is important when resuming after a `/clear` or at the start of a new session.

Read the task's context to understand:
- **Why** — The problem this task solves
- **What** — What needs to be built or changed
- **Key refs** — File paths to read as entry points
- **Watch out** — Edge cases and gotchas

Read the files mentioned in the task to build working understanding of the code you'll be
modifying. Also glance at the previous completed tasks to understand what's already been done.

If the task references decisions or a plan document, read those to understand the reasoning behind
the chosen approach.

## Step 4: Execute the task

### Follow the task's ordering

If tasks have specific ordering tags (like TDD `[RED]`/`[GREEN]` markers, or numbered sub-steps),
respect that ordering.

### Stay in scope

The task's scope and action items define what this task covers. Stay within those boundaries —
don't start work that belongs to a later task. If you discover something that needs doing but
isn't in the current task, note it for later rather than doing it now.

## Step 5: Verify before completing

After implementation, check if the task has verification steps. Run what you can (tests, linters,
type checks). Don't block on manual verification — flag those for the user.

## Step 6: Mark complete with metadata

Update the TASKS.md file:

1. Change `[ ]` to `[x]` on the task
2. Add completion metadata below the task's existing content:

```markdown
- [x] **4** Implement feature X
    - [existing task content...]
    - **Completed:** YYYY-MM-DD
    - **Learnings:**
        - Key insight discovered during implementation
        - Gotcha or edge case encountered
    - **Key Changes:**
        - Created `src/features/x/service.ts`
        - Modified `src/api/routes.ts`
    - **Notes:** Any important context for future tasks
```

Write meaningful learnings — things that weren't obvious from the task description, edge cases
you hit, patterns you discovered. These help future tasks and context recovery.

## Step 7: Report and suggest commit

Summarize what was done, then suggest committing the work as a natural checkpoint:

```
Done: task 4 — Implemented X with tests

Suggest committing before continuing. Want me to /commit?
```

If the user wants to continue, loop back to Step 2 for the next task.
