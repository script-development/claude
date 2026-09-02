# Extraction inventory — Phase 1 categories

Phase 1 in SKILL.md is the gate: every PLAN.md item must land in one of these
categories. This file holds the full category list and the "what fits where"
rules. Load it the moment you start the inventory.

The point of an explicit inventory — instead of "read the plan and write
tasks" — is to make scope creep and gaps visible **before** task wording
locks them in. A missing category at this stage costs an extra round of
revisions; a missing category after `/next` starts costs a re-plan.

## The literal inventory

Copy this block to the developer with every line filled in:

```markdown
## Extraction Inventory

### Code Changes

- [ ] Backend files to modify: [list every file mentioned]
- [ ] Backend files to create: [new services / actions, controllers, requests, DTOs]
- [ ] Frontend files to modify: [components, stores, routes]
- [ ] Frontend files to create: [new pages, components, modals]
- [ ] Database changes: [migrations, seeders]
- [ ] Type changes: [TypeScript types, backend DTOs]

### Integration Points

- [ ] API endpoints: [new routes, modified controllers]
- [ ] Frontend-backend contracts: [request/response shapes]
- [ ] Route registrations: [where new routes wire in]
- [ ] Middleware changes: [new middleware, group modifications]

### UI/UX Specifications

- [ ] Page layouts: [new pages, modified views]
- [ ] Component behavior: [modals, forms, tables]
- [ ] User flows: [what user sees after each action]

### Error Handling

- [ ] Error scenarios: [list each from plan]
- [ ] User-facing messages: [toast/alert text]
- [ ] Validation rules: [form request rules, frontend validation]

### Verification Requirements

- [ ] Manual test steps: [from plan's verification section]
- [ ] Edge cases to test: [race conditions, permissions, etc.]
- [ ] Success criteria: [how to know it works]
```

## What lands where

| If PLAN.md says… | Inventory category | Eventually becomes (Phase 2) |
|---|---|---|
| New file path under the backend tree | Code Changes → Backend files to create | `**Touches:**` of backend task |
| Existing file path with "modify" verb | Code Changes → Backend/Frontend files to modify | `**Touches:**` |
| Migration name or schema definition | Code Changes → Database changes | Infrastructure task |
| New TS interface or backend DTO class | Code Changes → Type changes | Bundled with the task that owns the producer |
| `POST /api/...` route | Integration Points → API endpoints | Backend HTTP task |
| Request/response DTO contract | Integration Points → Frontend-backend contracts | Crosses backend → frontend handoff |
| "User clicks X, sees Y" prose | UI/UX → User flows | Task Context "Architecture" |
| "If invalid → toast Z" | Error Handling → User-facing messages | Task Context "Watch out" + a `[RED]` test |
| Plan's "Verification" section steps | Verification Requirements → Manual test steps | Final manual-verify task |

If a PLAN.md item doesn't fit any row, **the plan has a gap** — surface it to
the developer before continuing. Don't shoehorn ambiguous items into "Code
Changes" to keep the inventory looking complete; that's how scope creep ships.

## Reading WIREFRAMES.md

If `WIREFRAMES.md` exists alongside PLAN.md, treat each screen as its own
UI/UX inventory entry. Component breakdowns from the wireframe become Touches
on the frontend task; interaction specs become "Watch out" entries or `[RED]`
test descriptions.

## Coverage check (Phase 3)

After tasks are drafted, the coverage check is the symmetric output of this
inventory — every box ticked above must trace forward to a task. The check
itself lives in SKILL.md Phase 3 because it's a fail-closed gate; the
rationale lives here:

A coverage check is not "did I list everything?" — that's the Phase 4 coverage
gate. It's "did the tasks I just wrote actually reflect the inventory
I just built?" Two gates, both fail-closed, because losing an item between
inventory and task wording is the most common mid-implementation surprise.
