# Example: frontend-only feature

A small frontend-only feature showing the task format with TDD ordering,
verification, and completion metadata. Reference this when you need a
worked example of how the SKILL.md phases produce a real TASKS.md.

The example below is from a Vue + TypeScript codebase — adapt the test
runner names, store/component conventions, and route helpers to your own
stack. The **shape** of the task (Context → Touches → Action items →
Verify before complete → Success) is what matters and is stack-agnostic.

## Input — feature request

> "Add a clickable icon to blocking issue cards that navigates to the
> blocked issue's detail page."

## Output — TASKS.md

```markdown
# {{ISSUE_KEY_PREFIX}}-0072: Navigation for Blocking Issues

### Phase 1: Add navigation icon to BlockingIssueCard (2 tasks)

**Goal:** Each blocking issue card gets a clickable link that navigates to that issue's detail page.

- [ ] **1.1** Add navigate link to `BlockingIssueCard`
    - **Context:**
        - **Why:** Users viewing dependencies have no way to jump to a blocking/blocked issue without manually searching.
        - **Architecture:** Add an `<a>` with `@click.prevent` + `routerService.goToShowPage` inside
          `BlockingIssueCard.vue`, outside the `<template v-if="editable">` block so it always renders.
          Use the project's icon component with a link icon, styled with the project's clickable token classes.
        - **Key refs:**
            - `frontend/.../components/BlockingIssueCard.vue` — component to modify
            - Navigation pattern: `routerService.goToShowPage(PROJECT_ISSUES_DOMAIN_NAME, issue.id)` (same pattern as the existing Show page)
            - Router mock: `__mocks__/router/index.ts` — `goToShowPage` is already a mocked function
        - **Watch out:**
            - Navigate link must sit outside `<template v-if="editable">` — visible in both Show and Edit contexts
            - `routerService.goToShowPage` resolves `parentId` from current route automatically — no prop needed
            - Use `<a>` not `<button>` — enables right-click "Open in new tab" and shows URL in status bar
    - **Touches:**
        - `frontend/.../components/BlockingIssueCard.vue`
        - `frontend/.../constants/icons.ts` (add link icon export)
        - `frontend/tests/.../components/BlockingIssueCard.spec.ts`
    - **Action items:**
        - [RED] Write test: clicking navigate link calls `routerService.goToShowPage(PROJECT_ISSUES_DOMAIN_NAME, issue.id)`
        - [RED] Write test: navigate link is visible when `editable` is `false`
        - [RED] Write test: element is an `<a>` tag with correct `href`
        - [GREEN] Add link-icon export to the icons constants module
        - [GREEN] Add navigate `<a>` with `data-test="navigate-button"`, `@click.prevent` handler, and icon component
    - **Verify before complete:**
        - [ ] Domain tests pass (project's narrowed domain test command for the issues slice)
        - [ ] Button outside `v-if="editable"`: test for `editable=false` passes
        - [ ] Link semantics: element is `<a>` with `href` (not `<button>`)
    - **Success:** Navigate link on every blocking issue card; clicking routes to correct issue detail page

- [ ] **1.2** Manual verification
    - Note: CI runs the full automated suite on the PR — this task covers only hands-on browser testing of the complete feature.
    - **Verify manually:**
        1. Open an issue with "Blocked By" dependencies
        2. Click the link icon — navigates to correct issue detail page
        3. Right-click the link icon — "Open in new tab" option available
        4. Confirm icon visible in both Show and Edit views
```

## What this example illustrates

- **Context block enables task pickup after `/clear`** — a fresh Claude session can read the Why / Architecture / Key refs / Watch out and resume without re-reading the plan
- **Watch out items have corresponding verification checks** — every "Watch out" entry maps to a `Verify before complete` row
- `[RED]` tests come **before** `[GREEN]` implementation — TDD ordering is non-negotiable
- The `<a>` vs `<button>` semantic choice is captured in **Watch out**, not buried in implementation prose — it's a decision a reviewer needs to see
- Verification uses the project's narrow domain test suite, not the full suite
- Manual verification is its own task because hands-on browser testing is human-only

Adapt the file paths, test runner invocation, and component conventions
to your stack. The structure (Context → Touches → Action items → Verify
before complete → Success) is the contract; everything inside it is
project-flavoured.
