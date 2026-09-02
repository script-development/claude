---
name: review-branch
description: >
  Two-agent review of the current branch vs the base branch. Spawns
  `runtime-integrity-reviewer` and `precedent-reviewer` in parallel and synthesizes their
  output into `docs/plans/<slug>/REVIEW_CLAUDE.md` for `/pr` to consume. Use whenever the
  user wants to review a branch, says "review my changes", "review branch", "check my code",
  "what did I change", "write the handoff", "branch review", "review handoff", or is about to
  open a PR and wants the review artifact first. **Writes a file** — if there's no plan or bug
  directory, falls back to a chat-only review and nothing is written.
---

# Review Branch

Spawn the repository's two canonical reviewer agents against the full branch diff and
synthesize their output into `REVIEW_CLAUDE.md` beside the plan artifacts.

## The two questions

Every reviewer at this gate answers exactly one of two questions:

- **`runtime-integrity-reviewer`** — *Does this branch break an invariant that spans it?*
  External calls inside DB transactions, missing concurrency guards, commit-then-act ordering,
  resource-lifecycle leaks, unbounded or repeated work, failures that never surface.
- **`precedent-reviewer`** — *Does this match what's already written down?*
  Conformance to the repo's standing rules (every `CLAUDE.md`, plus an ADR set where one
  exists), sister-implementation drift, cross-stack contracts, plan prose vs code, and drift
  from a plan-time approval.

Both run **always**, on every branch — plan or no plan, feature or bug. There are no trigger
patterns and no conditional specialists. Each agent carries its own scope, severity weighting
and score calibration in its agent definition; this skill only orchestrates and synthesizes.

## When this skill runs

- User invokes it directly (`/review-branch`, "review my changes", etc.).
- `/pr` Step 4 finds no fresh Claude review (or only a stale one) and offers to run this first.

## Step 1: Gather branch context

Run these in parallel:

- `git branch --show-current`
- `git status --short`
- `git rev-parse --short HEAD`
- `git diff --stat origin/{{DEFAULT_BRANCH}}...HEAD`

If `origin/{{DEFAULT_BRANCH}}` is unavailable, fall back to `{{DEFAULT_BRANCH}}...HEAD` and note
that in the review file. You do not need to pull the full diff into this context — each agent
takes its own diff. Pulling it here only burns the orchestrator's window.

## Step 2: Resolve the output directory

Use the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md).

- **`docs/plans/<slug>/` exists** → full review, write `REVIEW_CLAUDE.md` there.
- **`docs/bugs/<slug>/` exists** (bug branch) → full review, write `REVIEW_CLAUDE.md` there.
  Both agents run on bug branches; neither requires `PLAN.md`. Note this review is **optional
  on bug branches** — `bug-fix-verifier` is their gate, and `/pr` never asks for this artifact
  there. It runs when a developer explicitly wants it, and `/pr` will use it if it finds it.
- **Neither exists** → skip to the *no-directory fallback* at the bottom. Still spawn both
  agents; report in chat only, write nothing.

When a directory is found, read whichever of these exist: `PLAN.md`, `DECISIONS.md`,
`WIREFRAMES.md`, `TASKS.md`, `BUG.md`.

## Step 3: Spawn both reviewers in parallel

Send both `Agent()` calls in a **single message** so they run concurrently. Do not fall back to
sequential spawning — if parallel spawning is unavailable in this environment, stop and say so.

```
Agent({
  subagent_type: "runtime-integrity-reviewer",
  prompt: `Full-branch runtime-integrity audit.

Plan directory: docs/plans/<slug>/   (or docs/bugs/<slug>/, or "none")
Diff base: <the base resolved in Step 1 — origin/{{DEFAULT_BRANCH}}, or {{DEFAULT_BRANCH}} on fallback>

Run your six checks against the full branch diff: external calls inside DB
transactions, missing concurrency guards, commit-then-act ordering, resource
lifecycle leaks, unbounded or repeated work, and failures that never surface.
Report BLOCKER/MAJOR/MINOR with file:line and a concrete fix per finding.
Do NOT flag ADR violations, duplication, or plan-prose mismatches — those
belong to precedent-reviewer.`
})

Agent({
  subagent_type: "precedent-reviewer",
  prompt: `Full-branch precedent audit.

