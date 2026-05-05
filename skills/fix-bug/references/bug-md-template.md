# BUG.md template

Save to `docs/bugs/<KEY>-<short-slug>/BUG.md`. The slug is 2-5 words of kebab-case summarising the defect, not a copy of the title.

## What to fill when

- **Phase 5 (now):** Problem, Reproduction Steps, Status: `Investigating`.
- **Phase 6:** Root Cause (Status → `Diagnosed`), then Chosen Approach once the developer picks a candidate.
- **Phase 7:** Fix (Status → `Fixing`).
- **Phase 8:** Verification (filled by the `bug-fix-verifier` agent). Status → `Verified` after PASS.
- **Notes / Follow-ups:** any time something adjacent surfaces. Empty is fine.

## Template

```markdown
# <KEY>: <short bug title>

**Date:** <YYYY-MM-DD>
**Issue:** [<KEY>](link to issue)
**Status:** Investigating | Diagnosed | Fixing | Verified | Abandoned

## Problem
<2-4 sentences on the user-visible defect. Pulled from the issue's Problem
section, restated in your own words so this file reads independently.>

## Reproduction Steps
<Use exactly one of the headings below, matching the path you took.>

**Failing test (3a):** `path/to/test.spec.ts::<test name>`
Run with: `<exact command>`

**— or —**

**Diagnosis evidence (3b):**
- Stack trace / error log line: `<pasted trace>`
- Or concrete file:line reference: `<path:line>`
- Regression test that will ship with the fix: `<path/to/test.spec.ts::<test name>>`

**— or —**

**Manual steps (3c):**
1. <step>
2. <step>
3. <expected vs. actual>

## Root Cause
<Filled in Phase 6. 2-4 sentences on why the defect happens. Cite file:line
for the code at fault. Describe the mechanism, not the symptom.>

## Chosen Approach
<Filled at the end of Phase 6 once the developer accepts a candidate.
One line naming the picked solution — alternatives stay in chat, not here.>

## Fix
<Filled in Phase 7. What changed, in what files, why that addresses the
root cause. Not a diff dump — a short explanation a future reader can grasp
without opening the PR.>

## Verification
<Filled by bug-fix-verifier in Phase 8. Score, verdict, evidence. Empty
until the agent writes it.>

## Notes / Follow-ups
<Adjacent issues, missing tests elsewhere, refactors worth doing later.
Empty is fine.>
```
