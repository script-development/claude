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

### Deferred — agent/reviewer dependency chain (now resolved except `plan-feature`)

Originally skipped as a unit: `fix-bug`, `pr`, `plan-feature`, `implement-plan`. All four
unconditionally invoke something outside a plain skill-to-skill call — `fix-bug` runs `/pr`
and spawns the `bug-fix-verifier` agent; `pr` and `implement-plan` gate on `/review-branch`,
which itself spawns `runtime-integrity-reviewer` + `precedent-reviewer` (+
`docs-accuracy-reviewer` when triggered); `plan-feature` spawns `plan-reviewer` +
`surface-reviewer` directly. Converting any one of them properly meant first working out
whether plugins bundle agents the same way they bundle skills (confirmed: yes — `agents/` at
the plugin root, auto-discovered, no manifest entry needed) and then auditing the whole
`review-branch` + its three agents as a cluster, since `pr` and `implement-plan` both sit on
top of it. That was a bigger unit of work than one skill at a time, so it was set aside rather
than picked apart skill-by-skill — revisited as its own pass, in dependency order:
`review-branch` (unblocks the cluster), `pr`, `implement-plan`, `fix-bug` (each documented in its
own section below). `plan-feature` is a separate cluster, unrelated to this one, and remains
deferred — see "Up next".

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

- **`research`** — needed one **new field**, `research_dir` (under a new "Research" section):
  the skill hardcoded a `research/` output directory (`ls research/`, `Save to
  research/<name>.md`) with no override, the same shape `plan_dir` already covers for planning
  artifacts but for filed research reports instead. No existing field covered it, so — per Step
  3 of the conversion workflow — added one rather than overloading `plan_dir` for an unrelated
  concern. No `{{PLACEHOLDER}}` tokens, no `Agent()`/`subagent_type` spawns, no reference doc
  hosted by another catalog skill; single-file skill, shipped with the one field substitution
  (D21).

