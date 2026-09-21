# Core Skills

## Goal

A plugin bundling project-agnostic catalog skills, installed via this repo's marketplace
instead of copied by hand. Each skill's body is identical for every installer; anything
project-specific it needs is read at runtime from one file the consuming project owns:
`.claude/project-context.md`.

## `.claude/project-context.md`

One file per project, holding every fact any installed skill from this plugin needs — not
one file per skill. A missing file, or a missing field within it, means "use the generic
default" — a skill never fails just because the project hasn't set this up.

A starter template ships with this plugin at
[`references/project-context-template.md`](references/project-context-template.md). Copy it
to `.claude/project-context.md` in the project and fill in only the fields that project needs.

**Notation.** A skill below names the fields it reads inline, in backticks (e.g.
`integration_branch`) — that always means "read this field from `.claude/project-context.md`";
the skill states its own fallback for when the field, or the file itself, is absent. A code
block placeholder in hyphenated form (e.g. `<integration-branch>`) stands for that resolved
value, not the field's literal name. This paragraph is the one place that mechanism is
explained — an individual skill only needs to say *which* fields it reads and *what* it falls
back to, not re-explain the degrade-not-fail contract itself.

## Skills

| Skill | Description |
|-------|-------------|
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [worktree](skills/worktree/) | Cut a fresh git worktree: branch, deps, env files, project house rules, then hand back the path |
| [build-it](skills/build-it/) | Implement the last grill-me alignment: cut a worktree, write plan docs if chosen, build, run gates, open the PR |
| [commit](skills/commit/) | Small, focused commits matching this project's own message convention, + push |
| [grill-me](skills/grill-me/) | Interview the developer through AskUserQuestion before any code is written; ends with docs-or-not and build-or-stop |
| [memory-hygiene](skills/memory-hygiene/) | Audit the project memory store for stale, codified, duplicate entries; dry-run proposal, then sync worktree memory stores |
| [newbranch](skills/newbranch/) | Create a new branch from this project's integration branch; if an issue tracker is configured, resolve/create the issue and start work on it |
| [next](skills/next/) | Continue through TASKS.md — find next task, execute with TDD flow, mark done |
| [pr](skills/pr/) | Create a pull request with automatic issue feedback; gates on this session's `/review-branch` report (or `bug-fix-verifier`'s BUG.md verdict on a bug branch) and embeds the docs-accuracy verdict when the diff touches `doc_paths` |
| [research](skills/research/) | Run a research query, produce a structured markdown report, and file it so knowledge accumulates |
| [retro](skills/retro/) | Write a numbered retrospective capturing what went wrong, why, and what changed |
| [review-branch](skills/review-branch/) | Full-branch review vs the integration branch: runtime-integrity-reviewer + precedent-reviewer in parallel, joined by docs-accuracy-reviewer when the diff touches this project's `doc_paths`; reports in chat |
| [review-mcp-descriptions](skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for Tool Search discoverability |
| [shepard](skills/shepard/) | Drive one PR to green and answered: fix red CI, dispose every review finding, push once per cycle, arm a live watch |
| [sync-worktrees](skills/sync-worktrees/) | Sync every secondary git worktree with the primary: env files, dependencies, optional fast-forward |
| [task-writer](skills/task-writer/) | Break down an approved PLAN.md into phased TASKS.md with a self-administered coverage checklist |
| [wireframe](skills/wireframe/) | Generate WIREFRAMES.md (ASCII layouts, design tokens, interaction specs) from PLAN.md; self-gated by the bundled wireframe-reviewer agent |

## Agents

Plugins bundle agent definitions the same way they bundle skills — `agents/` at the plugin
root, auto-discovered, no `plugin.json` entry needed.

| Agent | Description |
|-------|-------------|
| [docs-accuracy-reviewer](agents/docs-accuracy-reviewer.md) | Grade every claim in the user-facing text a branch ships against the code it ships; spawned by `/review-branch` when the diff touches this project's `doc_paths` |
| [precedent-reviewer](agents/precedent-reviewer.md) | Check a branch against the repo's standing rules, sibling implementations, and its own plan prose; spawned always by `/review-branch` |
| [runtime-integrity-reviewer](agents/runtime-integrity-reviewer.md) | Check a branch for invariants that only break across the whole system — transactions, concurrency, lifecycle, silent failure; spawned always by `/review-branch` |
| [wireframe-reviewer](agents/wireframe-reviewer.md) | Scores WIREFRAMES.md on screen coverage, token validity, component references, internal consistency, and AC traceability; spawned by `/wireframe` |

## Design record

`docs/plans/plugin-skills-rework/` in the [claude-2 catalog](https://github.com/script-development/claude)
tracks the decisions behind this plugin — why `.claude/project-context.md` exists, why skills
are bundled into one plugin, and the workflow for converting the next catalog skill.
