# Review file format — frozen contract

Branch-review runners write a structured file beside the plan artifacts. This format is **frozen**: any runner — `/review-branch` (this skill) or a consumer-side equivalent — must produce a file conforming to this shape so `/pr` (and any other downstream consumer) can parse output identically without runner-specific logic.

A runner owns its own file: it overwrites that file on re-run and never touches another runner's file.

## File location and naming

- Path: `<plan-directory>/REVIEW_<RUNNER>.md`
- `<plan-directory>` is resolved via [`../../plan-feature/references/plan-directory.md`](../../plan-feature/references/plan-directory.md).
- `<RUNNER>` is the runner name in uppercase. The Claude-side runner writes `REVIEW_CLAUDE.md`. Consumer-side runners (e.g. a Codex equivalent) write `REVIEW_<THEIRNAME>.md`.
- If no plan directory exists, the runner does **not** write a file — it falls back to a chat-only review.

## Required fields

Every review file must contain, in this order:

1. **Header line** — exactly `> Reviewed by **<Runner>** on YYYY-MM-DD against commit `<short-sha>`.`
2. **Metadata block** with at minimum:
   - `Reviewer:` (runner name)
   - `Branch:`
   - `Base diff:` (e.g. `origin/<base>...HEAD`)
   - `Reviewed against commit:` — the short SHA of HEAD at review time. **This field is the staleness oracle**: downstream consumers compare it against current HEAD to decide whether the review is fresh.
   - `Plan directory:`
   - `Generated:` (date)
   - `Working tree state:` (`clean` / `dirty`)
3. **Executive Summary** — 2–4 sentences, plus threshold callouts (which reviewers meet / block / are not applicable).
4. **Per-reviewer sections** — one section per reviewer that ran, in this order: Acceptance Review, Simplicity Review, Silent Failure Review, Efficiency Review.
5. **Required Fixes Before PR** — numbered.
6. **Decisions Needed** — numbered (only real unresolved choices, not a question dump).
7. **Final Verdict** — `Ready for PR` or `Fix review findings first`.

## Per-reviewer section shape

Always-on reviewers (Acceptance, Simplicity) include:

- `Score: X / 10`
- `Verdict:` — reviewer-specific (`PASS / NEEDS WORK` for Acceptance, `PASS / NEEDS SIMPLIFICATION` for Simplicity)
- `Threshold status:` — `meets threshold` / `below threshold`
- `Findings:` — numbered list, each with severity (`MAJOR`/`MINOR` or reviewer-equivalent), `file:line` citation, and concrete next step. `none` if empty.
- `Boundary:` — scope of this review pass

Acceptance Review additionally includes an `AC gaps:` numbered list (one entry per non-PASS acceptance criterion: AC number, one-line restatement, status, severity, citation, required fix).

Conditional reviewers (Silent Failure, Efficiency) additionally include:

- `Status:` — `included` / `not applicable`. When `not applicable`, `Findings:` may be `No new error-handling sites in diff` (or equivalent for Efficiency); do not invent findings.

## Default threshold

`>= 7 / 10` is the default pass threshold for every reviewer. Consumers may tune this in their adopted skill copy if a different bar is appropriate for their project, but the threshold field shape stays the same.

## Canonical template

Runners must produce output matching this structure. Field labels are exact — downstream parsing depends on them.

```markdown
# Branch Review Handoff

> Reviewed by **<Runner>** on YYYY-MM-DD against commit `<short-sha>`.

## Metadata
- Reviewer: <Runner>
- Branch: `<branch-name>`
- Base diff: `origin/<base>...HEAD`
- Reviewed against commit: `<short-sha>`
- Plan directory: `<plan-directory>`
- Generated: YYYY-MM-DD
- Working tree state: clean / dirty

## Executive Summary
- 2-4 sentences on overall branch state.
- Threshold: reviewers pass at `>= 7 / 10`
- Blocks threshold: <list of reviewers below 7, or "none">
- Meets threshold: <list of reviewers at 7 or above>
- Not run / not applicable: <specialists skipped because triggers didn't match>

## Acceptance Review
- Score: X / 10
- Verdict: PASS / NEEDS WORK
- Threshold status: meets threshold / below threshold
- Findings:
  1. `MAJOR` / `MINOR` — file:line — concrete next step
- AC gaps:
  1. `AC #N` — one-line restatement, status, severity, citation, required fix
- Boundary: scope of this review pass

## Simplicity Review
- Score: X / 10
- Verdict: PASS / NEEDS SIMPLIFICATION
- Threshold status: meets threshold / below threshold
- Findings: …
- Boundary: …

## Silent Failure Review
- Status: included / not applicable
- Score: X / 10
- Verdict: …
- Threshold status: …
- Findings: …  (or "No new error-handling sites in diff" when skipped)
- Boundary: …

## Efficiency Review
- Status: included / not applicable
- Score: X / 10
- Verdict: …
- Threshold status: …
- Findings: …
- Boundary: …

## Required Fixes Before PR
1. …

## Decisions Needed
1. …  (only real unresolved choices — not a question dump)

## Final Verdict
- Ready for PR / Fix review findings first
```

## Why this is frozen

- `/pr` (or any downstream consumer) reads any runner's output without runner-specific parsing.
- Consumers can swap runners without touching the PR flow.
- The `Reviewed against commit:` field gives every reader a uniform staleness oracle.
- Per-reviewer sections are positionally stable, so a downstream consumer can pluck any reviewer's score by section name without parsing prose.

Alternatives that were rejected:

- **Loose convention** — leave each runner free to format reviews differently. Forces every downstream consumer to handle N runner-specific shapes.
- **Consumer-defined per-project** — every project re-derives the format. Drift across consumers; no shared `/pr` parsing.
