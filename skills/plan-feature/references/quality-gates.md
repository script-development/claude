# Quality gates — input (Phase 1.5), security (Phase 1.6), and output (Phase 4d)

`/plan-feature` runs three fail-closed gates that bracket the drafting work. The tables themselves live in SKILL.md so they fire reliably. This document carries the rationale, sycophancy guards, and operating notes — load it when you reach a gate.

## Why three gates

The path of least resistance — "this looks crisp, let me draft and we can iterate" — is the most expensive failure mode in planning. A draft built on partial information costs a full restart later (see `anti-patterns.md`). The input gate makes "is the input complete?" a binary question instead of a feel. The security gate catches the surfaces the convention checks don't see (untrusted-bytes flow, billing dollars, audit fidelity, lifecycle correctness). The output gate catches the symmetric failure: drafted with thin filler text in the gaps.

## Phase 1.5 — input gate

**The rule:** every ✓ requires a quoted source. **No ? or ✗ row may survive into drafting** — Phase 2 exists to close them, so an open row routes you into interrogation rather than blocking you where you stand. Phase 3 is the step that's unreachable while any row is still ? or ✗. Fail-closed.

Output the eight-row table verbatim to the developer with marks and citations filled in, then carry it into PLAN.md's `## Planning Evidence` section.

**Phase 1.6 runs next in both branches — an all-✓ gap table does not exempt a feature from the security surface.** After it:

- **All ✓** — say "All eight checks pass with cited evidence. Surface section written. Proceeding to Phase 3 confirmation." Skip Phase 2 interrogation; the input is genuinely complete.
- **Any ? or ✗** — list the missing rows and proceed to Phase 2 to fill them. Phase 2 questions target only ? and ✗ rows. Don't sweep.

### Sycophancy guards

- A ✓ without a quoted source is invalid. If you can't cite it, mark ?.
- An issue body of "Add settings page for X" cannot mark Acceptance Criteria ✓ — there's nothing testable in there.
- A long developer prompt is not evidence of completeness. Length doesn't make a row ✓; only specifics do.
- "Edge cases will be handled during implementation" is ✗, not ✓.

Persisting the table is what makes the gate checkable. `plan-reviewer` reads PLAN.md, not the planning conversation — a checklist that stays in chat proves nothing to anyone downstream. With it in `## Planning Evidence`, every ✓ can be held against the section of PLAN.md it was supposed to produce.

## Phase 1.6 — security & cost surface gate

**The rule:** six rows. For each row, the planner writes a **prose answer to the row's questions**, or marks `N/A — <one-line reason>`. Empty cells are not allowed; paraphrasing the questions back is not an answer. Fail-closed.

Question-shaped, not field-shaped — by design. The rows exist in their current shape because two agentic features scored ≥9/10 across every existing reviewer, shipped to human review, and immediately collected blockers + majors in exactly the surfaces below. Early drafts of this gate were field-shaped ("list every SDK, list every paid route...") and risked training the planner to fill in a form for the past, not think for the next feature. Questions transfer.

### Sycophancy guards specific to the security gate

These flag prose that *looks* like an answer but doesn't actually answer the row's questions:

- **"Defense in depth handles this"** without naming the specific defense for *this* surface is THIN. Name the file, the function, the const.
- **"Sanitizer will catch it"** is THIN unless the prose demonstrates the sanitizer's tag list includes every tag wrapping the field at every callsite. The pattern to look for is a single framework-tag constant on the repo's prompt-injection guard, escaped on every call — a per-call tag argument is the failure mode.
- **"Config has a timeout value"** is THIN; only "construction threads the timeout into the SDK *and* the arch test pins it" is OK. A timeout declared in config but not passed to `new Client(...)` is a fail.
- **"Audit log already records everything"** is THIN unless the answer enumerates *when written / what snapshotted / which outcomes recorded*. A logger that hard-codes `status: 'success'` fails the third question regardless of how many callers it has.
- **Walking only the happy path of partial failure.** Row 2 asks for *all three* shapes (local-then-external throws, external-then-local rolls back, concurrent collision wins-loses). An answer that only handles "external succeeds, local commits" is THIN — the failures are the whole point of the row.
- **"We always do that" / "It's a convention" / "Best practice handles this"** under Row 6 is THIN. The row's question is *which Escalation-Ladder level enforces it*. Tribal-knowledge defenses are L4 by default — name that explicitly with a trade-off, or escalate to L1/L2.
- **Operator-only signals on silent degradation.** Under Row 5, "the operator log will record it" is not a client-facing signal. The user cannot grep the operator log. If the answer doesn't name a client-facing surface (toast, sentinel, refresh-required flag) for a degradation path, the answer is THIN.
- **False N/A on LLM-touching features.** An LLM-touching feature cannot mark Row 1 N/A. Search the Approach for prompt-building calls, LLM SDK namespaces, managed-agent clients, vision endpoints, or MCP-tool argument handlers before accepting that N/A.

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
