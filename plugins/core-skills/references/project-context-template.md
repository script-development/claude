---
# Project Context reference — copy to `.claude/project-context.md` in the consuming
# project and fill in the fields that project needs. Every field is optional: a
# plugin skill that needs a fact it can't find here falls back to its own generic
# default rather than failing. Leave out sections whose skills aren't installed.
#
# This file grows as more catalog skills are converted into project-agnostic plugin
# skills — each conversion adds only the fields *that skill* needs, under a section
# named for the concern (not the skill), so unrelated skills can share a section.
# Don't add a field speculatively; add it when a skill is converted that reads it.
#
# Canonical source: templates/project-context-template.md in the claude-2 catalog. A plugin
# whose skills read this file (e.g. core-skills) ships an identical mirror under its own
# references/ directory, since an installed plugin's consumer never clones this catalog repo.
# The mirror is generated — .githooks/pre-commit copies this file over it automatically
# whenever this file changes. Edit only this copy; never hand-edit a shipped mirror.

# --- Issue tracking (used by: catchup, newbranch) ---
issue_tracker_skill:   # The skill/command that fetches issue details. Defaults to kendo-mcp
                       # (this org's in-house tracker) when unset. Set to a different skill
                       # name if this project uses a different tracker, or to `none` if it
                       # genuinely has no issue-tracker integration.
issue_tracker_project_id: # This project's id within that tracker (e.g. Kendo's numeric
                       # project_id) — only needed when the resolved tracker scopes calls by
                       # project id. Leave unset if the tracker has no such concept, or if
                       # issue_tracker_skill is `none`. Used by: newbranch.

# --- Directories ---
# Single-path overrides for where a skill's own output or artifacts live. Every field here
# shares one contract: a plain path, optionally with a literal {placeholder} substituted (noted
# per field below), read once by the skill(s) named, degrading to that skill's own generic
# default when the field or file is absent — never a hard failure. Add a new field here only
# when a skill hardcodes a directory convention with no override; don't add one speculatively.
plan_dir:              # e.g. docs/plans/{issue_key}/ — this project's plan directory
                       # convention. {issue_key} is substituted literally. Omit to use the
                       # skill's own generic default. Used by: catchup, build-it.
research_dir:          # e.g. docs/research/ — this project's filed-research directory.
                       # Omit to use the default, research/. Used by: research.
retro_dir:             # e.g. docs/retrospectives/ — this project's retro directory.
                       # Omit to use the default, retrospectives/. Used by: retro.
worktree_dir:          # e.g. .claude/worktrees/{slug} — override the default worktree
                       # location. {slug} is substituted literally. Needed when repo tooling
                       # sweeps the whole repo root (a docker build context, a globbing test
                       # runner, IDE indexing), or when the default path is already covered by
                       # this project's own .gitignore (say so under Worktrees > House rules
                       # below — worktree can then skip its own ignore-list write).
                       # Used by: worktree, build-it.

# --- Worktrees (used by: worktree, build-it, commit, sync-worktrees) ---
integration_branch:    # Override when auto-detection (origin/development, origin/develop,
                       # then the remote default branch) would get it wrong for this project.
                       # sync-worktrees auto-detects differently (origin/HEAD, then main, then
                       # master) but reads this field first, same as the others.
                       # If this project's tracker auto-links branches, also document the
                       # issue-key format under House rules below — a truncated or malformed
                       # key silently breaks the auto-link.

# --- Docs (used by: review-branch) ---
doc_paths:             # This project's list of user-facing text prefixes — directory prefixes,
                       # not `**` globs (git reads `<prefix>/**/*.md` as requiring an
                       # intervening directory, so it silently misses `<prefix>/README.md`). May
                       # include a `:(exclude)` pathspec for a sub-tree another reviewer owns.
                       # No generic default: unset means docs-accuracy-reviewer never fires —
                       # there's no universal answer for where a project's user-facing text
                       # lives, unlike issue_tracker_skill's kendo-mcp default (D8).
---

# Project Context

