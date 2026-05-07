---
name: task-writer
description: |
  TDD task breakdown and TASKS.md management. Use when planning a new feature, breaking down work
  into implementation tasks, creating or updating TASKS.md, estimating effort, or organizing
  multi-step work into phases. Also use when translating a plan document (like docs/plans/*.md)
  into TASKS.md — includes systematic extraction checklist to ensure nothing is missed. Trigger on:
  feature breakdown, task planning, "write tasks for", "create TASKS.md", plan-to-tasks conversion,
  sprint planning, implementation ordering, or when the user mentions wanting to organize
  implementation steps for a feature.
---

# Task Writer

Translate an approved PLAN.md into a TDD task breakdown (`TASKS.md`) that
`/next` can execute one task at a time. Lighter than `/plan-feature` — no
interrogation, no design — but heavier than `/implement-plan` because it
owns the per-task contract that downstream agents (`acceptance-reviewer`,
`simplicity-reviewer`) verify against.

If the plan is small enough to skip TASKS.md entirely, **Phase 0 hands off
to `/implement-plan`** — same plan context, no per-task overhead. The
fail-closed gate exists because the alternative — drafting TASKS.md "just
in case" — turns small plans into ceremony every time.

## Core philosophy

Bundle related work — types, service, tests, integration — into one
logical unit. Split by integration boundaries, not by files. Default to
**coarser-grained tasks**: one coherent layer end-to-end ("backend:
migrations + models + DTOs + services + HTTP + tests") is *one* task, not
three. Splitting at intra-backend boundaries creates handoffs without
reducing risk — the model holds a full layer coherently and the reviewer
reads commits, not tasks.

For sizing rules, approval gates, and the decision matrix that drives
splits, load [`references/task-sizing.md`](references/task-sizing.md).

## Phase 0: Right-size check (mandatory, fail-closed)

Before extracting tasks, check whether this plan is small enough that a
TASKS.md breakdown is overkill. The full inventory + task table is
valuable when work spans multiple integration boundaries — and noise when
it doesn't. Closing this loop matters because `/next` already has the
symmetric branch ("no TASKS.md → use `/implement-plan`"); both skills
should agree on what's small enough to skip the breakdown.

Read PLAN.md and count:

- **Approach steps** — bulleted/numbered items in the "Approach" section
- **Touched layers / domains** — backend-only, frontend-only, or both?
- **PR shape** — does the plan call for one PR or several?

| Signal | Threshold |
|---|---|
| Approach steps | ≤ 8 (count outer headings; if a step expands into a 3+ sub-list of mutation sites, count those sub-items too — nested step counting prevents 4 outer steps masking 6 sequential edits) |
| Touched layers / domains | one **coordinated** slice — either single layer in one domain, or multiple layers tightly coordinated within a single domain. Cross-domain reach via mechanical migration of call sites doesn't count against this. |
| PR shape | one PR is enough |

If **all three** thresholds are met, output the redirect and stop:

> "This plan is small enough that a TASKS.md breakdown would be ceremony, not value: <N> Approach steps, single coordinated slice (<layer/domain summary>), one-PR shape. Recommending `/implement-plan` instead — it loads the same plan context, runs TDD, and ends at the acceptance gate without the per-task overhead.
>
> Want me to invoke `/implement-plan` now, or do you want TASKS.md anyway?"

Wait for the developer's answer. If they confirm `/implement-plan`, hand
off. If they want TASKS.md anyway (sometimes the case for risk gates or
PR-handoff coordination even on small plans), proceed to Phase 1 — but
**cite the developer's reason** in the eventual TASKS.md so future readers
don't wonder why a small plan got the full treatment.

If **any threshold is exceeded** (≥ 9 Approach steps including expanded
sub-lists, multiple uncoordinated domains, or multi-PR shape), proceed
straight to Phase 1 without the redirect prompt.

Calibration evidence and sycophancy guards live in
[`references/quality-gates.md`](references/quality-gates.md).

## Phase 1: Build extraction inventory

Read PLAN.md and extract every concrete artefact into a category
checklist. The full category list — Code Changes, Integration Points,
UI/UX Specs, Error Handling, Verification Requirements — and the "what
fits where" table live in
[`references/extraction-workflow.md`](references/extraction-workflow.md).
Load it the moment you start the inventory.

Output the inventory verbatim to the developer with every line filled in.
**Every PLAN.md item must land in a category.** If a PLAN.md item doesn't
fit, the plan has a gap — surface it before continuing. Don't shoehorn
ambiguous items into "Code Changes" to keep the inventory looking
complete; that's how scope creep ships.

If `WIREFRAMES.md` exists alongside PLAN.md, treat each screen as its own
UI/UX inventory entry. Component breakdowns become Touches on the frontend
task; interaction specs become "Watch out" entries or `[RED]` test
descriptions.

## Phase 2: Map inventory to tasks

Group inventory items by **integration boundary**, not by file:

| Inventory category | Maps to |
|---|---|
| Migrations + Models + Config | Infrastructure task (Phase 1 of TASKS.md) |
| Services / Actions + DTOs + Unit tests | Backend logic task (Phase 2) |
| Controllers / HTTP layer + Routes + Feature tests | Backend HTTP task (Phase 3) |
| Frontend components + State + Tests | Frontend task (Phase 4) |
| Error scenarios | → Task Context "Watch out" section |
| UI specs | → Task Context "Architecture" section |
| Verification steps | → Final manual verification task |

Adapt the layer names to your stack — the boundary points (infrastructure
→ logic → HTTP → frontend → manual verify) are the contract; the labels
on either side are not.

Write the tasks using the literal format in
[`references/tasks-template.md`](references/tasks-template.md). The
template is the contract — `/next`, `acceptance-reviewer`, and
`task-alignment-reviewer` parse the section names, so don't rename or omit
them.

For sizing decisions (when to split, when to bundle), load
[`references/task-sizing.md`](references/task-sizing.md). For
pre-completion verification specifics (what to put in the "Verify before
complete" block), load
[`references/verification.md`](references/verification.md).

## Phase 3: Verify complete coverage

Cross-check before finalising:

```markdown
## Coverage Check

- [ ] Every "Files to modify" appears in at least one task's Touches
- [ ] Every "Files to create" appears in at least one task's Touches
- [ ] Every error scenario from the plan is in a task's "Watch out" or action items
- [ ] Every UI spec is captured in Context or verification
- [ ] Every verification step from the plan is in the final verify task
- [ ] Every PLAN.md acceptance criterion is mapped to at least one task's `**Acceptance Criteria:**` line
```

If any row is unchecked, you're not done. Don't punt to "the reviewer will
catch it" — that's the next phase, and a clean self-check makes the
reviewer's job re-confirmation, not discovery. The full self-check —
structure, context completeness, verification quality, AC coverage, plan
coverage — lives in
[`references/verification.md`](references/verification.md).

## Phase 4: Self-gate via task-alignment-reviewer (mandatory, fail-closed)

**Before showing TASKS.md to the developer**, spawn the
`task-alignment-reviewer` agent. It scores 1-10 against PLAN.md coverage;
below 7, fix the gaps and re-run until it passes. This exists because
you'll rationalise your own coverage decisions — a context-free agent
won't.

```
Agent({
  subagent_type: "task-alignment-reviewer",
  prompt: `Verify that TASKS.md fully covers PLAN.md.

Plan directory: docs/plans/<slug>/

Check that every acceptance criterion, wireframe screen, scope item, and planned file
maps to at least one task. Report coverage gaps and scope creep.`
})
```

The reviewer appends a `## Review Notes` section to TASKS.md so future
readers can see the verdict without re-running the audit. If the reviewer
flags scope creep, two valid responses: update PLAN.md to include the
missed work (with the developer's confirmation), or remove the task. Don't
paper over the gap by silently editing the plan.

Threshold rationale and what the reviewer checks live in
[`references/quality-gates.md`](references/quality-gates.md).

## Phase 5: Hand off

Tasks are written and the alignment reviewer passed. Stop here —
implementation is owned by a separate skill:

- **`/next`** — execute one task at a time, TDD loop, automatic per-task `acceptance-reviewer` + `simplicity-reviewer` runs
- **`/implement-plan`** — execute the full plan in one pass without TASKS.md (Phase 0 should have routed here for small plans)

Do not invoke `/next`, `/implement-plan`, or their reviewers from inside
this skill. Each downstream skill owns its own quality gate; chaining them
here would recreate the mega-skill we just trimmed away.

## Output

Write tasks to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-short-description/TASKS.md`
(same directory as the plan). If the directory doesn't exist yet, create it.

**Determine the ticket key from:**

1. The current branch name (e.g. `{{ISSUE_KEY_PREFIX}}-1234-feature` → `{{ISSUE_KEY_PREFIX}}-1234`)
2. The plan file if one exists in `docs/plans/`
3. Ask the user if neither is available

**If no issue exists yet**, create one using the `/kendo-mcp` skill:

1. Read `kendo://projects` to get the project ID
2. Read the [issue-templates.md](../kendo-mcp/references/issue-templates.md) for the feature + bug templates
3. Create the issue with `mcp__kendo__create-issue-tool` and `project_id: {{PROJECT_ID}}`
4. Use the returned issue ID (e.g. `115` → `{{ISSUE_KEY_PREFIX}}-115`) for the directory name

**TASKS.md header** should include the ticket key and links to the plan
and decisions:

```markdown
# {{ISSUE_KEY_PREFIX}}-XXXX: Short Description

> Plan: [PLAN.md](PLAN.md) | Decisions: [DECISIONS.md](DECISIONS.md)
```

## Worked example

A frontend-only feature showing the task format with TDD ordering,
verification, and completion metadata lives in
[`references/example-frontend-feature.md`](references/example-frontend-feature.md).
Reference it when you need a concrete output to model your TASKS.md
against.
