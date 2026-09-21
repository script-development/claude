---
name: build-it
description: >
  Implement the last /grill-me alignment in any repository: cut a fresh worktree via this
  plugin's /worktree skill, write the alignment into docs/plans/<slug>/ (PLAN.md + DECISIONS.md,
  or this project's own convention from .claude/project-context.md) on the new branch when docs
  were chosen at the end of the grill, implement exactly the in-scope list, run the project's
  gates, commit, push, and open a PR to the integration branch, adding the project's review label
  if the project or the user's settings name one. Use when the user says "build it", "go build
  it", "/build-it", "implement the alignment", "implement what we discussed", or confirms a grill
  go-ahead.
---

# Build — ship the grill alignment

This skill writes code. It consumes a `/grill-me` alignment from this conversation and ships it
as a PR. It does not re-interview. If a decision is still open, stop and send them back to
`/grill-me`.

This skill owns no project-specific decisions itself — it always defers to `/worktree`'s
hand-back for the integration branch, the docs convention, and house rules, and to the project's
own `CLAUDE.md`/`/pr` skill for anything PR-shaped. See Steps 1, 2, 4, and 6 below.

## Preconditions

You need a closed alignment in this conversation — the Phase 3 block from `/grill-me`:

```
Here's what we're aligned on:
- Building: …
- In scope: …
- Out of scope: …
- Key decisions: …
- Edge cases: …
- Patterns to follow: …
```

No alignment and `$ARGUMENTS` empty → stop: *"Nothing to build — `/grill-me` first."*
`$ARGUMENTS` may name a slug or an issue key. It does not replace the alignment.

**Docs choice**: `/grill-me`'s Phase 4 asked "docs or not". Use that answer. If this conversation has
an alignment but no docs answer (an old grill, a resumed session), ask it once now — one
`AskUserQuestion`, `No docs` recommended for small changes — then continue.

## 1 · Cut the worktree

Never implement in the checkout you were standing in. Invoke this plugin's **`worktree`**
skill — it owns repo detection, the integration branch, branch naming, the ignore guard, env
files, dependency install, and the project's house rules (from `.claude/project-context.md`, if
one exists). Give it the work's name: the issue key if the alignment has one, otherwise a slug
from the alignment's Building line.

Everything after this step runs against the worktree path it hands back (`$WT`). Follow the
house rules it reports. If `.claude/project-context.md` names a branch convention (a `feat/`
prefix, an issue-key format), `worktree` already applied it.

## 2 · Docs, if chosen

Skip entirely when the answer was **No docs**.

Otherwise write two files into the worktree, so they ride the new branch and land in the PR:

```
$WT/docs/plans/<slug>/PLAN.md
$WT/docs/plans/<slug>/DECISIONS.md
```

`<slug>` **must equal the branch name minus any `type/` prefix**. Skills that consume these docs
(e.g. `/implement-plan`, `/next`, `/pr`) derive the directory from the branch name — a
mismatched slug orphans the docs. If `.claude/project-context.md` sets `plan_dir`, follow that
convention instead of the default above.

- **PLAN.md** — the contract, straight from the alignment: `## Goal` (the Building line),
  `## Scope` (In / Out), `## Approach` (files and components in implementation order),
  `## Acceptance criteria` (verifiable pass/fail rows).
- **DECISIONS.md** — the reasoning: one entry per key decision — what was chosen, why, and the
  rejected alternative when one was discussed. Rejected proposals are the valuable part; they
  stop the next session from re-proposing them.

Write only what the grill actually settled. A section the interview never touched gets
`N/A — not discussed`, not invented content. In some projects these records do real work — a
reviewer that honours `docs/plans/**` decisions as waivers reads your Out-of-scope list — so a
decision recorded here that the grill never made is a forged waiver.

## 3 · Implement the alignment

Build exactly the in-scope list. Do not expand into the out-of-scope list. Follow the named
patterns from the alignment and the house rules the worktree hand-back reported (formatter
hooks, testing skills, style rules from the project's `CLAUDE.md`).

If the alignment names an issue key, keep it in the branch and the PR body. Do not create a new
issue.

If you change UI, verify it in the running app, not just in tests.

## 4 · Gates

Run the gates for the side you touched — `.claude/project-context.md`'s Worktrees → Gates table
when one exists, the project's `CLAUDE.md` gate block otherwise. Judge a test run by exit code
plus the test-files summary line, never the test count — a collection failure registers zero
tests while the count stays green.

A red gate is a fix, not a skip. Do not open a PR on a locally red suite.

## 5 · Commit and push

If the project has its own `/commit` skill, load it and follow it from `$WT`. Otherwise: small
focused commits, conventional subjects, then push. Either way, confirm afterwards that the
upstream is the feature branch — never the integration branch or the default branch.

## 6 · Open the PR

Base = the integration branch `/worktree` picked. Add the project's review label if the project
or the user's settings name one (the project's `/pr` skill or `CLAUDE.md`, or the user's global
`CLAUDE.md`):

```bash
gh pr create --base <integration> [--label "<review label>"] --title "<conventional subject>" --body "$(cat <<'EOF'
## Why

<issue key if any>. <one sentence from the alignment's Building line.>

## What

<the in-scope list; note the docs/plans/<slug>/ docs when written>

## Out of scope

<the alignment's out-of-scope list>

## Test plan

- [x] <the gates you ran>
- [ ] CI green
EOF
)"
```

If a named label does not exist yet, `gh label create "<review label>"` and retry; if that fails
on permissions, open the PR without it and say so. Never encode a personal label in a project.

Never `--force`. Never target the default branch when the project integrates on another branch.

## 7 · Hand back

Report the worktree path, the branch, the commit hashes, the PR URL, and whether docs were
written (with their path). Then stop.

## What this skill never does

- Never builds without a closed grill alignment.
- Never re-interviews — open decisions go back to `/grill-me`.
- Never writes into the checkout `/build-it` was invoked from.
- Never writes docs when the answer was No docs, and never invents doc content the grill
  didn't settle.
- Never opens a PR on a red gate, without attempting a named review label, or against a wrong
  base.
- Never force-pushes, and never pushes to the integration or default branch.
