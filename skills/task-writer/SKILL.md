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

**Default to coarser-grained tasks.** One task should cover a coherent layer end-to-end — e.g.,
"backend: migrations + models + DTOs + services + HTTP + tests" is *one* task, not three. Split
only at boundaries that buy something real: PR handoffs, backend-to-frontend contracts,
risk/approval gates, and manual verification. Artificial splits (layer-by-layer within the
backend) create handoffs without reducing risk — the model holds a full layer coherently, and
the reviewer reads commits, not tasks.

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
| Schema + Models + Business logic + Tests | Backend end-to-end task |
| API/HTTP layer + Route tests | Bundle with backend task unless contract is reviewed/deployed independently |
| UI components + State + Tests | Frontend end-to-end task |
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
| Small | 1-5 | 1 task | Don't split |
| Medium | 6-15 | 1-2 tasks | Backend end-to-end → Frontend end-to-end (+ manual verify) |
| Large | 15+ | 2-4 tasks | By PR, integration boundary, or risk gate |

**Why bigger than you'd expect:** Splitting backend into separate migration/logic/HTTP tasks
used to hedge against context loss mid-layer. That hedge is no longer load-bearing — splitting
there now creates handoffs without reducing risk. Keep splits where they buy something real
(reviewable PR boundary, merge order that another layer depends on, human checkpoint before a
risky operation).

### Full-Stack Feature Split