- **`retro`** — needed one **new field**, `retro_dir`, in its own new "Retrospectives" section
  (not folded into "Research" — user's call, D22): the skill hardcoded a `retrospectives/`
  output directory (`ls retrospectives/RETRO-*.md`, `Save to
  retrospectives/RETRO-<NNN>-<short-name>.md`) with no override, the same "hardcoded directory,
  no override" shape as `research`, encountered a second time back to back. Also genericized the
  skill's own Step 4 worked example, which hardcoded an outdated
  `Co-Authored-By: Claude <noreply@anthropic.com>` commit trailer — swapped for the same
  `<attribution trailer, exactly as the harness injects it for this session>` placeholder
  `commit` already established, rather than baking in a stale, session-specific line the skill
  has no business fixing to one value. No `{{PLACEHOLDER}}` tokens, no hard dependency.

- **`review-mcp-descriptions`** — needed **zero changes**, the third confirmed instance of the
  `grill-me`/`memory-hygiene` shape: it finds its target files generically ("search for server
  registration, tool classes, and resource classes in the codebase"), same as `memory-hygiene`
  operates on platform-level conventions rather than a business-domain project. Checked
  specifically because this org's MCP tool definitions live inside the Kendo repo, not this
  catalog — but the skill was already written to review *whatever* MCP server the host codebase
  defines, not Kendo's specifically. The `project_id` strings inside it are illustrative text in
  "before/after" example snippets (what a *bad* tool description looks like), not real
  hardcoding. **Corrects D14**, which listed this skill among "the catalog's other Kendo-shaped
  skills" that hardcode `{{PROJECT_ID}}` — that claim doesn't hold against the file's actual
  content; D14's parenthetical was checked here for the first time rather than re-derived from
  memory, and it doesn't survive the check (D23).

- **`sync-worktrees`** — needed two fixes, neither a new field. (1) **Reused** `integration_branch`
  (established for `worktree`/`build-it`, D11, already reused once by `commit`'s D13): the
  bundled script's `--base` flag and its own auto-detection (`origin/HEAD`, then `main`, then
  `master`) cover the same concept `integration_branch` already names, just with a different
  fallback chain than `worktree`'s. Now reads the field first and passes it as `--base`, falling
  back to the script's own auto-detection when unset — same three-tier priority shape as
  `worktree`'s own lookup, with the script's `--base` flag as a fourth, most-specific tier for a
  one-off override. The template's `integration_branch` "used by" comment was stale (listed only
  `worktree, build-it`, missing `commit`); corrected to list all four consumers while here. (2)
  **Fixed the same `<skill dir>` gap D20 found in `shepard`**: the catalog original hardcoded
  `bash .claude/skills/sync-worktrees/scripts/sync.sh` with no plugin-cache or user-level
  fallback at all (not even the two-tier fallback `shepard` had) — the bundled `sync.sh` would
  never have been found under a plugin install. Fixed by reusing D20's exact resolution snippet
  (D24). The script itself (`scripts/sync.sh`) needed zero changes — already fully generic, no
  Kendo assumptions, verified byte-identical to the catalog original.

### Directories regrouping pass

Collapsed `## Plans`, `## Research`, and `## Retrospectives` — three near-identical
single-field sections (D21, D22) — into one `## Directories` section holding `plan_dir`,
`research_dir`, `retro_dir`, and `worktree_dir` (pulled out of `## Worktrees`, which keeps
`integration_branch` and its own richer prose). User's call, made ahead of converting the
deferred `review-branch` cluster on the expectation that `plan-feature` and `fix-bug` will each
add another directory-shaped field of their own (D25). Also fixed `plan_dir`'s stale "used by"
comment — it named only `catchup`, missing `build-it` (confirmed reading
`plugins/core-skills/skills/build-it/SKILL.md:70`).

### `review-branch` — unblocks the deferred cluster

Converted, bundling all three reviewer agents it unconditionally spawns
(`runtime-integrity-reviewer`, `precedent-reviewer`, `docs-accuracy-reviewer`) into
`plugins/core-skills/agents/` in the same commit — the actual "convert the dependency first"
move D12/Step 5 of the workflow memory call for, since a skill and the agents it always spawns
have to land together for the plugin to stay in a working state at every commit.

Two placeholder tokens needed resolving, one reused an existing field and one didn't:

- **`{{DEFAULT_BRANCH}}` reuses `integration_branch`** (no new field) — the same concept
  `worktree`/`build-it`/`commit`/`sync-worktrees` already read, just a second placeholder token
  naming it in the still-unconverted catalog. Falls back to `worktree`'s own auto-detect chain
  (`origin/development`, `origin/develop`, then the remote default branch) when unset.
- **`{{DOC_PATHS}}` gets a new field, `doc_paths`**, under a new "Docs" section — a list of
  directory-prefix pathspecs (not `**` globs, may carry `:(exclude)` entries), read by
  `docs-accuracy-reviewer` via `review-branch` to decide whether it joins a review at all. No
  generic default exists for "where does this project's user-facing text live", so an unset
  field means the reviewer never fires — not a degraded version of it, an absent one.

Of the three bundled agents, only `docs-accuracy-reviewer` needed changes: its `{{DOC_PATHS}}`
tokens (used both as a concept name and inside literal `git diff ... -- {{DOC_PATHS}}` /
`grep {{DOC_PATHS}}` commands) became `<doc_paths>`, a caller-supplied value the parent skill
resolves and hands over in the spawn prompt — the same pattern `<diff_base>` already used, not a
second project-context read inside the agent itself. `runtime-integrity-reviewer` and
`precedent-reviewer` shipped byte-identical, same as `wireframe-reviewer` (D18) — neither
referenced a `{{PLACEHOLDER}}` token or a Kendo assumption.

Also resolved, before conversion started, a gap the previous handoff flagged in the conversion
workflow: `docs-accuracy-reviewer`'s spawn is conditional, but on the diff's own content, not a
developer's confirmation — 5a's exemption only covers the latter shape. Recorded as workflow
Step 5b (see the `feedback-plugin-skill-conversion-workflow` memory): a diff-content-gated spawn
is still a hard, always-bundle dependency once its condition holds.

`plugins/core-skills/references/plan-directory.md` (D16) was re-synced from the catalog original
per that decision's own instruction — added back the dual-root (`docs/plans/` /
`docs/bugs/`) resolution and `review-branch`'s fallback note, both previously trimmed out because
no bundled consumer needed them yet.

