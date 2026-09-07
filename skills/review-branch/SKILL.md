---
name: review-branch
description: >
  Full-branch review of the current branch vs the base branch. Spawns
  `runtime-integrity-reviewer` and `precedent-reviewer` in parallel — joined by
  `docs-accuracy-reviewer` when the diff touches user-facing text — and reports in chat for
  `/pr` to consume in this session. Use whenever the user wants to review a branch, says
  "review my changes", "review branch", "check my code", "what did I change", "write the
  handoff", "branch review", "review handoff", or is about to open a PR. **Chat only.** `/pr`
  re-runs this skill when this session has no review for current HEAD.
---

# Review Branch

Spawn the repository's canonical reviewer agents against the full branch diff and report in
chat. `/pr` consumes this session's report when its `Reviewed against commit:` sha matches HEAD.

## The questions

Every reviewer at this gate answers exactly one question:

- **`runtime-integrity-reviewer`** — *Does this branch break an invariant that spans it?*
  External calls inside DB transactions, missing concurrency guards, commit-then-act ordering,
  resource-lifecycle leaks, unbounded or repeated work, failures that never surface.
- **`precedent-reviewer`** — *Does this match what's already written down?*
  Conformance to the repo's standing rules (every `CLAUDE.md`, plus an ADR set where one
  exists), sister-implementation drift, cross-stack contracts, and plan prose vs code.
- **`docs-accuracy-reviewer`** — *Does the user-facing text this branch ships hold in its code?*
  Guides, API docs, legal pages, generated LLM corpora and skill docs, graded per claim.

The first two run **always**, on every branch — plan or no plan, feature or bug. Each agent
carries its own scope, severity weighting and score calibration in its agent definition; this
skill only orchestrates and synthesizes.

`docs-accuracy-reviewer` is the one **path-triggered** reviewer: it runs when the diff touches
`{{DOC_PATHS}}`, and not otherwise, because a branch that ships no user-facing text makes no
claim for it to grade. Trigger *greps* — patterns that guess at a diff's semantics — are not
used here: they can silently skip a reviewer when code error-handles through an unnamed helper.
A directory prefix has no such failure mode: a file either sits under one or it does not. A `**`
glob does — see the warning in Step 3.

## When this skill runs

- User invokes it directly (`/review-branch`, "review my changes", etc.).
- `/pr` Step 4 finds no review in this session for current HEAD (or only a stale one) and offers
  to run this first.

## Step 1: Gather branch context

Run these in parallel:

- `git branch --show-current`
- `git status --short`
- `git rev-parse --short HEAD`
- `git diff --stat origin/{{DEFAULT_BRANCH}}...HEAD`

If `origin/{{DEFAULT_BRANCH}}` is unavailable, fall back to `{{DEFAULT_BRANCH}}...HEAD` and note
that in the chat report. You do not need to pull the full diff into this context — each agent
takes its own diff. Pulling it here only burns the orchestrator's window.

## Step 2: Resolve the plan or bug directory (read only)

Use the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md).

- **`docs/plans/<slug>/` exists** → full review. Read `PLAN.md` / `DECISIONS.md` /
  `WIREFRAMES.md` / `TASKS.md` if present. Report in chat. Write nothing.
- **`docs/bugs/<slug>/` exists** (bug branch) → full review. Read `BUG.md` if present. Report in
  chat. Write nothing. This review is **optional on bug branches** — `bug-fix-verifier` is their
  gate, and `/pr` never asks for this run there. It runs when a developer explicitly wants it.
- **Neither exists** → still spawn the agents; report in chat only.

The directory is read for context. Nothing in it is written by this skill, on any branch shape.

## Step 3: Spawn the reviewers in parallel

Send every `Agent()` call in a **single message** so they run concurrently. Do not fall back to
sequential spawning — if parallel spawning is unavailable in this environment, stop and say so.

Before composing the message, resolve the docs trigger once:

```bash
git diff --name-only <base>...HEAD -- {{DOC_PATHS}}
```

Non-empty output means the third block below joins the message.

