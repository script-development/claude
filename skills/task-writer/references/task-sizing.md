# Task sizing — when to bundle, when to split

The default for `/task-writer` is **coarser-grained tasks**. One task should
own a coherent layer end-to-end — backend (migrations + models + DTOs +
services + HTTP + tests) is *one* task, not three. Splitting at intra-backend
layer boundaries creates handoffs without reducing risk: the model holds a
full layer coherently, and the reviewer reads commits, not tasks.

This file holds the decision rules that drive sizing.

## Sizing matrix

| Feature size | Files | Task count | How to split |
|---|---|---|---|
| Small | 1-5 | 1 task | Don't split |
| Medium | 6-15 | 1-2 tasks | Backend end-to-end → frontend end-to-end (+ manual verify) |
| Large | 15+ | 2-4 tasks | By PR, integration boundary, or risk gate |

**Why bigger than you'd expect:** splitting backend into separate
migration / service / HTTP tasks used to hedge against context loss
mid-layer. That hedge is no longer load-bearing — splitting there now
creates handoffs without reducing risk. Keep splits where they buy
something real (reviewable PR boundary, merge order that another layer
depends on, human checkpoint before a risky operation).

## Default full-stack split

For a feature with both backend and frontend work:

```
Phase N: [Feature Name] (2-3 tasks)

- [ ] N.1 Backend end-to-end (TDD)
      → Migrations, models, config, DTOs, services / actions, controllers, form requests, routes, middleware
      → Arch tests + unit tests + feature tests, per the project's testing conventions
      → Load the project's backend testing skill before writing tests
      → Success: backend test suite passes, type/static analysis passes
      → On completion, verification is the gate (tests + types + lint); review runs once per branch via `/review-branch`

- [ ] N.2 Frontend end-to-end (TDD)
      → Types, state, pages, components, modals, frontend tests
      → Load the project's frontend testing skill before writing tests
      → Success: frontend test suite passes (use the project's narrowed domain test command)
      → On completion, verification is the gate (tests + types + lint); review runs once per branch via `/review-branch`

- [ ] N.3 Manual verification
      → Hands-on browser testing of the full feature
      → Success: feature works end-to-end in the browser
      → Note: lint/format/type checks run as commit/push hooks; the full automated suite runs in CI on the PR — no manual full-suite invocation needed
```

For **frontend-only** features, skip N.1. For **backend-only**, skip N.2.

## Documentation-sync task

If the feature adds or changes API routes, MCP tools, or user-facing
capabilities, add:

```
- [ ] N.X Update site documentation
      → Update relevant pages in the project's docs/site to reflect changes
      → API routes changed → API docs section
      → MCP tools changed → MCP docs section
      → Feature behavior changed → user guides
      → Success: docs build passes, docs match implementation
```

## Approval gates — what triggers a new task

Create separate tasks **only** at these boundaries. If a split doesn't fall
on one of these, it's probably artificial — collapse it.

1. **Risk boundary** — destructive ops, production data migrations, auth/permission changes, or anything where you want a human checkpoint *before* proceeding
2. **PR boundary** — when the plan is shipped as multiple PRs (e.g. big-bang restructures, multi-phase rollouts). One phase per PR
3. **Backend → frontend handoff** — the API contract is a real handoff that the frontend depends on. Keep backend as one coherent task; split only when the contract needs to be reviewed or deployed before the frontend consumes it
4. **Architectural decision needed** — multiple valid approaches, need user input before continuing
5. **Manual verification** — hands-on browser testing always gets its own task (human-only)

## Splitting one task further

When the default backend / frontend split isn't enough:

- Backend is large enough that one commit would be hard to review → split at the HTTP boundary (`N.1a` core + `N.1b` HTTP)
- Schema migration touches production data or is risky to roll back → checkpoint it as its own task for human approval
- Multiple PRs are planned (e.g. big-bang restructure) → one phase per PR
- Architectural uncertainty in one layer → isolate that layer so the decision is reviewable on its own

## Not a reason to split

- "This touches a lot of files." One coherent task can own a full backend layer (migrations + models + services + HTTP + tests). Splitting at intra-backend boundaries creates handoffs without reducing risk.
- "I want progress to feel granular." Tasks are not check-ins; they're units of integration.
- "The reviewer might miss something." The pre-PR reviewers read the whole branch diff, not the task list — task granularity doesn't change what they see.

## Decision framework

| Question | Answer |
|---|---|
| Small change (1-5 files)? | One task, includes everything |
| Medium feature (6-15 files)? | 1-2 tasks: backend end-to-end → frontend |
| Large full-stack feature (15+)? | 2-4 tasks, split at PR / risk / layer handoff |
| Frontend-only? | Backend task omitted |
| Backend-only? | Frontend task omitted |
| Needs manual browser testing? | Always a separate final task |
| Schema migration on prod data? | Checkpoint as its own task for approval |
| Architectural uncertainty? | Stop and ask before implementing |
| Trivial (1-line change)? | Don't create task, just do it |

## Trivial-feature escape hatch

If the work is genuinely trivial — a one-line copy change, a config flip, a
prop rename — don't create TASKS.md at all. Phase 0 in SKILL.md routes
small plans to `/implement-plan`; truly trivial work falls below even that
threshold and should be done inline. Tell the developer:

> "This is a one-touch change — TASKS.md and `/implement-plan` would both be ceremony. Do it inline?"
