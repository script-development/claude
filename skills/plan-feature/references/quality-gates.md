# Quality gates — input (Phase 1.5) and output (Phase 4d)

`/plan-feature` runs two fail-closed gates that bracket the drafting work. The tables themselves live in SKILL.md so they fire reliably. This document carries the rationale, sycophancy guards, and operating notes — load it when you reach a gate.

## Why two gates

The path of least resistance — "this looks crisp, let me draft and we can iterate" — is the most expensive failure mode in planning. A draft built on partial information costs a full restart later (see `anti-patterns.md`). The input gate makes "is the input complete?" a binary question instead of a feel. The output gate catches the symmetric failure: drafted with thin filler text in the gaps.

## Phase 1.5 — input gate

**The rule:** every ✓ requires a quoted source. Every ? or ✗ is a topic for Phase 2 interrogation. **You may not proceed past Phase 1.5 with any ? or ✗ row.** Fail-closed.

Output the eight-row table verbatim to the developer with marks and citations filled in. Then either:

- **All ✓** — say "All eight checks pass with cited evidence. Proceeding to Phase 3 confirmation." Skip Phase 2 interrogation; the input is genuinely complete.
- **Any ? or ✗** — list the missing rows and proceed to Phase 2 to fill them. Phase 2 questions target only ? and ✗ rows. Don't sweep.

### Sycophancy guards

- A ✓ without a quoted source is invalid. If you can't cite it, mark ?.
- An issue body of "Add settings page for X" cannot mark Acceptance Criteria ✓ — there's nothing testable in there.
- A long developer prompt is not evidence of completeness. Length doesn't make a row ✓; only specifics do.
- "Edge cases will be handled during implementation" is ✗, not ✓.

This gate also gives `plan-reviewer` something concrete to verify post-hoc — every ✓ in the checklist must have produced a corresponding section of PLAN.md grounded in that evidence.

## Phase 4d — output gate

**The rule:** for each row in the SKILL.md output table, mark **OK** if the bullet rule is met **OR** if the section explicitly declares `N/A — <one-line reason>` (e.g. "Wireframes — N/A, backend-only feature"). Otherwise **THIN** and re-work the section before continuing.

The N/A carve-out exists because pure-content plans (translation work, refactor-only changes, backend-only features) legitimately have empty Wireframes / Migration / Site Docs Sync sections, and treating those as THIN would block them. An explicit N/A with a reason is substance — silent emptiness or "TBD" is not.

### Sycophancy guards specific to the output

- "TBD" in any row is THIN, not OK. If you don't know yet, you shouldn't be at Phase 4.
- A section consisting of one bullet is THIN unless the bullet rule explicitly allows it.
- Acceptance Criteria written as goals ("the feature should work well") are THIN. Each row is a binary observable.
- Restating the Goal in different sections doesn't count toward those sections' bulk.

If any row is THIN, fix the section using evidence from Phase 1.5 / Phase 2 transcripts. Do not invent new content here — that's a sign the input gate let something slip and you should re-open Phase 2 for that topic.

When every row is OK, proceed to Phase 5.