**Use the `{{DOC_PATHS}}` pathspecs literally.** They are directory prefixes, not `**` globs:
git reads `<prefix>/**/*.md` as requiring an intervening directory, so it silently misses
`<prefix>/README.md` and every other file sitting directly under `<prefix>`. A trigger that
answers "no text changed" when text changed is the exact failure this gate exists to prevent.
`{{DOC_PATHS}}` may also carry `:(exclude)` pathspecs for a sub-tree another reviewer owns —
pass those through unchanged.

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

Run your checks against the full branch diff: conformance to the repo's
standing rules (every CLAUDE.md, plus an ADR set where one exists),
sister-implementation drift, cross-stack contracts, and plan prose vs code.
Name the precedent (ADR number, CLAUDE.md section, sibling file:line, or the
PLAN.md line) on every finding.
Do NOT flag runtime behaviour — transactions, races, N+1 and silent failure
belong to runtime-integrity-reviewer.`
})
```

Add this third block **only** when the trigger command above returned a path:

```
Agent({
  subagent_type: "docs-accuracy-reviewer",
  prompt: `Full-branch docs-accuracy audit.

Plan directory: docs/plans/<slug>/   (or docs/bugs/<slug>/, or "none")
Diff base: <the base resolved in Step 1 — origin/{{DEFAULT_BRANCH}}, or {{DEFAULT_BRANCH}} on fallback>
Text files in this diff: <the paths the trigger command returned>

Grade every claim in that text against the code this branch ships, and run the
inverse pass: sentences the diff did not touch that its code change made false.
Report per-claim verdicts with the quoted sentence, the file and symbol you read,
and a suggested rewrite. Flag compliance claims separately.
Do NOT review CLAUDE.md files, docs/plans/ or docs/bugs/ — those are
precedent-reviewer's. Do NOT review any path {{DOC_PATHS}} excludes.`
})
```

## Step 4: Synthesize in chat

Report in this conversation. Do not write a file. Use this exact structure so `/pr` can match
the sha against HEAD:

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
- Boundary: scope of this review pass

## Docs Accuracy Review
(Omit this whole section when the diff touches no `{{DOC_PATHS}}` file.)
- Score: X / 10
- Verdict: PASS / NEEDS WORK
- Threshold status: meets threshold / below threshold
- Findings:
  1. `SOURCED` / `PARTIAL` / `OVER-GENERALISED` / `FABRICATED` / `SOURCE-MISSING` — `path` ›
     heading — the quoted sentence, the code that fails to back it, the suggested rewrite
- Compliance claims: <flagged claims, or "none"> (orthogonal — does not affect the score)
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
- Do not modify application code in this skill. The chat report is the only deliverable.

## Step 5: Report back

The Step 4 block **is** the report. Also state in chat:

- Score per reviewer + overall verdict.
- The `Reviewed against commit:` sha (must equal `git rev-parse --short HEAD`).
- If any reviewer is below threshold, list Required Fixes and recommend fixing before `/pr`.
- Whether `docs-accuracy-reviewer` ran, and if it did not, that the diff touched no user-facing
  text. `/pr` asks for this either way, so say it explicitly rather than leaving its absence to
  be read as a skip.

Hand the docs-accuracy report back in full rather than summarised — `/pr` embeds **that**
section in the PR body when the docs trigger fired. Runtime Integrity and Precedent scores stay
in chat. They do not go in the PR body.

## No-directory fallback (Step 2 found nothing)

When there's no `docs/plans/<slug>/` or `docs/bugs/<slug>/`:

1. Spawn the always-on agents anyway — neither requires `PLAN.md`. `precedent-reviewer` anchors
   on the repo's standing rules; `runtime-integrity-reviewer` anchors on the repo's conventions.
   The docs trigger is independent of the directory: if it fired, the third agent joins here too.
2. Report their findings inline in chat, `precedent-reviewer`'s standing-rule findings first so
   security-shaped gaps surface before line-level nits.

Nothing changes about the deliverable — this skill reports in chat on every branch shape. The
fallback exists only to say which context the agents get, not whether a file is written.

## Constraints

- Read-only on application code. Report in chat. That includes the text
  `docs-accuracy-reviewer` grades — it proposes rewrites; the author applies them.
- Do not create commits, branches, or PRs from this skill.
- Do not skip the parallel-spawn requirement — if spawning fails, stop and report rather than
  running one agent sequentially.
