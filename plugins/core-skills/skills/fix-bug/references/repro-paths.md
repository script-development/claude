# Repro paths

Phase 3 of `/fix-bug` produces **something executable or describable that demonstrates the defect** — that's what Phase 8's verifier checks against. Three valid paths, plus a pre-flight validation step and a hard "cannot reproduce" stop condition.

## Before picking a path: validate the issue's contract

Read the issue's *Expected behaviour* / *Steps to reproduce* section against the feature it touches. The reporter writes user-language; the code encodes maintainer-language. Common gaps:

- A bullet says "X should always do Y" but the feature already supports a Y-overriding gesture (e.g. multi-select). The bullet may be the reporter's *symptom* description, not a behaviour contract.
- A bullet uses a name that resembles a code identifier but means something different in the user's head (e.g. "selected report" in the issue vs. `selectedReports` prop in code).
- Two bullets contradict each other under realistic feature usage.

If you spot any of these, **do not write failing tests yet**. Surface the contradiction to the developer in plain prose and ask which model is canonical:

> The issue says *"X should always do Y"*, but the feature uses gesture Z which would override Y in case W. Is bullet 3 the desired behaviour, or the reporter's symptom-language?

Only after the developer confirms the canonical model, pick a path and write tests. Otherwise the failing tests become contractual on a contract the developer never signed off on, and Phase 6 has to walk back the assertions.

## 3a. Failing test first (default)

Write a test that fails on HEAD for the exact reason the user reports, then passes after the fix. Use this when the mechanism is fuzzy — writing the test forces you to pin down the expected behaviour before patching. If the project has a domain-specific testing skill, load it before writing the test.

The same test becomes the regression gate in Phase 8. Once the fix makes it green, the bug cannot silently come back.

**BUG.md "Reproduction Steps" entry:**
> **Failing test (3a):** `path/to/test.spec.ts::<test name>`
> Run with: `<exact command>`

## 3b. Test alongside fix (clear diagnosis)

When the diagnosis is already done *for* you — stack trace pointing at a line, visible typo, null deref staring at you in a recent diff — a failing-test dance is ceremony. Skip it and ship the regression test in the same commit as the fix.

**Use only if all of these hold:** the issue includes a stack trace / error log / concrete file:line OR the defect is a self-evident typo/off-by-one/missing null-check; the fix is mechanical (no design judgment); the regression test ships with the fix (not before).

In BUG.md's Reproduction Steps, record diagnosis evidence in place of a failing test:

> **Diagnosis evidence:** `NullPointerException` at `CreateIssueAction.php:87` — thrown when `$project` is null because the caller sends a deleted project ID. No reproduction ceremony; fix + regression test ship together.

Path 3b also skips the hypothesis-ranking sub-step in Phase 6 and the post-mortem prompt in Phase 10 — the trace already tells you the cause and the diagnosis didn't surface a structural smell.

## 3c. Manual reproduction (visual / race / cross-tab)

Visual glitches, keyboard interactions across tabs, races only seen in real browsers — describe the steps in BUG.md and ask the developer to confirm manually before fixing:

> **Repro:** open project settings → team, click Invite, press Escape mid-animation. **Expected:** modal closes cleanly. **Actual:** backdrop stays. Confirm?

Do **not** automate a browser to reproduce — browser-automation skills (where they exist) are for verifying finished UI, not reproducing defects.

## Cannot reproduce at all

Stop. Ask for more context (steps, browser, tenant, role, data state). Don't proceed on "probably this".
