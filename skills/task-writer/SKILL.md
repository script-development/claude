---
name: task-writer
description: |
  Task breakdown and TASKS.md management. Use when planning a new feature, breaking down work
  into implementation tasks, creating or updating TASKS.md, estimating effort, or organizing
  multi-step work into phases. Also use when translating a plan document into TASKS.md — includes
  systematic extraction checklist to ensure nothing is missed. Trigger on: feature breakdown,
  task planning, "write tasks for", "create TASKS.md", plan-to-tasks conversion, sprint planning,
  implementation ordering, or when the user mentions wanting to organize implementation steps.
---

# Task Writer

## Core Philosophy

**Feature-focused tasks:** Bundle related work (types, service, tests, integration) into one
logical unit. Split by integration boundaries, not by files.

## Plan Extraction Workflow

When working from an existing plan document, follow this systematic extraction process:

### Step 1: Build Complete Inventory

Read the plan and extract ALL items into these categories:

```markdown
## Extraction Inventory

### Code Changes

- [ ] Files to modify: [list every file mentioned]
- [ ] Files to create: [list new files]
- [ ] Database/schema changes: [migrations, schema updates]
- [ ] Type/interface changes: [type definitions, DTOs]

### Integration Points

- [ ] API endpoints: [new routes, modified controllers]
- [ ] Frontend-backend contracts: [request/response shapes]
- [ ] Route registrations: [where new routes wire in]

### UI/UX Specifications

- [ ] Page layouts: [new pages, modified views]
- [ ] Component behavior: [modals, forms, tables]
- [ ] User flows: [what user sees after each action]

### Error Handling

- [ ] Error scenarios: [list each from plan]
- [ ] User-facing messages: [error text, notifications]
- [ ] Validation rules: [input validation]

### Verification Requirements

- [ ] Manual test steps: [from plan's verification section]
- [ ] Edge cases to test: [race conditions, permissions, etc.]
- [ ] Success criteria: [how to know it works]
```

### Step 2: Map Inventory to Tasks

Group inventory items by **integration boundary**, not by file:

| Inventory Category | Maps To |
| --- | --- |
| Migrations + Models + Config | Infrastructure task (Phase 1) |
| Business logic + Tests | Core logic task (Phase 2) |
| API layer + Route tests | HTTP/API task (Phase 3) |
| UI components + State + Tests | Frontend task (Phase 4) |
| Error scenarios | → Task Context "Watch out" section |
| UI specs | → Task Context "Architecture" section |
| Verification steps | → Final manual verification task |

### Step 3: Verify Complete Coverage

Before finalizing, cross-check:

```markdown
## Coverage Check

- [ ] Every "Files to modify" appears in at least one task's Touches
- [ ] Every "Files to create" appears in at least one task's Touches
- [ ] Every error scenario from plan is in a task's "Watch out" or action items
- [ ] Every UI spec is captured in Context or verification
- [ ] Every verification step from plan is in the final verify task
```

---

## Task Sizing Rules

| Feature Size | Files | Task Count | How to Split |
| --- | --- | --- | --- |
| Small | 1-3 | 1 task | Don't split |
| Medium | 4-8 | 2-3 tasks | Core logic → Integration → Manual verify |
| Large | 8+ | 3-5 tasks | By integration boundary |

### Full-Stack Feature Split

For features spanning multiple layers, split by **integration boundary**:

```
Phase N: [Feature Name] (3-5 tasks)

- [ ] N.1 Infrastructure
      → Migrations, models, config, packages
      → Success: schema applied, types compile

- [ ] N.2 Business logic
      → Core logic, unit tests
      → Success: tests pass with full coverage

- [ ] N.3 API/HTTP layer
      → Controllers, routes, middleware, integration tests
      → Success: API tests pass

- [ ] N.4 Frontend implementation
      → Types, state, pages, components, tests
      → Success: frontend tests pass

- [ ] N.5 Code quality review
      → Review all changed code for reuse, quality, and efficiency
      → Fix any issues found

- [ ] N.6 Manual verification
      → Manual testing of the full feature
      → Success: feature works end-to-end
```

Skip phases that don't apply (e.g., skip backend phases for frontend-only work).

---

## Task Format

```markdown
### Phase N: Feature Name (X tasks)

**Goal:** One sentence describing what this phase delivers.

- [ ] **N.1** Implement [feature/layer]
    - **Context:** (REQUIRED - enables standalone task pickup)
        - **Why:** [Business problem this solves]
        - **Architecture:** [How it fits in, which pattern to follow]
        - **Key refs:** [Specific file:line references to understand entry points]
        - **Watch out:** [Edge cases, gotchas, things that aren't obvious]
    - **Scope:** Brief description of what's included
    - **Touches:** Key files (not exhaustive, just main ones)
    - **Action items:**
        - Write tests for [specific behavior 1]
        - Write tests for [specific behavior 2]
        - Implement [component] to make tests pass
        - Integrate into [existing code]
    - **Verify before complete:**
        - [ ] Tests pass
        - [ ] Lint/type checks pass
        - [ ] [Watch out item 1] - addressed by [how]
        - [ ] [Watch out item 2] - addressed by [how]
        - [ ] Integration: [specific check]
    - **Success:** [One-line summary of done state]

- [ ] **N.2** Manual verification
    - **Verify manually:** [What to test]
```

### Completion Metadata

When a task is completed, enrich it with what was learned:

