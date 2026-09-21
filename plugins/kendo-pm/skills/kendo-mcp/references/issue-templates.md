# Issue Templates

Single source of truth for how issues are written in this project. Used by `/newbranch`,
`/triage-reports`, `/plan-feature`, `/task-writer`, and `/kendo-cli` — any skill that creates
or promotes issues.

## Contents

1. [Issue Types & Priorities](#issue-types--priorities)
2. [Feature Template (User Story)](#feature-template-user-story)
3. [Bug Template (Bug Report)](#bug-template-bug-report)
4. [Task](#task)
5. [Writing Principles](#writing-principles)
6. [Examples](#examples)

---

## Issue Types & Priorities

These numeric values are the actual Kendo MCP schema — verify against `mcp__kendo__create-issue-tool` if in doubt.

| Type     | Value | Template                                    |
|----------|-------|---------------------------------------------|
| Feature  | `0`   | [User Story](#feature-template-user-story)  |
| Bug      | `1`   | [Bug Report](#bug-template-bug-report)      |
| Task     | `2`   | No fixed template — see [§ Task](#task).    |

| Priority | Value |
|----------|-------|
| Highest  | `0`   |
| High     | `1`   |
| Medium   | `2` (default) |
| Low      | `3`   |
| Lowest   | `4`   |

---

## Feature Template (User Story)

Use for anything that delivers new user-facing functionality. Keep the description small
enough that a developer can hold the whole thing in their head — detailed design goes in
`/plan-feature` output, not the issue itself.

For Feature issues, Acceptance Criteria (AC) describe user-observable outcomes — what the user sees or can do — not mechanism. "Clicking 'Log out' calls DELETE /logout" prescribes implementation; "Clicking 'Log out' returns the user to the login page" describes an outcome. AC written at the outcome layer stay stable as implementation evolves; mechanism-layer AC shift as design crystallises.

```markdown
# [Short, descriptive title]

## User Story
As a [role], I want [functionality] so that [goal].

## Context
[1–2 sentences of background: why is this on the table now, what problem does it solve?]

## Acceptance Criteria
1. [concrete, testable criterion]
2. [concrete, testable criterion]
3. [concrete, testable criterion]

## Scope
**In:**
- [in scope]
- [in scope]

**Out:**
- [explicitly excluded — prevents scope creep at review]

## Testing
- 100% coverage for new code
- [which scoped test suite must be green — name it]
```

Aim for **3–5 acceptance criteria**. If you need more, the story is probably too big — split it.

---

## Bug Template (Bug Report)

Use for defects in existing behaviour. The defining feature of a bug report is the
"Problem" + "Cause" pairing: what the user observes, and (when known) why. If you
haven't yet diagnosed the cause, replace the `## Cause` section with
`## Steps to reproduce` + `## Expected behavior` + `## Actual behavior` so the
next developer can reproduce and diagnose.

### When cause is known

```markdown
# [Short bug title]

## Problem
[What users see / what goes wrong, in 1–3 sentences.]

## Cause
[Technical analysis: which file, which function, why it fails.
Reference line numbers or commits if it helps.]

## Acceptance Criteria
- [concrete observable behaviour after the fix]
- [edge case 1]
- [edge case 2]

## Scope
**In:**
- [specific files/functions that get touched]

**Out:**
- [broader refactors that are tempting but deserve a separate issue]

## Testing
- [which test suite must be green]
- [regression check: which existing flow must still work]
```

Bug AC describe observable state after the fix — what the user experiences when the defect is no longer present. Edge cases and regressions belong here too.

The `## Cause` section names where the failure is — diagnosis, not prescription. `## Scope` specifies an area of work, not a developer instruction — write the area ("board fetch logic"), not a verb phrase.

### When cause is unknown (reproduction-first report)

```markdown
# [Short bug title]

## Problem
[What users see, in 1–3 sentences.]

## Context
[Which environment, which account, which flow led here.]

## Steps to reproduce
1. [step]
2. [step]
3. [step]

## Expected behavior
[What should have happened.]

## Actual behavior
[What actually happens — including error messages, stack traces, screenshots.]

## Possible causes
[Optional: hypotheses to investigate. If you have nothing, drop the section.]

## Scope
**In:** [what you think needs to be touched]
**Out:** [what is explicitly out of scope]

## Testing
- [how the fix is validated]
```

AC are not written at this stage. This template captures what's needed to reproduce and diagnose — AC belong in the fix issue once the cause is known and scope is clear.

---

## Task

Tasks use direct description — no fixed template. Describe the work, its motivation, and what done looks like.

Acceptance Criteria should describe what 'done' looks like at the level appropriate to the task. For example:

- **Refactoring** — structural change is the requirement. AC name the classes, call patterns, or invariants that must hold after the change.
- **Infrastructure** — system-observable behaviour. AC describe what the system does (queue dispatch, cache hit, retry on failure), not what users see.
- **Research / investigation** — artifact completion. AC describe the deliverable and what makes it actionable (document exists, covers these questions, concrete enough to file follow-up issues from).

---

## Writing Principles

### Do

- **English prose** — all user-facing content (user stories, bug reports) is English. Technical terms (class names, HTTP codes, file paths) stay literal.
- **Testable criteria** — "User can log out" ✗; "Clicking 'Log out' returns the user to the login page" ✓. Use measurable values or design token references for precision.
- **Concrete values for performance and thresholds** — name a measured or agreed value (`< 10 s` for up to 1 000 issues, `30-second TTL`), not prose hedges (`within a reasonable time`, `fast enough`). If the value isn't yet determined, write `[TBD: <what needs deciding and by whom>]` rather than leaving the hedge in place.
- **Concrete testing sections** — name the specific test suite, single-file run, or arch test, not "make sure it works". When the repo has scoped suites (per domain, per package, per file), name the scope the change touches rather than the whole slow suite. When the repo's standard gate *is* the whole suite, name that gate.
- **Design decisions in PLAN.md** — keep architectural choices in `/plan-feature` output (PLAN.md, DECISIONS.md), not the issue body.
- **Scope in two columns** — `**In:**` and `**Out:**`. The `Out:` list is often more valuable than `In:` because it prevents scope creep.
- **Right-size** — 2–5 days of work per issue. More? Split or use an epic (`mcp__kendo__create-epic-tool`). Much less? Maybe doesn't need its own issue.
- **Code-fences** for identifiers (class names, column names, command names). Keeps the issue readable in markdown renderers and in search.

### Avoid

- Implementation details in the body — unless a bug's cause requires them.
- Shallow testing sections like "make sure it works" or "all tests keep passing".
- The whole slow suite as the only check when the repo has scoped suites — name the affected scope instead.
- Vague criteria ("it must be fast", "it must be pretty").
- Multi-week epics in a single issue.

### Title Conventions

- Start with a verb or noun that names the problem — not the proposed solution.
- Good: `Board shows issues outside the active sprint` (describes the symptom).
- Also good: `User can reset password` (describes the desired functionality).
- Avoid: `Fix board filter bug` (no symptom, no feature — empty for search).

---

## Examples

Filled-in examples are stack-specific (Vue/Laravel/Pest/etc.) and stay consumer-side. Each consumer maintains its own examples file alongside this one if useful — the catalog version intentionally ships templates only.
