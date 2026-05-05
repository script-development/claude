---
name: review-branch
description: >
  Multi-agent review of the current branch vs the base branch. Spawns acceptance +
  simplicity (+ conditional silent-failure / efficiency) reviewers in parallel and
  synthesizes the output into `<plan-directory>/REVIEW_CLAUDE.md` for `/pr` to consume.
  Use whenever the user wants to review a branch, says "review my changes", "review
  branch", "check my code", "what did I change", "write the handoff", "branch review",
  "review handoff", or is about to open a PR and wants the review artifact first.
  **Writes a file** — if there's no plan directory, falls back to a lightweight
  chat-only review and nothing is written.
---

# Review Branch

Spawn the project's canonical reviewer agents against the full branch diff and
synthesize their output into `REVIEW_CLAUDE.md` beside the plan artifacts. The
output conforms to the frozen contract in
[`references/review-file-format.md`](references/review-file-format.md), so any
downstream consumer (`/pr`, etc.) can parse the file without runner-specific
logic.

## When this skill runs

- User invokes it directly (`/review-branch`, "review my changes", etc.).
- `/pr` finds no fresh Claude review (or finds only a stale one) and offers to
  run this first.

## Step 1: Gather branch context

Run these in parallel:

- `git branch --show-current`
- `git status --short`
- `git rev-parse --short HEAD`
- `git diff --stat origin/{{DEFAULT_BRANCH}}...HEAD`
- `git diff origin/{{DEFAULT_BRANCH}}...HEAD` — full diff, used for trigger grepping

If `origin/{{DEFAULT_BRANCH}}` is unavailable, fall back to `{{DEFAULT_BRANCH}}...HEAD`
and note that in the review file.

## Step 2: Resolve the plan directory

Use the canonical algorithm in
[`../plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md).
If no plan directory exists, **skip to the no-plan fallback** at the bottom of
this skill — do not spawn reviewers, do not write `REVIEW_CLAUDE.md`.

When a plan directory is found, read the files that exist:

- `PLAN.md`
- `DECISIONS.md`
- `WIREFRAMES.md`
- `TASKS.md`

Also check for any sibling `REVIEW_<RUNNER>.md` from a different runner — you do
not touch those, but their presence and `Reviewed against commit:` value are
useful context for the Step 6 summary.

## Step 3: Decide which reviewers to spawn

**Always spawn:**

- `acceptance-reviewer` (full branch)
- `simplicity-reviewer` (full branch)

**Conditionally spawn** — grep the branch diff for trigger patterns. The lists
below are catalog defaults; tune them for the consumer's stack on adoption
(prune patterns that don't apply, add stack-specific ones that do):

- `silent-failure-hunter` — if diff matches any of:
  `catch (`, `try {`, `rescue(`, `\.catch\(`, `Log::error`, `Log::warning`,
  `throw new`, `console\.error`, `console\.warn`, `addErrorToast`
- `efficiency-hunter` — if diff matches any of:
  `foreach`, `->each\(`, `->map\(`, `->with\(`, `EAGER_LOAD`, `DB::`, `for (`,
  `\.map\(`, `\.filter\(`, `\.reduce\(`, `\.forEach\(`, `await `, `Promise\.all`,
  `computed\(`, `watch\(`, `v-for`

## Step 4: Spawn reviewers in parallel

Send every applicable `Agent()` call in a **single message** so they run
concurrently. Do not silently fall back to sequential spawning — if parallel
spawning is unavailable in this environment, stop and say so instead.

```
Agent({
  subagent_type: "acceptance-reviewer",
  prompt: `Full-branch acceptance criteria audit.

Plan directory: <plan-directory>

Check ALL acceptance criteria in PLAN.md against the full branch diff
(git diff origin/{{DEFAULT_BRANCH}}...HEAD). Report PASS / PARTIAL / FAIL / SKIP
per criterion with file:line citations and required fixes.`
})

Agent({
  subagent_type: "simplicity-reviewer",
  prompt: `Full-branch simplicity audit.

Plan directory: <plan-directory>

Check the full branch diff for: reuse violations, DECISIONS.md drift,
scope creep, over/under-abstraction, dead scaffolding, anti-patterns.
Report BLOCKER/MAJOR/MINOR findings with file:line and fixes. Do NOT
re-check acceptance criteria.`
})

// CONDITIONAL — only if diff grep matched error-handling patterns
Agent({
  subagent_type: "silent-failure-hunter",
  prompt: `Full-branch silent-failure audit.

Plan directory: <plan-directory>

Check diff's error-handling sites for: empty/near-empty catches, over-broad
catches, fallbacks masking problems, missing user feedback, service/Action-layer
swallowing of infrastructure exceptions, thin logging. Report BLOCKER/MAJOR/MINOR
with file:line and code-example fixes.`
})

// CONDITIONAL — only if diff grep matched perf-sensitive patterns
Agent({
  subagent_type: "efficiency-hunter",
  prompt: `Full-branch efficiency audit.

Plan directory: <plan-directory>

Check diff for: N+1 queries, missing/incomplete eager-loading, sequential await
that could be Promise.all, wasteful recomputation, unnecessary allocations,
query-shape issues. Report BLOCKER/MAJOR/MINOR with file:line and fixes.`
})
```

## Step 5: Synthesize to REVIEW_CLAUDE.md

Write `<plan-directory>/REVIEW_CLAUDE.md`, overwriting any existing
`REVIEW_CLAUDE.md` (Claude-authored reviews are regenerated each run). **Do not
touch any sibling `REVIEW_<OTHER>.md`** — those belong to their own runner.

The output **must conform** to
[`references/review-file-format.md`](references/review-file-format.md). That file
is the frozen contract: section names, field labels, the `Reviewed against
commit:` line, default `>= 7 / 10` threshold, and the canonical template all
live there. Read it before writing.

### Synthesis rules

- Synthesize — don't paste four independent reports.
- Every finding needs: severity + `file:line` citation + concrete next step.
- Restate every non-pass AC inline so the review is readable without `PLAN.md`.
- If a reviewer had no findings, say `Findings: none`.
- If a specialist wasn't triggered, mark `Status: not applicable` — don't invent
  findings.
- Do not modify application code in this skill. The review file is the only
  deliverable.

## Step 6: Report back

Summarize in chat:

- Which reviewers ran, which were skipped.
- Score per reviewer + overall verdict.
- Path to the written `REVIEW_CLAUDE.md`.
- If a sibling `REVIEW_<OTHER>.md` exists, note it — quote the `Reviewed against
  commit:` value so the user knows whether the two runners are in sync against
  HEAD.
- If any reviewer is below threshold, list Required Fixes and recommend
  addressing them before `/pr`.

## No-plan fallback (Step 2 found nothing)

When there's no plan directory, skip the reviewer agents and the file write. Do
a lightweight chat-only review instead:

1. `git diff origin/{{DEFAULT_BRANCH}}...HEAD --name-only` to get changed files.
2. Review each file's diff for: possible bugs, inconsistencies, dead code,
   coverage gaps, and the project's idiomatic patterns.
3. Output a numbered actionable list with `[file.ts:42](file.ts#L42)`-style
   citations, priority level (Critical/High/Medium/Low), and concrete fix
   suggestion.

This is the lightweight flow for drive-by branches where the agent flow would
be overkill.

## Constraints

- Read-only on application code: do not modify anything outside `REVIEW_CLAUDE.md`.
- Do not create commits, branches, or PRs from this skill.
- Do not touch any sibling `REVIEW_<OTHER>.md`.
- Do not skip the parallel-spawn requirement — if spawning fails, stop and
  report rather than running one agent sequentially.
