---
name: review-branch
description: >
  Full-branch review of the current branch vs the integration branch. Spawns
  `runtime-integrity-reviewer`, `correctness-reviewer` and `precedent-reviewer` in parallel and
  reports in chat for `/pr` to consume in this session. Use whenever the user wants to review a
  branch, says "review my changes", "review branch", "check my code", "what did I change", "write
  the handoff", "branch review", "review handoff", or is about to open a PR. **Chat only.** `/pr`
  offers to run this skill when this session has no review for current HEAD.
---

# Review Branch

Spawn the repository's three finders (bundled with this plugin) against the full branch diff and
report in chat. `/pr` may consume this session's report when its `Reviewed against commit:` sha
matches HEAD.

This skill reads `integration_branch` (Step 1) and `plan_root` / `bug_root` (Step 2) from
`.claude/project-context.md` — see this plugin's README for how that file and its notation work.

## The lanes

Every finder answers exactly one question and carries its own sections of the hunting corpus
in [`references/corpus/`](references/corpus/_preamble.md). All three run **always**, on every
branch — plan or no plan, feature or bug. None of them scores, ranks, or applies a waiver.
They return tagged findings and a `checked` list. This skill synthesizes those reports in
chat. The parent session sees them and decides what to do.

- **`runtime-integrity-reviewer`** — *Does this branch fail without anyone being told, or
  permit what the base refused?* Security & cost surface, Runtime data-flow, Contract &
  boundary integrity, plus the silent-failure and security lane focus.
- **`correctness-reviewer`** — *Does the changed code do the wrong thing on a path the tests
  never take?* Runtime-state simulation, Sins of omission, Test disciplines (diff-gated on
  test files), plus the correctness lane focus.
- **`precedent-reviewer`** — *Does this match what's already written down?* Recorded rulings,
  Sibling precedent, CI-config awareness.

The finder contract every lane follows — context, the finding shape, the three tags, method,
voice — is [`references/finder-base.md`](references/finder-base.md).

User-facing text a branch ships — guides, API docs, legal pages, generated LLM corpora, skill
docs — has no reviewer of its own. `correctness-reviewer`'s promised-behaviour rule (Sins of
omission) checks it on every branch, whichever paths the diff touches.

## When this skill runs

- User invokes it directly (`/review-branch`, "review my changes", etc.).
- `/pr` Step 4 finds no review in this session for current HEAD (or only a stale one) and offers
  to run this first.

## Step 1: Gather branch context