Structured facts that project-agnostic plugin skills read to adapt to this project's
conventions, instead of having those conventions baked into the skill's prose at adoption
time. A skill reads only the fields it needs; a missing file, or a missing field within it,
means "use the generic fallback" — never a hard failure.

## Issue tracking

- `issue_tracker_skill` names the skill this project ships for talking to its issue
  tracker. Unset defaults to `kendo-mcp` — this org's own in-house tracker, a sensible
  default within it even though there's no universal one across orgs — as long as that
  skill is actually installed in the project; otherwise (or if a different tracker is in
  use) set this field explicitly, or to `none` to opt out of tracker integration entirely.
- `issue_tracker_project_id` is this project's id within that tracker (e.g. Kendo's numeric
  `project_id`), for a skill whose calls need to be scoped to one project on a shared
  tenant. Leave unset if the tracker has no such concept, or if there's no tracker
  integration at all.

## Directories

Every field here is a single-scalar path override with the same degrade-to-default contract —
see the frontmatter comments above for what each one overrides and which skill(s) read it. This
section exists so that repetition doesn't accumulate one thin subsection per skill; add a line
here, not a new `##` heading, the next time a skill hardcodes a directory convention.

- `plan_dir` — a branch's planning artifacts (`PLAN.md`, `TASKS.md`, `DECISIONS.md`).
- `research_dir` — filed research reports.
- `retro_dir` — numbered retrospectives.
- `worktree_dir` — where a cut worktree lives; see Worktrees below for the richer,
  worktree-specific knowledge this field's own section still carries.

## Worktrees

`integration_branch` is a simple one-line override — see the frontmatter comments above.
`worktree_dir` lives in Directories above, since it's the same single-scalar-path shape as
`plan_dir`/`research_dir`/`retro_dir`; it's still referenced here in House rules, because the
knowledge of *why* its default might need overriding (a `.gitignore` that already covers it, a
build context that sweeps it) is worktree-specific. Everything below `integration_branch` is
richer, project-verified knowledge that doesn't fit a single scalar, so it lives here as prose
instead: only write down what you've actually verified in this project, with the reason it's
true, not what seems like it should be true. A rule without its *why* goes stale silently, and a
skill reading this section follows it anyway.

### Setup

Exact commands, in order, beyond the generic env-file copy and lockfile-based installs a
plugin skill already does on its own. Then the do-nots, each with its cost — this half
matters more than the commands, because the default is to add setup, not leave it out.

```
# example
cp path/to/.env.example path/to/.env
<install command>
```

- **No `<thing>`.** <What it would buy, and why that's nothing here.>

### Gates

The commands that judge whether a change is safe to ship, per side of the codebase, run from
the worktree root:

| Touched | Commands |
|---|---|
| `<side>` | `<command>`, `<command>` |

Call out any script whose base variant hangs (a watch-mode test runner never returns).

### House rules

Anything a session should know once it's working in a worktree for this project: hooks that
block an edit until a skill is loaded, formatters that run on save (and must never be run by
hand), coverage expectations, shared state a worktree mutates that the primary checkout also
sees (a shared database, cache, or tenant — say what's harmless and what breaks another
branch), and the order skills should run in to ship.

Also the place for two narrower notes, when they apply: the issue-key format this project's
tracker expects if it auto-links branches (a truncated or malformed key silently breaks the
link), and whether `worktree_dir`'s path is already covered by this project's own `.gitignore`
(if so, `worktree` can skip writing its own ignore-list entry).

## Docs

`doc_paths` is this project's list of user-facing text prefixes — directory prefixes, not `**`
globs, for the reason given in the frontmatter comment above. `docs-accuracy-reviewer` (spawned
by `review-branch`) reads it to decide whether it joins a branch's review at all, and which files
it audits when it does. Entries may carry a `:(exclude)` pathspec for a sub-tree another reviewer
owns — passed through unchanged. Leaving the field unset means the reviewer never fires: unlike
`issue_tracker_skill`'s `kendo-mcp` default (D8), there's no generic answer for where a project's
user-facing text lives.

Example:

```yaml
doc_paths:
  - docs/
  - README.md
  - "plugins/*/README.md"
```
