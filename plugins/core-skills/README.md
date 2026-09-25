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
[`references/project-context-template.md`](references/project-context-template.md). Run
[`/core-skills:install`](skills/install/) to create the file from it: it keeps only the fields
the skills installed in this project read, detects values from the repo, and asks
(AskUserQuestion) only for what it can't detect. It's additive, so re-run it after installing
another plugin from this marketplace (e.g. `kendo-pm`) to add that plugin's fields without
touching the ones already set. The file it writes holds only values and links to the template,
which stays the one place each field is documented: every skill reads the whole file, so
copied-in documentation would cost context on every read. Copying the template by hand still
works.

**One install skill, not one per plugin.** Every plugin from this marketplace reads the same file,
and its one template lives here; `kendo-pm` declares `core-skills` as a dependency, so this skill
is always present wherever `kendo-pm` is. The template's per-field `used by:` lists already say
which skills read each field, which is all `install` needs to scope the file to what's installed.

**Notation.** A skill below names the fields it reads inline, in backticks (e.g.
`integration_branch`) — that always means "read this field from `.claude/project-context.md`";
the skill states its own fallback for when the field, or the file itself, is absent. A code
block placeholder in hyphenated form (e.g. `<integration-branch>`) stands for that resolved
value, not the field's literal name. This paragraph is the one place that mechanism is
explained — an individual skill only needs to say *which* fields it reads and *what* it falls
back to, not re-explain the degrade-not-fail contract itself.

**Project reference files.** A project's own notes that a skill reads beside its shipped text —
hazards, a docs-sync map, filled-in issue examples, agent-ready calibration, shepard's repo
notes — live in the repo and are named under the one `references:` map in that file (e.g.
`references.hazards`). The plugin install directory is shared and replaced on every update, so
nothing a project writes there survives. Each key's reader and default are documented on the key
in the template.

## Skills

| Skill | Description |
|-------|-------------|
| [install](skills/install/) | Create or top up `.claude/project-context.md` for the plugins installed here: detect values, confirm via AskUserQuestion, never overwrite; re-run after adding a plugin |
| [catchup](skills/catchup/) | Load branch context, show progress, sync with base branch |
| [worktree](skills/worktree/) | Cut a fresh git worktree: branch, deps, env files, project house rules, then hand back the path |
| [commit](skills/commit/) | Small, focused commits matching this project's own message convention, plan kept in step, + push and PR Summary refresh |
| [fix-bug](skills/fix-bug/) | End-to-end bug-fix workflow: reproduce, diagnose, propose, implement, gate on the bundled bug-fix-verifier agent (plus runtime-integrity-reviewer when `bug_runtime_review` is on), and hand off to `/core-skills:pr` |
| [implement-plan](skills/implement-plan/) | Execute a feature plan end-to-end without TASKS.md; runs `/core-skills:review-branch` and acts on its findings before capturing learnings |
| [newbranch](skills/newbranch/) | Create a new branch from this project's integration branch; if an issue tracker is configured, resolve/create the issue and start work on it |
| [next](skills/next/) | Continue through TASKS.md — find next task, execute with TDD flow, mark done |
| [plan-feature](skills/plan-feature/) | Interrogate the developer with codebase-informed questions, then produce PLAN.md and DECISIONS.md; self-gated by the bundled plan-reviewer and surface-reviewer agents |
| [pr](skills/pr/) | Create a pull request with automatic issue feedback; offers `/core-skills:review-branch` when this session has none for HEAD, and gates bug branches on `bug-fix-verifier`'s BUG.md verdict |
| [review-branch](skills/review-branch/) | Full-branch review vs the integration branch: three finders (runtime-integrity, correctness, precedent) in parallel against a shared hunting corpus; reports tagged findings in chat |
| [review-mcp-descriptions](skills/review-mcp-descriptions/) | Improve MCP tool/resource descriptions for Tool Search discoverability |
| [shepard](skills/shepard/) | Drive one PR to green and answered: fix red CI, dispose every review finding, push once per cycle, arm a live watch; reads the repo's own notes via `references.shepard_notes` |
| [sync-worktrees](skills/sync-worktrees/) | Sync every secondary git worktree with the primary: env files, dependencies, optional fast-forward |
| [task-writer](skills/task-writer/) | Break down an approved PLAN.md into phased TASKS.md with a self-administered coverage checklist |

## Agents

Plugins bundle agent definitions the same way they bundle skills — `agents/` at the plugin
root, auto-discovered, no `plugin.json` entry needed.

| Agent | Description |
|-------|-------------|
| [bug-fix-verifier](agents/bug-fix-verifier.md) | Verify a bug fix actually resolves BUG.md's defect and glance at touched files for regressions; spawned by `/core-skills:fix-bug` before PR |
| [correctness-reviewer](agents/correctness-reviewer.md) | Find code that computes the wrong thing on paths the tests never take, and obligations the change created but did not meet — including user-facing text that promises what the code does not do; spawned always by `/core-skills:review-branch` |
| [plan-reviewer](agents/plan-reviewer.md) | Re-apply the module-shape lens independently and check a plan against codebase conventions (enums, auth, arch tests); spawned by `/core-skills:plan-feature` Phase 5 in parallel with surface-reviewer |
| [precedent-reviewer](agents/precedent-reviewer.md) | Check a branch against the repo's standing rules, sibling implementations, its own plan prose, and the CI config that decides what green means; spawned always by `/core-skills:review-branch` |
| [runtime-integrity-reviewer](agents/runtime-integrity-reviewer.md) | Find failures that vanish and guards that got weaker — swallowed errors, partial completion, unchecked boundaries, entry points missing a guard; spawned always by `/core-skills:review-branch`, and by `/core-skills:fix-bug` on bug branches that opt in |
| [surface-reviewer](agents/surface-reviewer.md) | Audit a plan's Security & Cost Surface prose against the seven canonical row questions and the repo's standing rules; spawned by `/core-skills:plan-feature` Phase 5 in parallel with plan-reviewer |

## Design record

`docs/plans/plugin-skills-rework/` in the [claude-2 catalog](https://github.com/script-development/claude)
tracks the decisions behind this plugin — why `.claude/project-context.md` exists, why skills
are bundled into one plugin, and the workflow for converting the next catalog skill.