Also fixed, found while updating the root `README.md` Plugins table row for this conversion: that
row had drifted stale independently of this pass — it was still missing `research`, `retro`,
`review-mcp-descriptions`, `shepard`, and `sync-worktrees`, five skills converted in the previous
session that never made it into that one line (the plugin's own README and `plugin.json` were
both kept current; only the catalog root's summary row lagged). Same two-tier staleness pattern
D24/D25 already flagged for "used by" comments, one level up — see D26 in `DECISIONS.md`.

### `pr` — needed zero new fields

Converted. Every one of its four catalog placeholder tokens resolved by **reusing** an existing
field or fixing an internal inconsistency — no new `project-context.md` surface at all:

- **`{{ISSUE_KEY_PREFIX}}`** (Step 3, issue feedback) → the same generic issue-key-shaped regex
  (`[A-Z]+-\d+`) `catchup` and `plan-directory.md` already use, combined with
  `issue_tracker_skill` (D8) to decide whether to run the step at all (`none`, or no such prefix
  on the branch, skips it silently).
- **`{{PROJECT_ID}}`** (Step 3, tracker search scope) → `issue_tracker_project_id` (D14).
- **`{{DOC_PATHS}}`** (Step 4, docs-accuracy trigger and PR-body comment) → `doc_paths` (D26),
  read first with the same "unset skips the whole gate" behaviour `review-branch` established.
- **`{{DEFAULT_BRANCH}}`** (Step 4 only, both occurrences) → **not** a new field or a reuse of
  `integration_branch`. Fixed as an internal inconsistency instead, the same category D13 found
  in `commit`: Step 1 already resolves `<base>` generically (`gh pr view --json baseRefName`,
  falling back to the remote's default branch) and states "every diff/log command below compares
  against `origin/<base>`" — Step 4's docs-accuracy diff was the one command that didn't follow
  that stated rule, diffing against the hard default branch instead. Fixed by reusing `<base>`,
  which also makes the docs-accuracy diff correct on a stacked PR (a PR targeting a non-default
  branch), where the old hardcoded-default read would have included the parent branch's own
  already-reviewed diff. See D27 in `DECISIONS.md`.

Also delegated Step 3's `mcp__kendo__*` tool calls to whatever `issue_tracker_skill` resolves to
(documenting the `kendo-mcp` path concretely, same as `newbranch`/`task-writer` already do)
instead of assuming Kendo unconditionally. Re-synced `pr`'s own fallback bullet into
`plugins/core-skills/references/plan-directory.md`'s "Skill-specific fallbacks" section and
widened its "Which root" note to cover both `review-branch` and `pr` as dual-pipeline consumers.

### `implement-plan` — needed zero new fields, zero placeholder tokens

Converted. The catalog original had no `{{PLACEHOLDER}}` tokens at all and no Kendo assumptions
— the only two things that needed generalizing were structural, not project-specific facts:

- **Step 1's `plan-directory.md` link** — repointed to the shipped copy
  (`../../references/plan-directory.md`), same as every other consumer. `implement-plan` is
  single-root (`docs/plans/` only, per its own "ask the user, don't guess" fallback when nothing
  resolves) — re-synced that fallback bullet into the shared reference alongside `review-branch`'s
  and `pr`'s (D16/D26's standing re-sync instruction).
- **Step 4's testing-skill lookup** — the catalog original hardcoded `Look in .claude/skills/ for
  any skill whose name matches a testing convention`, a copy-adoption-era path assumption that
  doesn't hold for a project that installs its testing skill as a plugin instead. Reworded to
  match `next`'s already-established, path-free phrasing verbatim ("if the project provides a
  domain-specific testing skill, invoke it...") — the two skills are explicitly siblings sharing
  this exact machinery, so this was a genuine missed-sync rather than a judgment call: `next`
  had already solved this when it converted, `implement-plan` just hadn't caught up yet.

Step 7's unconditional `/review-branch` invocation is a real hard dependency under the workflow's
Step 5/6, already satisfied by `review-branch`'s own conversion — no ordering issue.

### `fix-bug` — bundled its one agent; reused `issue_tracker_skill` for a vague spot the
catalog original left unformalized

Converted — the last member of the deferred agent/reviewer cluster. `bug-fix-verifier` (Phase 8's
unconditional spawn) bundled byte-identical into `plugins/core-skills/agents/`, same shape D18/D26
already established for a single clean agent dependency: no `{{PLACEHOLDER}}` tokens, no Kendo
assumptions, no dependency of its own. Its three reference files (`repro-paths.md`,
`bug-md-template.md`, `diagnose-and-propose.md`) shipped byte-identical too — none referenced a
placeholder or a project-specific assumption, the first reference-file set in this rework that
needed zero edits (`task-writer`'s and `wireframe`'s each needed at least one illustrative-example
fix).

The catalog original had no `{{PLACEHOLDER}}` tokens either. Phase 1 ("Read the issue from your
project's issue tracker (Linear, Jira, Kendo, GitHub Issues, etc.)") was already written
generically in prose, but — unlike every other tracker-reading skill in this plugin — never
pointed at the established `issue_tracker_skill` field (D8) at all, leaving "how" entirely
undefined rather than delegated. Formalized it to read `issue_tracker_skill` (defaulting to
`kendo-mcp`, `none` asking the user for the bug's details directly), matching `catchup`'s
read-only degrade style rather than `newbranch`/`pr`'s write-and-spell-out-kendo-mcp style, since
Phase 1 here only reads. No new field — pure reuse of a need every tracker-reading skill in this
plugin already names the same way. `plan-directory.md` needed **no** changes for `fix-bug`: it
creates `docs/bugs/<slug>/` itself (like `plan-feature` creates `docs/plans/`), it doesn't
*resolve* an existing one, so the shared reference's read-time algorithm doesn't apply here. See
D29 in `DECISIONS.md`.

### Up next

Every Generic Skill in the README's table is now converted into `core-skills`. Only
`plan-feature` remains — a separate cluster (spawns `plan-reviewer` + `surface-reviewer`,
unrelated to `review-branch`'s three) still deferred on its own terms; nothing else in this
plugin depends on it. `babysit` stays explicitly skipped (superseded by `shepard`).

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
