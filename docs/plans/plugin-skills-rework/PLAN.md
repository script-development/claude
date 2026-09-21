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

- **`newbranch`** — needed a **new field**, `issue_tracker_project_id` (D14): the tracker
  project id (`{{PROJECT_ID}}` in the placeholder catalog) that scopes tracker calls, distinct
  from `issue_tracker_skill` (which names *which* tracker). Also generalized: the original
  hardcoded Kendo's MCP tool names unconditionally; the converted version fully delegates
  tracker mechanics to whatever skill `issue_tracker_skill` resolves to (default `kendo-mcp`,
  documented inline since it's the only tracker this catalog actually implements), same
  abstraction boundary `catchup` already established, plus a `none`/unresolved path that skips
  issue linking and just asks for a branch slug (D14).

### Cross-cutting readability pass

Collapsed the repeated "missing file/field degrades, never blocks" explanation that `catchup`,
`worktree`, and `newbranch` had each independently written into their own intro paragraph, into
one shared "Notation" paragraph in `plugins/core-skills/README.md` (D15). Each skill's intro now
states only which fields it reads and links to the README for the mechanism. Also standardized
code-block placeholders to hyphenated English words (`<integration-branch>`, `<project-id>`) —
never the field's literal snake_case name — fixing one stray instance in `newbranch`. Applies
going forward: state which fields, link to the README, don't re-derive the degrade-semantics
sentence.

- **`next`** — no new field needed; every step but Step 1 was already generic. Step 1 pointed
  at `plan-feature/references/plan-directory.md`'s canonical slug-derivation algorithm — a
  reference-doc hosting problem, not a functional dependency on `/plan-feature` itself (which
  doesn't even use the algorithm — it documents it because it owns the directory-naming
  convention, and doesn't need it since it creates the directory and already knows the slug).
  Same D9 pattern as the project-context template: shipped a trimmed copy at
  `plugins/core-skills/references/plan-directory.md` (D16), rather than treating `plan-feature`
  (itself in the deferred cluster) as a blocking dependency.

- **`task-writer`** — no new field needed; reused two already-established patterns rather than
  inventing anything. Its own six `references/*.md` files (task-sizing, quality-gates,
  extraction-workflow, tasks-template, verification, example-frontend-feature — ~700 lines)
  were already fully generic and shipped as-is, with the two illustrative
  `{{ISSUE_KEY_PREFIX}}-0072`-style examples swapped for a concrete-looking one (`KD-0072`,
  matching `newbranch`'s and `plan-directory.md`'s own examples). The Output section's directory
  lookup now reuses the shared `references/plan-directory.md` (D16, added for `next`) instead of
  hardcoding `{{ISSUE_KEY_PREFIX}}-XXXX`; its issue-backfill fallback (no plan directory found at
  all) reuses `issue_tracker_skill` / `issue_tracker_project_id` (D8/D14, added for `newbranch`)
  instead of hardcoding `mcp__kendo__create-issue-tool` and `{{PROJECT_ID}}` unconditionally. No
  hard dependency: the Phase 0 hand-off to `/implement-plan` is conditional on the developer's
  own confirmation (not an unconditional spawn), and the issue-tracker fallback is the same
  optional/conditional shape already established for `newbranch`.

- **`wireframe`** — no new field needed; reused `references/plan-directory.md` (D16) for
  Step 1's directory lookup, same as `next`/`task-writer`. The one new mechanic: `wireframe`
  unconditionally spawns the `wireframe-reviewer` agent every run (Step 5), a "one clean
  prerequisite" dependency in D12's sense, not a cluster — so it's the first skill in this
  rework to actually exercise agent bundling (`plugins/core-skills/agents/`), confirming what
  D12/step 6 of the workflow memory had only established in principle (D18). The agent itself
  needed zero changes — no `{{PLACEHOLDER}}` tokens, no Kendo assumptions, already fully
  project-agnostic. Its three reference files (anti-patterns, wireframes-template,
  issue-board — a 406-line worked example) shipped with two illustrative
  `{{ISSUE_KEY_PREFIX}}` fixes, same treatment as `task-writer`'s references.

- **`shepard`** — needed **no new `project-context.md` field**, for the same "already
  self-contained" reason as `grill-me` and `memory-hygiene`, but via a third mechanism: it doesn't
  read `.claude/project-context.md` at all, because it already has its own per-repo reference-file
  convention (`references/repos/<repo-name>.md`, one per consuming repo, defaulting cleanly when
  absent — the same "missing file degrades, never blocks" contract `.claude/project-context.md`
  itself follows). No `{{PLACEHOLDER}}` tokens, no `Agent()`/`subagent_type` spawns, no reference
  doc hosted by another catalog skill (checked both the relative-link and the mention-vs-depend
  angle per Step 1/5a). Its two bundled scripts (`ci-failures.sh`, `pr-watch.sh`, plus their
  `.test.sh` companions) and its `references/reviewers/crit.md` reviewer contract shipped as-is,
  executable bits preserved. Org-specific PR numbers in code comments (`kendo#2113`,
  `emmie#1297`, `lokalekeuze#273`, …) are audit citations grounding a design decision, the same
  worked-example treatment already given `task-writer`'s and `wireframe`'s reference docs, not
  hardcoded behaviour needing genericization. It **did** need one real fix: its own `<skill dir>`
  self-location logic (checked-in copy vs. user-level install) predated plugins entirely and had
  no candidate path for a plugin-cache install, so `scripts/ci-failures.sh` would have silently
  failed to resolve under the very install path this rework exists to support. Fixed by adopting
  `context-economy`'s already-proven plugin-cache glob (`~/.claude/plugins/cache/*/core-skills/*/skills/shepard`,
  last match wins) as a third candidate, checked-in copy still first (D20).

### Up next

Four Generic Skills remain unconverted and untouched by this rework so far: `research`, `retro`,
`review-mcp-descriptions`, `sync-worktrees`. A quick dependency grep (`Agent(`,
`subagent_type`, `spawn`) turned up nothing in any of the four — no known hard dependency, so any
of them is a valid next pick, pending the same full check (Step 1 of the conversion workflow)
this rework has applied to every skill so far. `babysit` stays explicitly skipped (superseded by
`shepard`, now converted).

`review-branch` — not previously named in "Deferred" above, but it belongs there: it's the
actual owner of the three-agent unconditional spawn (`runtime-integrity-reviewer` +
`precedent-reviewer` + `docs-accuracy-reviewer`) that `pr`, `implement-plan`, and transitively
`fix-bug` gate on. Converting it is the real unblock for that whole cluster — treat it as the
cluster's first move whenever that pass starts, not a sixth independent Generic Skill.

### Tooling: auto-sync the project-context template pair

`.githooks/pre-commit` now copies `templates/project-context-template.md` over
`plugins/core-skills/references/project-context-template.md` on every commit that touches the
canonical file (D19). This replaces the manual-sync duty D9 accepted for that one pair — but
deliberately *not* for `plan-directory.md` (D16): that pair is a curated derivative, not a
mirror, and its catalog-side source (`plan-feature`) retires piecemeal as this rework's own
remaining conversions land, so it stays manual. One-time setup per clone:
`git config core.hooksPath .githooks` (documented in `CLAUDE.md`).

**Not permanent tooling.** If the "Fate of `skills/catchup/`..." question below (D6) ever
resolves toward full catalog retirement, `templates/project-context-template.md` and this hook
both retire in the same pass — the plugin's copy becomes the sole file, with nothing left to
sync.

### Out (open questions — not resolved yet)

- **Fate of `skills/catchup/` and `skills/worktree/`** (the pre-existing catalog copies) — and,
  by extension, `templates/` and `.githooks/pre-commit` (D19). Left in place for now — removing
  any of them would break a consumer still on copy-adoption rather than the plugin. Revisit once
  it's clear whether plugin adoption is meant to fully replace catalog copies or coexist. See
  `DECISIONS.md` D6.
- **When (if ever) `core-skills` splits.** D7 picks one bundle plugin for now, on the
  explicit basis that splitting later is easy; it doesn't set a threshold for when a split
  would be warranted (skill count, unrelated themes emerging, install-size complaints, ...).
- **What happens to the `{{PLACEHOLDER}}` mechanism for skills that stay catalog-only.** This
  pass doesn't touch it — `{{ISSUE_KEY_PREFIX}}`, `{{DEFAULT_BRANCH}}`, `{{PROJECT_ID}}`,
  `{{TENANT}}`, `{{DOC_PATHS}}` keep working exactly as before for every skill not yet converted.
