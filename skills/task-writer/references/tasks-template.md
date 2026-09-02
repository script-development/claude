# TASKS.md template

Save the breakdown to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-slug/TASKS.md`. Use
this exact structure — `/next` parses it. Renaming or omitting sections breaks
downstream agents silently.

## Task format

```markdown
### Phase N: Feature Name (X tasks)

**Goal:** One sentence describing what this phase delivers.

**Phase Context:** (only if needed for phase-level decisions)

- Why NOT [alternative]: [Key decision that's not obvious from code]

- [ ] **N.1** Implement [feature/layer]
    - **Context:** (REQUIRED — enables standalone task pickup)
        - **Why:** [Business problem this solves — what triggered this task. Reference decisions: "see D2"]
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
        - [ ] [Watch out item 1] — addressed by [how/test name]
        - [ ] [Watch out item 2] — addressed by [how/test name]
        - [ ] Integration: [specific check]
    - **Success:** [One-line summary of done state]

- [ ] **N.2** Manual verification
    - Note: CI runs the full automated suite on the PR — this task covers only hands-on browser testing of the complete feature.
    - **Verify manually:** [What to test in the browser]
```

## Required sections per task

| Section | Required when | Notes |
|---|---|---|
| **Context** | Every implementation task | Enables pickup after `/clear`. Don't pad it; write the non-obvious. |
| **Acceptance Criteria** | Every implementation task | List AC numbers from PLAN.md. Use "(partial)" when only part of an AC is covered. Omit for infra/scaffold tasks. |
| **Touches** | Every implementation task | Indicative file paths, not exhaustive. |
| **Action items** | Every implementation task | `[RED]` tests **before** `[GREEN]` implementation. No exceptions. |
| **Verify before complete** | Every implementation task | One row per "Watch out" item, plus integration checks. |
| **Success** | Every task | One line. The done-state predicate. |

## Completion metadata

When a task is completed, enrich it with what was learned. This is valuable
for future tasks and context recovery:

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

## TDD ordering — non-negotiable

Action items MUST list `[RED]` test-writing steps **before** `[GREEN]`
implementation steps. The order encodes TDD discipline; reversing it
encourages "implement, then write tests that pass" anti-patterns.

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

If the project provides domain-specific testing skills (backend service
tests, frontend component tests), reference them in the action items so
the implementer loads them before writing tests. No "Testing:" footer —
tests **are** the first action items.

## Capturing non-code requirements

Plans contain specifications that aren't "write code for file X". Capture
them inside the task structure:

### UI/UX specifications → Architecture

```markdown
- **Context:**
    - **Architecture:** Profile page shows a 2FA section card:
        - Enabled state: green badge, "Disable" button, "Regenerate codes" link
        - Disabled state: "Enable 2FA" button with setup wizard modal
```

### Error scenarios → Watch out + `[RED]` tests

```markdown
- **Watch out:**
    - Invalid TOTP code → toast "Invalid verification code"
    - Recovery code already used → toast "Code already consumed"
    - User without 2FA secret → redirect to setup
- **Action items:**
    - [RED] Write tests for error cases (invalid code, consumed recovery, no secret)
```

### Verification steps → final manual-verify task

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

## Conventions

- `- [ ]` for incomplete, `- [x]` for complete
- Number as `Phase.Task` (e.g. `3.2`)
- File paths in **Touches** are indicative, not exhaustive — listing every file is noise
- Keep descriptions concise; the Context block is for the non-obvious, not for re-hydrating basic plan context
- The Context block is written primarily for code reviewers and `/clear`-recovery, not for the current Claude session

## What goes IN a single task — bundle these together

- Types / DTOs needed for the feature
- Service / Action implementation
- Tests for that service (write tests first — TDD)
- Integration into existing code
- Related handler / component updates

For when to **split** instead of bundle, see [`task-sizing.md`](task-sizing.md).
