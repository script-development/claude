# Ready for Agent

When an issue earns the `Ready for Agent` label, and what the label promises. Read by
`/triage-reports` (which applies it at promotion), by whoever picks work for an agent (a
developer's own session, an orchestrator, a queue view on the board), and by any skill that
writes issues. Resolve the label id by name from `prepare-project-context`'s `labels` array;
never hardcode it.

These are the generic criteria. A project that calibrates its own — named precedents, the
provider consoles it depends on, its own epic history — keeps that copy at
`.claude/references/agent-ready.md`, and `/triage-reports` reads it instead of this file.

## What the label means

**An agent finishes this issue in one session, from planning to pull request, with the developer
only ratifying.** The session may be a developer running `/plan-feature` or `/fix-bug` then
`/next` and `/pr`, or an orchestrator briefing a worker; the label does not care which. Planning
is expected and welcome: the issue does not have to carry every decision, because the driving
session settles the technical forks first. It has to be the *kind* of work one session finishes
without a product ruling, a wireframe round, a manual verification, or hands outside the repo.

It is not a quality score for the issue text (AC clarity, bounded scope, named files, observable
behaviour, no ambiguity are a separate rubric). A well-written issue that ends in a product
decision is not ready; a mechanical fix with a thin body can be.

## The five criteria (all must hold)

1. **No open product decision.** Technical forks are the driving session's to settle in its plan:
   one shared helper or three copies, tooltip or inline text under the design system, which
   validation limit. Product forks are the developer's and block the label: behaviour a user
   would notice and might dispute (hidden or disabled control, what a status command claims), a
   test-rule or convention ruling, an app-wide policy ("decide once, not per site"), a spend cap
   or retention horizon. A body containing `[TBD`, "decide whether", "product decision first" or
   "research" is not ready until the fork is resolved in the text. Resolving one such fork at
   triage time is cheap and is the usual way a not-ready issue becomes ready.
2. **One PR of bounded size.** The issue is one pull request, whether or not it belongs to an
   epic. Size is the triage effort band: **Trivial, Small or Medium** qualify. **Large** does not;
   Large means "split into epic children", and each child is judged on its own.
3. **Never a full feature.** A Feature-type issue qualifies only when it extends an existing
   surface: no new screen, no wireframe round, no `/plan-feature` pass needed before a worker can
   start. Anything needing those is an epic or a planning issue, not a labelled issue.
4. **Verifiable by CI and automated review alone.** The Testing section names a runnable command
   and the test that goes red to green. No manual browser check (styling and animation fixes are
   gated on one by `/fix-bug`), no production or staging measurement, no "compare before and after
   by eye".
5. **No developer hands outside the repo.** No hosting secrets, payment-provider or DNS
   configuration, production runbook step, or third-party console.

## The companion label: `Needs Decision`

An issue that fails only criterion 1 carries **`Needs Decision`** instead. It names what the
issue waits for: a product ruling from the developer, recorded on the issue (a comment or an
edit to the body). Once the ruling is in the text, the label flips to `Ready for Agent` if the
other four criteria hold. Both labels are resolved by name from `prepare-project-context`'s
`labels` array; a project without them simply goes unlabelled. `blocked` is a different bucket
(another issue or an upstream release is in the way), and so is a manual-verification gap
(criterion 4), which carries no label.

## Hints for the plan or brief (not gates)

Record these on the triage card and in the issue when known; the driving session sequences them.

- **In-tree precedent.** The sibling that already solves this shape ("as PROJ-XXXX did for the
  two bulk-assign handlers", "the existing per-user rate-limiter key"). A worker copies; it does
  not invent.
- **Blocked by** an open issue, and **coupling**: several labelled issues that edit the same
  shared allowlist or primitive cost a review round per sibling merge. Name the siblings.

## Typical shapes

| Usually ready | Usually not |
|---|---|
| Copy a sibling's fix to the handler that missed the sweep | A new screen, page or flow |
| Add a validation limit plus its request test | An app-wide error-handling or rollback policy |
| Add a missing feature or unit test | A rule-reach or convention ruling on the test suite |
| Gate a control on a permission the route already checks (decision made: hide) | A spend cap, retention horizon or purge window |
| Delete pass-through tests a prior issue removed elsewhere | A migration with backfill |
| Re-measure a constant and pin it | A fix whose proof is a screenshot or a staging run |
| Prefix a cache or limiter key with the tenant id | Anything needing a secret or a provider console |
