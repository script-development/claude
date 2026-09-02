# Quality gates — Phase 0 (right-size) and Phase 4 (alignment)

`/task-writer` runs two fail-closed gates that bracket the breakdown work.
The tables themselves live in SKILL.md so they fire reliably. This document
carries the rationale, sycophancy guards, and operating notes — load it
when you reach a gate.

## Why two gates

Both gates exist because the path of least resistance — "this looks
crisp, let me draft TASKS.md and we can iterate" — is the most expensive
failure mode in task breakdown. A premature breakdown forces the
implementer through pointless ceremony on small plans (Phase 0 catch);
a complete-looking breakdown can still miss acceptance criteria (Phase 4
catch). Two gates, two failure modes.

## Phase 0 — right-size gate

**The rule:** if **all three** thresholds are met, output the redirect
and stop. The developer can override and request TASKS.md anyway, but the
default branches to `/implement-plan`. Fail-closed.

### Sycophancy guards

- "I usually write TASKS.md so let's do that" is not a reason to bypass
  the redirect. Surface the calibration: ≤ 8 Approach steps + single
  coordinated slice + one-PR shape genuinely doesn't benefit from the
  per-task overhead. The developer may still say "yes, write it" — but
  they should be making that choice with the threshold visible, not by
  default.
- "The plan is complex" is not evidence. Quote the Approach step count
  and the touched layers. Complexity is felt; thresholds are counted.
- A long PLAN.md is not a signal to skip Phase 0. PLAN.md length tracks
  how thoroughly the plan was written, not how many integration boundaries
  it crosses.

### Calibration evidence

Thresholds derived from auditing recent plans against TASKS.md presence as
ground truth. Earlier stricter rules (≤ 5) wrongly forced TASKS.md on
small mechanical plans; the looser ≤ 8 with coordinated-slice softening
matches the empirical signal. Nested step counting is mandatory because
4 outer steps can mask 6 sequential mutation sites — the 4-vs-9 cliff
edge is where the gate matters most.

### Override path

If the developer says "TASKS.md anyway" — write it, but **cite the
developer's reason** in TASKS.md so future readers understand why a small
plan got the full treatment. Reasons usually fall into:

- Risk gate (schema migration on prod data, auth changes)
- Multi-PR coordination (the plan is one slice but ships in two PRs)
- Stakeholder visibility (a reviewer wants per-task progress)

Without the reason, a future Claude encountering this TASKS.md will think
the Phase 0 gate failed and try to "fix" it.

## Phase 4 — coverage gate

**The rule:** walk the self-check in `verification.md` and fix every unchecked
row before handing off. Fail-closed, and self-administered — no agent audits
this afterwards, so honesty here is the whole gate.

### Sycophancy guards specific to the output

You are checking your own work, which is exactly the condition under which
"close enough" wins. Three guards:

- **"Most of the ACs are covered" is not a passing answer.** Classify each AC
  as COVERED / IMPLICIT / MISSING. **Implicit is a yellow flag** — the task
  probably covers the AC but doesn't say so. The fix is usually adding an
  `**Acceptance Criteria:**` line, not creating a new task.
- **Three IMPLICIT verdicts is fine to ship. One MISSING is not** — least of
  all when it's rationalised as "the developer can figure it out."
- **Write the counts down, not an adjective.** "8/8 acceptance criteria,
  24/24 planned files" is checkable by the next reader. "Coverage looks good"
  is what this gate produces when it isn't really being run.

### What to verify

Read PLAN.md and TASKS.md side by side:

1. Every acceptance criterion maps to at least one task's
   `**Acceptance Criteria:**` field
2. Every wireframe screen (if `WIREFRAMES.md` exists) has a task that
   implements it
3. Every PLAN.md "in scope" item is covered by a task
4. No task introduces work outside the plan's scope (scope creep)
5. Every planned file appears in some task's `**Touches:**`
6. Critical edge cases from PLAN.md are addressed by task action items
   or test descriptions

Don't assess task quality, TDD ordering, or whether the breakdown reads well.
Nothing downstream does either — TASKS.md is scaffolding for execution, not a
reviewed artifact. The pre-PR reviewers grade the code, not the plan for
writing it.

### When you find scope creep

A task that doesn't trace back to the plan has two valid responses:

1. **Plan was incomplete** — the task is real work the plan missed. Update
   PLAN.md to include it, with the developer's confirmation.
2. **Task is genuine creep** — it's doing work the plan didn't ask for. Remove
   it from TASKS.md.

Don't paper over it by adding the task to the plan retroactively without that
confirmation — it erodes the plan's role as the contract.

### Audit trail

Record the coverage counts in a `## Review Notes` section at the bottom of
TASKS.md (template in `SKILL.md` Phase 4), so a future reader sees the coverage
without re-deriving it. Replace it on re-runs rather than appending a second
one.
