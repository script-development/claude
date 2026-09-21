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
- **Registration** — `core-skills` is in `.claude-plugin/marketplace.json` and both READMEs
  (root and the plugin's own) as of this pass; no longer deferred (supersedes D6's deferral).
- **Template shipped with the plugin** — `plugins/core-skills/references/project-context-template.md`
  is a synced copy of the canonical `templates/project-context-template.md`, so a plugin
  consumer who never clones this catalog can still bootstrap their own file (D9).

### Up next

`build-it` — was going to be next in README order, but depends on `/worktree` (now converted).
Per the rollout approach above, `build-it` is next since its dependency is satisfied.

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