Default to **one backend task + one frontend task + manual verify**. Split further only when
you hit a real boundary (see [Approval Gates](#what-triggers-a-new-task-approval-gates)).

```
Phase N: [Feature Name] (2-3 tasks)

- [ ] N.1 Backend end-to-end (TDD)
      → Migrations, models, config, DTOs, business logic, controllers, routes, tests
      → Success: backend test suite passes, type/static analysis passes
      → On completion, automated reviewers (acceptance-reviewer + simplicity-reviewer)
        verify the work; both must score ≥ 7

- [ ] N.2 Frontend end-to-end (TDD)
      → Types, state, pages, components, modals, tests
      → Success: frontend test suite passes
      → On completion, automated reviewers verify the work; both must score ≥ 7

- [ ] N.3 Manual verification
      → Hands-on browser testing of the full feature
      → Success: feature works end-to-end in the browser
      → Note: CI runs the full automated suite on the PR — no local full-CI needed
```

**When to split a single task further:**

- Backend is large enough that one commit would be hard to review → split at the HTTP boundary
  (N.1a core + N.1b HTTP).
- Schema migration touches production data or is risky to roll back → checkpoint it as its own
  task for human approval.
- Multiple PRs are planned (e.g., big-bang restructure) → one phase per PR.
- Architectural uncertainty in one layer → isolate that layer so the decision is reviewable on
  its own.

For **frontend-only** features, skip N.1. For **backend-only** features, skip N.2.

---

## Task Format

```markdown
### Phase N: Feature Name (X tasks)

**Goal:** One sentence describing what this phase delivers.

**Phase Context:** (only if needed for phase-level decisions)

- Why NOT [alternative]: [Key decision that's not obvious from code]

- [ ] **N.1** Implement [feature/layer]
    - **Context:** (REQUIRED - enables standalone task pickup)
        - **Why:** [Business problem this solves - what triggered this task. Reference decisions: "see D2"]
        - **Architecture:** [How it fits in, which pattern to follow, e.g. "Follows pattern of LoginUserAction"]
        - **Key refs:** [Specific file:line references to understand entry points and integration]
        - **Watch out:** [Edge cases, gotchas, things that aren't obvious]
    - **Scope:** Brief description of what's included
    - **Acceptance Criteria:** AC #N, #N (partial — what this task covers vs later tasks). List the PLAN.md acceptance criteria numbers this task addresses. Use "(partial)" when the task only implements part of an AC. Omit for infrastructure/scaffolding tasks with no direct ACs.
    - **Touches:** Key files (not exhaustive, just main ones)
    - **Action items:**
        - [RED] Write tests for [specific behavior 1]
        - [RED] Write tests for [specific behavior 2]
        - [GREEN] Implement [component] to make tests pass
        - [GREEN] Integrate into [existing code]
    - **Verify before complete:**
        - [ ] Lint + type checks pass
        - [ ] [Watch out item 1] - addressed by [how/test name]
        - [ ] [Watch out item 2] - addressed by [how/test name]
        - [ ] Integration: [specific check]
    - **Success:** [One-line summary of done state]

- [ ] **N.2** Manual verification
    - Note: CI runs the full automated suite on the PR — this task covers only hands-on browser testing of the complete feature.
    - **Verify manually:** [What to test in the browser]
```

### Completion Metadata

When a task is completed, enrich it with what was learned — this is valuable for future tasks
and context recovery:

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

**CRITICAL:**

- Action items MUST list [RED] test-writing steps BEFORE [GREEN] implementation steps (TDD ordering)
- **Context block is REQUIRED** for every implementation task — written primarily for code
  reviewers and session recovery. Don't pad it to re-hydrate basic context that the model can
  load from the plan on its own; do include the non-obvious (watch-out edge cases, architectural
  references, pattern precedents).
- If the project provides domain-specific testing skills, reference them in the action items so
  the implementer loads them.

---

## Capturing Non-Code Requirements

Plans often contain specifications that aren't "write code for file X". Capture these:

### UI/UX Specifications

Put in **Architecture** or create dedicated **UI Spec** subsection:

```markdown
- **Context:**
    - **Architecture:** Profile page shows a 2FA section card:
        - Enabled state: green badge, "Disable" button, "Regenerate codes" link
        - Disabled state: "Enable 2FA" button with setup wizard modal
```

### Error Handling

Put each scenario in **Watch out** or create testable action items:

```markdown
- **Watch out:**
    - Invalid TOTP code → toast "Invalid verification code"
    - Recovery code already used → toast "Code already consumed"
    - User without 2FA secret → redirect to setup
```

Or as testable action items:

```markdown
- **Action items:**
    - [RED] Write tests for error cases (invalid code, consumed recovery, no secret)
```

### Verification Checklist

Put ALL verification steps from plan in the final verify task:

```markdown
- [ ] **N.5** Manual verification
    - Note: CI runs the full automated suite on the PR — this task covers only hands-on browser testing of the complete feature.
    - **Verify manually:**
        1. Enable 2FA from profile → QR code shown
        2. Confirm with authenticator app → recovery codes displayed
        3. Log out and log back in → challenge page appears
        4. Enter TOTP code → access granted
        5. Disable 2FA from profile → login works without challenge
```

---

## What Goes IN a Single Task

Bundle these together (one logical unit):

- Types/DTOs needed for the feature
- Service/business-logic implementation
- Tests for that service (write tests first — TDD)
- Integration into existing code
- Related handler/component updates

## What Triggers a New Task (Approval Gates)

Create separate tasks only at these boundaries. If a split doesn't fall on one of these, it's
probably artificial — collapse it.

1. **Risk boundary** — Destructive ops, production data migrations, auth/permission changes, or
   anything where you want a human checkpoint *before* proceeding
2. **PR boundary** — When the plan is shipped as multiple PRs (e.g., big-bang restructures,
   multi-phase rollouts). One phase per PR
3. **Backend → frontend handoff** — The API contract is a real handoff that the frontend depends
   on. Keep backend as one coherent task; split only when the contract needs to be reviewed or
   deployed before the frontend consumes it
4. **Architectural decision needed** — Multiple valid approaches, need user input before continuing
5. **Manual verification** — Hands-on browser testing always gets its own task (human-only)

**Not a reason to split:** "This touches a lot of files." One coherent task can own a full
backend layer (migrations + models + services + HTTP + tests) — splitting at intra-backend layer
boundaries creates handoffs without reducing risk.

---

## TDD Within Tasks

TDD happens INSIDE each task. Action items ordered: tests first, then implementation.

```
Task: Implement EnableTwoFactorAction
  ↓
  Action items (in this order):
    [RED]   1. Write tests for secret generation (happy path)
    [RED]   2. Write tests for re-setup (clears old confirmation)
    [GREEN] 3. Implement EnableTwoFactorAction to make tests pass
    [GREEN] 4. Wire into TwoFactorController
  ↓
  Run all tests, verify passing
  ↓
Task complete
```

**Rules:**

1. Action items MUST list [RED] steps before [GREEN] steps
2. Reference the project's testing skill where applicable
3. No "Testing:" footer — tests ARE the first action items

---

## Pre-Completion Verification

Every task should have structured verification BEFORE marking complete. Replace vague "tests
pass" with explicit checks.

### Verification Template

Add to each implementation task:

```markdown
- **Verify before complete:**
    - [ ] All [RED] action items have passing tests
    - [ ] All [GREEN] action items implemented
    - [ ] Lint + type checks pass
    - [ ] Domain tests pass (use the project's narrowed test command, not full suite)
    - [ ] Each "Watch out" edge case addressed:
        - [ ] [specific edge case 1] - handled by [how]
        - [ ] [specific edge case 2] - handled by [how]
    - [ ] Integration point works: [specific check]
```

### Good vs Bad Verification

**Bad (vague):**

```markdown
- **Success:** Tests pass, type-check passes
```

**Good (explicit):**

```markdown
- **Verify before complete:**
    - [ ] Lint + type checks pass
    - [ ] Domain tests pass (use the project's narrowed test command)
    - [ ] Edge cases from Watch out:
        - [ ] Invalid TOTP code → returns false (test: `verifyChallenge.invalidCode`)
        - [ ] Recovery code consumed → set to null after use (test: `verifyChallenge.recoveryConsumed`)
    - [ ] Integration: `login()` in state.ts handles `{ two_factor_required: true }` response
- **Success:** Challenge flow works, error cases handled, login modified
```

**Reviewer agents run automatically.** When `/next` finishes a task, it spawns
`acceptance-reviewer` and `simplicity-reviewer` in parallel. Both must score ≥ 7 before the task
is marked complete. You don't need to list them as verification steps in the task — they always
run. Address any BLOCKER/MAJOR findings the same way you'd address an acceptance-reviewer FAIL.

### Edge Case Cross-Check

Every item in "Watch out" MUST appear in verification:

```markdown
- **Watch out:**
    - POST /auth/two-factor-challenge must skip two-factor middleware
    - Recovery code must be consumed (set to null) after use
    - `two_factor_confirmed_at` separates "setup started" from "setup confirmed"

- **Verify before complete:**
    - [ ] Challenge route accessible without 2FA verification (test: middleware skips challenge endpoint)
    - [ ] Recovery code consumed: test verifies code is set to null after use
    - [ ] Unconfirmed setup: test verifies `two_factor_confirmed_at` is null before confirmation
```

---

## Task Conventions

- Use `- [ ]` for incomplete, `- [x]` for complete
- Number as Phase.Task (e.g., 3.2)
- **Success criteria required** — Each task must define "done"
- **Acceptance Criteria mapping required** — Each implementation task must list which PLAN.md AC
  numbers it addresses (omit for infra/scaffold tasks with no direct ACs)
- **Verification checklist required** — Explicit checks before marking complete
- **Completion metadata** — Add Completed/Learnings/Key Changes when done
- Keep descriptions concise
- File paths indicative, not exhaustive

---

## Decision Framework

| Question | Answer |
| --- | --- |
| Small change (1-5 files)? | One task, includes everything |
| Medium feature (6-15 files)? | 1-2 tasks: backend end-to-end → frontend |
| Large full-stack feature (15+)? | 2-4 tasks, split at PR / risk / layer handoff |
| Frontend-only? | Backend task omitted |
| Backend-only? | Frontend task omitted |
| Needs manual browser testing? | Always a separate final task |
| Schema migration on prod data? | Checkpoint as its own task for approval |
| Architectural uncertainty? | Stop and ask before implementing |
| Trivial (1-line change)? | Don't create task, just do it |

---

## Self-Verification Checklist

Before finalizing tasks, check:

### Structure

- [ ] Is each task a complete logical unit (not just one file)?
- [ ] Do action items list [RED] tests BEFORE [GREEN] implementation?
- [ ] Does each task have clear success criteria?
- [ ] Are approval gates only at natural boundaries?
- [ ] Is the task count appropriate for the feature size?

### Context Completeness

- [ ] Would a developer know when they're "done"?
- [ ] Can this task be picked up after `/clear`? (Context block complete?)
- [ ] Are testing-skill references included where the project provides them?

### Verification Quality

- [ ] Does each task have a "Verify before complete" section?
- [ ] Are verification checks explicit (not just "tests pass")?
- [ ] Does every "Watch out" item have a corresponding verification check?
- [ ] Are specific test names or file:line references included?

### Acceptance Criteria Coverage (when working from plan)

- [ ] Does every implementation task have an `**Acceptance Criteria:**` line?
- [ ] Does every AC from PLAN.md appear in at least one task's AC mapping?
- [ ] Are "(partial)" annotations used when a task only covers part of an AC?
- [ ] Do infrastructure/scaffold tasks note "None directly" for their AC mapping?

### Plan Coverage (when working from plan)

- [ ] Every file from plan appears in Touches?
- [ ] Every error scenario captured in Watch out or tests?
- [ ] Every UI spec captured in Architecture or verification?
- [ ] Every verification step in final verify task?
- [ ] No items from plan "fell through the cracks"?

---

## Output

Write tasks to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-short-description/TASKS.md` (same
directory as the plan). If the directory doesn't exist yet, create it.

**Determine the ticket key from:**

1. The current branch name (e.g. `{{ISSUE_KEY_PREFIX}}-1234-feature` → `{{ISSUE_KEY_PREFIX}}-1234`)
2. The plan file if one exists in `docs/plans/`
3. Ask the user if neither is available

**If no issue exists yet**, create one using the `/kendo-mcp` skill:

1. Read `kendo://projects` to confirm the project ID
2. Read the [issue-templates.md](../kendo-mcp/references/issue-templates.md) for the feature + bug templates
3. Create the issue with `mcp__kendo__create-issue-tool` and `project_id: {{PROJECT_ID}}`
4. Use the returned issue key (e.g. `{{ISSUE_KEY_PREFIX}}-115`) for the directory name

**TASKS.md header** should include the ticket key and links to the plan and decisions:

```markdown
# {{ISSUE_KEY_PREFIX}}-XXXX: Short Description

> Plan: [PLAN.md](PLAN.md) | Decisions: [DECISIONS.md](DECISIONS.md)
```

---

**Remember:** Tasks should be large enough to be meaningful, small enough to be recoverable if
something goes wrong. When working from a plan, the plan is the source of truth — extract
EVERYTHING.

## Post-Generation: Task–Plan Alignment Review

After writing TASKS.md, **always** spawn the `task-alignment-reviewer` agent to verify full
coverage. This catches gaps before implementation starts.

```
Agent({
  subagent_type: "task-alignment-reviewer",
  prompt: `Verify that TASKS.md fully covers PLAN.md.

Plan directory: docs/plans/<slug>/

Check that every acceptance criterion, wireframe screen, scope item, and planned file
maps to at least one task. Report coverage gaps and scope creep.`
})
```

**Threshold:** Score must be 7/10 or above. If below 7, revise TASKS.md to close the gaps
and re-run the reviewer. Do NOT present TASKS.md to the developer until it passes.