Resolve `<integration-branch>` — `integration_branch` from `.claude/project-context.md` if set,
otherwise auto-detect (`origin/development`, `origin/develop`, then the remote's default branch)
— the same detection `worktree` uses.

Run these in parallel:

- `git branch --show-current`
- `git status --short`
- `git rev-parse --short HEAD`
- `git diff --stat origin/<integration-branch>...HEAD`

If `origin/<integration-branch>` is unavailable, fall back to `<integration-branch>...HEAD` and
note that in the chat report. You do not need to pull the full diff into this context — each
finder takes its own diff. Pulling it here only burns the orchestrator's window.

Resolve `<skill dir>` — this skill's own directory, which the finders need to read
`references/finder-base.md` and the corpus — in this order: checked-in copy, then this plugin's
install, then a user-level install. Keep the first match:

```bash
skill_dir=
[ -d .claude/skills/review-branch ] && skill_dir=$(cd .claude/skills/review-branch && pwd)
if [ -z "$skill_dir" ]; then
  for d in "$HOME"/.claude/plugins/cache/*/core-skills/*/skills/review-branch; do
    [ -d "$d" ] && skill_dir=$d
  done
fi
[ -z "$skill_dir" ] && [ -d "$HOME/.claude/skills/review-branch" ] && skill_dir="$HOME/.claude/skills/review-branch"
echo "skill_dir=$skill_dir"
```

No match: stop and say so — a finder without its contract and corpus has nothing to hunt with.

## Step 2: Resolve the plan or bug directory (read only)

Use the canonical algorithm in
[`plan-directory.md`](../../references/plan-directory.md) (shipped with this plugin, shared with
`next`, `task-writer` and `catchup`), under `plan_root` then `bug_root` (defaults `docs/plans`,
`docs/bugs`).

- **`<plan-root>/<slug>/` exists** → read `PLAN.md` / `DECISIONS.md` / `WIREFRAMES.md` /
  `TASKS.md` if present. Report in chat. Write nothing.
- **`<bug-root>/<slug>/` exists** (bug branch) → read `BUG.md` if present. This review is
  **optional on bug branches** — `bug-fix-verifier` is their gate, and `/pr` never asks for
  this run there. It runs when a developer explicitly wants it.
- **Neither exists** → still spawn the finders; report in chat only.

Write nothing in any case.

## Step 3: Spawn the finders in parallel

Send all three `Agent()` calls in a **single message** so they run concurrently. Do not fall
back to sequential spawning — if parallel spawning is unavailable in this environment, stop
and say so. There is no trigger to resolve: every lane runs on every diff, and a section that
does not apply is reported in the finder's `## Checked`, never skipped.

```
Agent({
  subagent_type: "runtime-integrity-reviewer",
  prompt: `Full-branch review, runtime-integrity lane.

Skill dir: <skill dir resolved in Step 1>
Plan directory: <plan-root>/<slug>/   (or <bug-root>/<slug>/, or "none")
Diff base: <the base resolved in Step 1 — origin/<integration-branch>, or <integration-branch> on fallback>

FIRST: read <skill dir>/references/finder-base.md, then your three corpus sections under
<skill dir>/references/corpus/. Return ## Findings and ## Checked only, in the finder shape.
No score, no severity, no waiver applied.`
})

Agent({
  subagent_type: "correctness-reviewer",
  prompt: `Full-branch review, correctness lane.

Skill dir: <skill dir resolved in Step 1>
Plan directory: <plan-root>/<slug>/   (or <bug-root>/<slug>/, or "none")
Diff base: <the base resolved in Step 1 — origin/<integration-branch>, or <integration-branch> on fallback>

FIRST: read <skill dir>/references/finder-base.md, then your three corpus sections under
<skill dir>/references/corpus/. Return ## Findings and ## Checked only, in the finder shape.
No score, no severity, no waiver applied.`
})

Agent({
  subagent_type: "precedent-reviewer",
  prompt: `Full-branch review, precedent lane.

Skill dir: <skill dir resolved in Step 1>
Plan directory: <plan-root>/<slug>/   (or <bug-root>/<slug>/, or "none")
Diff base: <the base resolved in Step 1 — origin/<integration-branch>, or <integration-branch> on fallback>

FIRST: read <skill dir>/references/finder-base.md, then your three corpus sections under
<skill dir>/references/corpus/. Return ## Findings and ## Checked only, in the finder shape.
No score, no severity, no waiver applied.`
})
```

The go-line carries variables and the read order, never a rule. A rule stated here is a second
home for it, and the second home drifts.

## Step 4: Synthesize in chat

Report in this conversation. Do not write a file. Use this exact structure so `/pr` can match
the sha against HEAD:

```markdown
# Branch Review Handoff

> Reviewed by **Claude** on YYYY-MM-DD against commit `<short-sha>`.

## Metadata
- Reviewer: Claude
- Branch: `<branch-name>`
- Base diff: `origin/<integration-branch>...HEAD`
- Reviewed against commit: `<short-sha>`
- Plan directory: `<plan-root>/<slug>` (or `<bug-root>/<slug>`, or none)
- Generated: YYYY-MM-DD
- Working tree state: clean / dirty

## Executive Summary
- 2-4 sentences on overall branch state.
- Findings: N across the three lanes

## Runtime Integrity Review
- Findings:
  1. `file:line` — claim — consequence — tags — concrete next step
- Checked: <its ## Checked, verbatim>
- Boundary: scope of this review pass

## Correctness Review
- Findings:
  1. `file:line` — claim — consequence — tags — concrete next step
- Checked: <its ## Checked, verbatim>
- Boundary: scope of this review pass

## Precedent Review
- Findings:
  1. `file:line` — claim — consequence — tags — concrete next step
- Checked: <its ## Checked, verbatim>
- Boundary: scope of this review pass

## Required Fixes Before PR
1. …   (write `None.` when there are none — do not pad this list)

## Decisions Needed
1. …   (only real unresolved choices — not a question dump. `None.` is the common case.)
```

### Synthesis rules

- **Synthesize — don't paste three reports.** If two lanes land on the same site, state it once
  under the lane whose question it answers.
- Every finding needs `file:line` + claim + a concrete next step. Keep the finder's tags on
  the line so the parent session can read them. Do not route on them.
- If a lane had no findings, write `Findings: none`. Do not invent work to fill the list.
- **`Required Fixes Before PR` is the parent's synthesis of what it would fix**, not a tag
  router. A finding the author may reasonably skip is not a required fix. Roughly a quarter
  of branches have a genuinely non-empty list; if yours is non-empty on most runs, the bar
  has slipped.
- **`Decisions Needed` is the only place to ask the developer** — a real design call, not
  every finding. Unambiguous defects are the parent session's to act on after this report.
- Do not verify, dedupe, waive, or emit READY / NEEDS WORK. This skill reports; the parent
  session decides.
- Do not modify application code in this skill. The chat report is the only deliverable.

## Step 5: Report back

The Step 4 block **is** the report. Also state in chat:

- Finding count per lane.
- The `Reviewed against commit:` sha (must equal `git rev-parse --short HEAD`).
- If `Required Fixes` is non-empty, list them and recommend fixing before `/pr`.

Nothing from this report goes in the PR body; the pushed code is the record.

## Constraints

- Read-only on application code. Report in chat.
- Do not create commits, branches, or PRs from this skill.
- Do not skip the parallel-spawn requirement — if spawning fails, stop and report rather than
  running one agent sequentially.