Plan directory: docs/plans/<slug>/   (or docs/bugs/<slug>/, or "none")
Diff base: <the base resolved in Step 1 — origin/{{DEFAULT_BRANCH}}, or {{DEFAULT_BRANCH}} on fallback>

Run your four checks against the full branch diff: conformance to the repo's
standing rules (every CLAUDE.md, plus an ADR set where one exists),
sister-implementation drift, plan prose vs code, and drift from any plan-time
Review Notes. Name the precedent (ADR number, CLAUDE.md section, sibling
file:line, or the PLAN.md line) on every finding.
Do NOT flag runtime behaviour — transactions, races, N+1 and silent failure
belong to runtime-integrity-reviewer.`
})
```

## Step 4: Synthesize to REVIEW_CLAUDE.md

Write `REVIEW_CLAUDE.md` into the directory from Step 2, overwriting any existing one
(reviews are regenerated each run).

Use this exact structure so `/pr` can parse the file without prose-reading:

```markdown
# Branch Review Handoff

> Reviewed by **Claude** on YYYY-MM-DD against commit `<short-sha>`.

## Metadata
- Reviewer: Claude
- Branch: `<branch-name>`
- Base diff: `origin/{{DEFAULT_BRANCH}}...HEAD`
- Reviewed against commit: `<short-sha>`
- Plan directory: `docs/plans/<slug>` (or `docs/bugs/<slug>`)
- Generated: YYYY-MM-DD
- Working tree state: clean / dirty

## Executive Summary
- 2-4 sentences on overall branch state.
- Threshold: reviewers pass at `>= 7 / 10`
- Blocks threshold: <reviewers below 7, or "none">
- Meets threshold: <reviewers at 7 or above>

## Runtime Integrity Review
- Score: X / 10
- Verdict: PASS / NEEDS WORK
- Threshold status: meets threshold / below threshold
- Findings:
  1. `BLOCKER` / `MAJOR` / `MINOR` — file:line — what breaks, under what conditions, concrete fix
- Boundary: scope of this review pass

## Precedent Review
- Score: X / 10
- Verdict: PASS / NEEDS WORK
- Threshold status: meets threshold / below threshold
- Findings:
  1. `BLOCKER` / `MAJOR` / `MINOR` — file:line — precedent cited (ADR-XXXX / CLAUDE.md section /
     sibling file:line / PLAN.md line) — concrete fix
- Drift: <drift findings, or "none">
- Boundary: scope of this review pass

## Required Fixes Before PR
1. …   (write `None.` when there are none — do not pad this list)

## Decisions Needed
1. …   (only real unresolved choices — not a question dump. `None.` is the common case.)

## Final Verdict
- Ready for PR / Fix review findings first
```

### Synthesis rules

- **Synthesize — don't paste two reports.** If both agents land on the same site, state it once
  under the reviewer whose question it answers.
- Every finding needs severity + `file:line` + a concrete next step.
- If a reviewer had no findings, write `Findings: none`. Do not invent MINORs to fill space.
- **`Required Fixes Before PR` means "this branch should not open a PR until these land."** A
  MINOR the author may reasonably skip is not a required fix. Roughly a quarter of branches have
  a genuinely non-empty list; if yours is non-empty on most runs, the bar has slipped.
- Do not modify application code in this skill. The review file is the only deliverable.

## Step 5: Report back

Summarize in chat:

- Score per reviewer + overall verdict.
- Path to the written `REVIEW_CLAUDE.md`.
- If either reviewer is below threshold, list Required Fixes and recommend fixing before `/pr`.

## No-directory fallback (Step 2 found nothing)

When there's no `docs/plans/<slug>/` or `docs/bugs/<slug>/`:

1. Spawn **both** agents anyway — neither requires `PLAN.md`. `precedent-reviewer` anchors on
   the repo's standing rules; `runtime-integrity-reviewer` anchors on the repo's conventions.
2. Report their findings inline in chat, `precedent-reviewer`'s standing-rule findings first so
   security-shaped gaps surface before line-level nits.
3. Write nothing. There is no directory to own the artifact.

## Constraints

- Read-only on application code: do not modify anything outside `REVIEW_CLAUDE.md`.
- Do not create commits, branches, or PRs from this skill.
- Do not skip the parallel-spawn requirement — if spawning fails, stop and report rather than
  running one agent sequentially.