```markdown
- [x] **N.1** Implement [feature/layer]
    ...existing content...
    - **Completed:** YYYY-MM-DD
    - **Learnings:**
        - [What was discovered during implementation that wasn't obvious]
        - [Gotchas that future tasks should know about]
    - **Key Changes:**
        - Modified `path/to/file.ts` — [what changed and why]
        - Created `path/to/new-file.py` — [purpose]
```

---

## Capturing Non-Code Requirements

Plans often contain specifications that aren't "write code for file X". Capture these:

### UI/UX Specifications

Put in **Architecture** or create dedicated subsection:

```markdown
- **Context:**
    - **Architecture:** Profile page shows a settings card:
        - Enabled state: green badge, "Disable" button
        - Disabled state: "Enable" button with setup wizard
```

### Error Handling

Put each scenario in **Watch out** or as testable action items:

```markdown
- **Watch out:**
    - Invalid input → show "Invalid input" error
    - Duplicate entry → show "Already exists" error
    - Missing permissions → redirect to access denied
```

### Verification Checklist

Put ALL verification steps from plan in the final verify task:

```markdown
- [ ] **N.5** Manual verification
    - **Verify manually:**
        1. Navigate to feature page → correct layout shown
        2. Submit valid form → success message, data saved
        3. Submit invalid form → validation errors displayed
        4. Check permissions — unauthorized user sees access denied
```

---

## What Goes IN a Single Task

Bundle these together (one logical unit):

- Types/interfaces needed for the feature
- Service/logic implementation
- Tests for that logic (write tests first when doing TDD)
- Integration into existing code
- Related component updates

## What Triggers a New Task

Create separate tasks only at these boundaries:

1. **Layer complete** — Backend done, ready for frontend
2. **Ready for manual testing** — Need user to verify
3. **Architectural decision needed** — Multiple valid approaches, need user input
4. **Manual verification** — Separate task for hands-on testing
5. **Risk boundary** — If next step could break things, checkpoint first

---

## Pre-Completion Verification

Every task should have structured verification BEFORE marking complete.

### Good vs Bad Verification

**Bad (vague):**

```markdown
- **Success:** Tests pass, type-check passes
```

**Good (explicit):**

```markdown
- **Verify before complete:**
    - [ ] Lint and type checks pass
    - [ ] Unit tests pass with full coverage
    - [ ] Edge cases from Watch out:
        - [ ] Invalid input → returns error (test: `handleInvalidInput`)
        - [ ] Duplicate entry → prevented (test: `rejectDuplicate`)
    - [ ] Integration: API responds correctly to frontend requests
- **Success:** Feature works, error cases handled
```

### Edge Case Cross-Check

Every item in "Watch out" MUST appear in verification:

```markdown
- **Watch out:**
    - API endpoint must validate auth token
    - Rate limiting applies to this endpoint
    - Empty results should show placeholder, not error

- **Verify before complete:**
    - [ ] Auth validation: test verifies 401 without token
    - [ ] Rate limiting: test verifies 429 after limit exceeded
    - [ ] Empty state: test verifies placeholder rendered
```

---

## Task Conventions

- Use `- [ ]` for incomplete, `- [x]` for complete
- Number as Phase.Task (e.g., 3.2)
- **Success criteria required** — Each task must define "done"
- **Verification checklist required** — Explicit checks before marking complete
- **Completion metadata** — Add Completed/Learnings/Key Changes when done
- Keep descriptions concise
- File paths indicative, not exhaustive

---

## Decision Framework

| Question | Answer |
| --- | --- |
| Small change (1-3 files)? | One task, includes everything |
| Medium feature (4-8 files)? | 2-3 tasks: logic → integration → verify |
| Large full-stack feature (8+)? | 3-5 tasks split by integration boundary |
| Frontend-only? | Skip backend phases |
| Backend-only? | Skip frontend phase |
| Needs manual testing? | Separate verify task |
| Architectural uncertainty? | Stop and ask before implementing |
| Trivial (1-line change)? | Don't create task, just do it |

---

## Self-Verification Checklist

Before finalizing tasks, check:

### Structure

- [ ] Is each task a complete logical unit (not just one file)?
- [ ] Does each task have clear success criteria?
- [ ] Are boundaries only at natural integration points?
- [ ] Is the task count appropriate for the feature size?

### Context Completeness

- [ ] Would a developer know when they're "done"?
- [ ] Can this task be picked up after `/clear`? (Context block complete?)

### Verification Quality

- [ ] Does each task have a "Verify before complete" section?
- [ ] Are verification checks explicit (not just "tests pass")?
- [ ] Does every "Watch out" item have a corresponding verification check?

### Plan Coverage (when working from plan)

- [ ] Every file from plan appears in Touches?
- [ ] Every error scenario captured in Watch out or tests?
- [ ] Every UI spec captured in Architecture or verification?
- [ ] Every verification step in final verify task?
- [ ] No items from plan "fell through the cracks"?

---

## Output

Write tasks to a `TASKS.md` file in a sensible location — either alongside the plan document
(e.g., `docs/plans/<feature>/TASKS.md`) or in the repository root. If a plan directory already
exists, put TASKS.md there.

**TASKS.md header** should link back to the plan if one exists:

```markdown
# <Feature Name>

> Plan: [PLAN.md](PLAN.md)
```

---

**Remember:** Tasks should be large enough to be meaningful, small enough to be recoverable if
something goes wrong. When working from a plan, the plan is the source of truth — extract
EVERYTHING.
