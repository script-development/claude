# Pre-completion verification

Every implementation task in TASKS.md needs a structured "Verify before
complete" block. This file holds the patterns and the rationale.

The point: replace vague "tests pass" success criteria with explicit checks
that map back to the task's `Watch out` items. Every "Watch out" entry must
appear in the verification block — otherwise the edge case is documented but
not enforced.

## Verification template

Add to each implementation task:

```markdown
- **Verify before complete:**
    - [ ] All [RED] action items have passing tests
    - [ ] All [GREEN] action items implemented
    - [ ] Domain tests pass (use the project's narrowed domain test command, not the full suite)
    - [ ] Each "Watch out" edge case addressed:
        - [ ] [specific edge case 1] — handled by [how]
        - [ ] [specific edge case 2] — handled by [how]
    - [ ] Integration point works: [specific check]
```

## Good vs bad

**Bad (vague):**

```markdown
- **Success:** Tests pass, type-check passes
```

**Good (explicit):**

```markdown
- **Verify before complete:**
    - [ ] Domain tests pass (project's narrowed domain test command for the auth slice)
    - [ ] Edge cases from Watch out:
        - [ ] Invalid TOTP code → returns false (test: `verifyChallenge.invalidCode`)
        - [ ] Recovery code consumed → set to null after use (test: `verifyChallenge.recoveryConsumed`)
    - [ ] Integration: `login()` in state.ts handles `{ two_factor_required: true }` response
- **Success:** Challenge flow works, error cases handled, login modified
```

## Verification by task type

| Task type | Verification focus |
|---|---|
| Backend end-to-end | Schema applied, unit coverage on services / actions per project threshold, feature tests, arch tests, static analysis passes |
| Frontend end-to-end | Frontend coverage per project threshold, user-visible behavior tested |
| Manual verification | Hands-on browser testing per checklist (Note: CI covers the full automated suite) |

## Edge case cross-check — non-negotiable

Every item in **Watch out** MUST appear in **Verify before complete**:

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

If a Watch out has no matching verification, you've documented a risk you're
not enforcing. Either add the check, or remove the Watch out — leaving it
hanging is worse than not flagging it at all.

## Review happens once per branch, not per task

`/next` does **not** spawn reviewer agents — per-task review was retired in
April 2026 because first-pass scores were 9-10 nearly every time. The gate for
a task is its verification: tests, types, lint.

Review runs once against the whole branch via `/review-branch`, which spawns
`runtime-integrity-reviewer` and `precedent-reviewer`. **Don't list them as
verification steps in a task** — they don't run at task granularity, and the
defects they hunt (transaction boundaries, sibling drift) only become visible
once the branch is whole.

## Lint, types, and CI — don't list these

Don't write checklist items for running lint or type checks. Project hooks
should handle them automatically:

| When | What runs (typical) |
|---|---|
| Every Edit/Write | Project formatter (e.g. Prettier, Pint, oxfmt) |
| `git commit` | Lint-staged on staged files |
| `git push` | Type checks, static analysis |
| Push to remote | Full test suite in CI |

Verification items in TASKS.md focus on what the developer actually has to
do: run the narrow domain test suite, hands-on browser checks, edge-case
verification. The hooks block commits/pushes that fail lint or types, so
listing those as checklist items is noise.

If your project doesn't yet have those hooks, list lint/type checks
explicitly — but the long-run fix is to push them into hooks, not to
re-list them in every task.

## Coverage requirements

| Stack | Threshold |
|---|---|
| Backend services / actions | Per project (typically 100% on the unit-test boundary) |
| Frontend | Per project (typically 100% on lines, branches, functions, statements) |

These are enforced by CI; the verification block should reference the
**narrow** domain test suite, not the full suite — domain runs in seconds,
full suite runs in minutes and adds nothing the parallel CI matrix isn't
already doing.

## Self-check before finalising TASKS.md

This checklist **is** the Phase 4 gate — nothing downstream re-checks it. Walk
every row before showing TASKS.md to the developer:

### Structure

- [ ] Is each task a complete logical unit (not just one file)?
- [ ] Do action items list `[RED]` tests BEFORE `[GREEN]` implementation?
- [ ] Does each task have clear success criteria?
- [ ] Are approval gates only at natural boundaries?
- [ ] Is the task count appropriate for the feature size?

### Context completeness

- [ ] Would a developer know when they're "done"?
- [ ] Can this task be picked up after `/clear`? (Context block complete?)
- [ ] Are project testing-skill references included where the project provides them?

### Verification quality

- [ ] Does each task have a "Verify before complete" section?
- [ ] Are verification checks explicit (not just "tests pass")?
- [ ] Does every "Watch out" item have a corresponding verification check?
- [ ] Are specific test names or `file:line` references included?
- [ ] Are coverage requirements stated per the project's thresholds?

### Acceptance Criteria coverage

- [ ] Does every implementation task have an `**Acceptance Criteria:**` line?
- [ ] Does every AC from PLAN.md appear in at least one task's AC mapping?
- [ ] Are "(partial)" annotations used when a task only covers part of an AC?
- [ ] Do infrastructure / scaffold tasks note "None directly" for their AC mapping?

### Plan coverage

- [ ] Every file from plan appears in Touches?
- [ ] Every error scenario captured in Watch out or tests?
- [ ] Every UI spec captured in Architecture or verification?
- [ ] Every verification step in final verify task?
- [ ] No items from plan "fell through the cracks"?

If any row is unchecked, fix it before handing off. No agent audits this
afterwards, so an unchecked row here is a gap that reaches implementation.
Record the coverage counts in TASKS.md's `## Review Notes` (see Phase 4).
