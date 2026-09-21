# Plan — rework catalog skills into project-agnostic plugin skills

## Goal

Convert catalog skills (currently consumed by copy-into-project, with project-specific facts
hand-substituted into `{{PLACEHOLDER}}` tokens at adoption time — see `DECISIONS.md` in this
directory, D2) into plugin skills installed via this repo's marketplace, whose body is byte-
identical for every consumer. Project-specific facts move out of the skill's prose and into a
per-project reference file the skill reads at runtime: `.claude/project-context.md`.

Team lead's one fixed requirement: **one reference file per project**, holding everything every
plugin skill running in that project needs — not one file per skill.

## Rollout approach

One skill at a time, one commit per skill, all landing on this branch for a single eventual PR.
Default order is the README's Generic Skills table, top to bottom — except a skill with a hard
functional dependency on another not-yet-converted skill jumps the queue ahead of it, so every
commit leaves `core-skills` in a working state (see `DECISIONS.md` D12). `babysit` is skipped
entirely — superseded by `shepard`, no reason to convert it.

Per-skill workflow (see the `feedback-plugin-skill-conversion-workflow` memory for the full
version): check what the skill actually needs, reuse an existing `project-context.md`
field/section before adding a new one, add a new one only on demand, commit per skill.

### Converted so far

- **`catchup`** — worked example. Reads `issue_tracker_skill` (defaults to `kendo-mcp`, this
  org's in-house tracker — D8) and `plan_dir` from `.claude/project-context.md`.
- **`worktree`** — turned out to already be project-agnostic in its detection logic; the actual
  change was moving *where* its per-repo customization lives, from a reference file inside the
  skill's own directory (which doesn't survive a plugin version bump) to
  `.claude/project-context.md`'s new `## Worktrees` section (D10, D11). Reads
  `integration_branch`, `worktree_dir`, and the Worktrees body section.
- **`build-it`** — converted out of README order (it hard-depends on `/worktree`, converted
  just before it — D12). Needed **zero new `project-context.md` fields**: it owns no
  project-specific decisions itself, deferring entirely to `worktree`'s hand-back for the
  integration branch and house rules, to `plan_dir` (already added for `catchup`) for the docs
  convention, and to the project's own `CLAUDE.md`/`/pr` skill for the review label. Confirms
  D10's premise held on a second skill.
- **Registration** — `core-skills` is in `.claude-plugin/marketplace.json` and both READMEs
  (root and the plugin's own) as of this pass; no longer deferred (supersedes D6's deferral).
- **Template shipped with the plugin** — `plugins/core-skills/references/project-context-template.md`
  is a synced copy of the canonical `templates/project-context-template.md`, so a plugin
  consumer who never clones this catalog can still bootstrap their own file (D9).

- **`commit`** — needed zero new fields, but did need a **reuse** of `integration_branch`
  (added for `worktree`): the branch-safety check's hardcoded protected-branch list
  (`main`/`master`/`develop`/`development`) missed a project whose integration branch has a
  different name. Also fixed an internal inconsistency in the original skill — it gathered
  `git log` "for recent commit message style" but then imposed a fixed conventional-commit
  type list regardless of what that showed; now it actually matches the detected convention,
  falling back to conventional commits only when there's no clear pattern (D13).

### Deferred — agent/reviewer dependency chain

Skipped for now, not converted: `fix-bug`, `pr`, `plan-feature`, `implement-plan`. All four
unconditionally invoke something outside a plain skill-to-skill call — `fix-bug` runs `/pr`
and spawns the `bug-fix-verifier` agent; `pr` and `implement-plan` gate on `/review-branch`,
which itself spawns `runtime-integrity-reviewer` + `precedent-reviewer` (+
`docs-accuracy-reviewer` when triggered); `plan-feature` spawns `plan-reviewer` +
`surface-reviewer` directly. Converting any one of them properly means first working out
whether plugins bundle agents the same way they bundle skills (confirmed: yes — `agents/` at
the plugin root, auto-discovered, no manifest entry needed) and then auditing the whole
`review-branch` + its three agents as a cluster, since `pr` and `implement-plan` both sit on
top of it. That's a bigger unit of work than one skill at a time, so it's set aside rather than
picked apart skill-by-skill. Revisit as its own pass.

- **`grill-me`** — needed **zero changes**: already fully project-agnostic as written (grounds
  itself in whatever CLAUDE.md/codebase it finds; writes nothing itself). Its one functional
  dependency, `/build-it`, was already converted, so no ordering issue. Not every skill needs
  the `project-context.md` mechanism — this is the first confirmed case of one that doesn't.

- **`memory-hygiene`** — needed **zero changes**, for a different reason than `grill-me`: it
  operates entirely on Claude Code's own platform-level conventions (the
  `~/.claude/projects/<key>/memory/` store, `.claude/agents/`, `.claude/skills/`, `CLAUDE.md`),
  none of which vary by business-domain project the way an issue tracker or plan directory
  does. No `Agent()` spawns, no invocation of another skill — `claude-md-improver` is only
  mentioned conditionally ("if one is installed"), never called.

### Up next

`newbranch` — next in README's Generic Skills order with no unconverted hard dependency.

### Out (open questions — not resolved yet)

- **Fate of `skills/catchup/` and `skills/worktree/`** (the pre-existing catalog copies). Left
  in place for now — removing either would break any consumer still on copy-adoption rather
  than the plugin. Revisit once it's clear whether plugin adoption is meant to fully replace
  catalog copies or coexist. See `DECISIONS.md` D6.
- **When (if ever) `core-skills` splits.** D7 picks one bundle plugin for now, on the
  explicit basis that splitting later is easy; it doesn't set a threshold for when a split
  would be warranted (skill count, unrelated themes emerging, install-size complaints, ...).
- **What happens to the `{{PLACEHOLDER}}` mechanism for skills that stay catalog-only.** This
  pass doesn't touch it — `{{ISSUE_KEY_PREFIX}}`, `{{DEFAULT_BRANCH}}`, `{{PROJECT_ID}}`,
  `{{TENANT}}`, `{{DOC_PATHS}}` keep working exactly as before for every skill not yet converted.
