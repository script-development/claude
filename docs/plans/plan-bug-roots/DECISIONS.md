# Decisions — plan-bug-roots

## D1 — Replace `plan_dir` with `plan_root` / `bug_root`, honoured by every reader and writer; `catchup` joins the shared plan-directory algorithm

**Trigger.** Two `/core-skills:install` trial runs (0.22.0) on 2026-09-23, one in `kendo` (catalog
skills still checked in) and one in `kendo-2` (catalog skills deleted in the working tree). Both
ran against the same plan folders, e.g. `docs/plans/KD-1446-empty-button-allowlist/`. In all 29
plan folders that have a PR, the folder name is exactly that PR's head branch.

- `kendo` noticed `catchup` would look for `docs/plans/KD-1446/` and offered
  `plan_dir: docs/plans/{issue_key}*/`. `catchup` promises literal substitution, so a glob it may
  not expand was written into the file.
- `kendo-2` left `plan_dir` unset without asking, stating that the default `docs/plans/<issue-key>/`
  "is already this repo's convention". It isn't.

Two runs on one repo, two different wrong outcomes on one field. The underlying defect was not in
`install`: `catchup` (key-only lookup, exact `docs/plans/<issue-key>/`) could not find the folders
that `plan-feature`, `task-writer` and `newbranch`'s branch names produce. `plugin-install-skill`
D3 had recorded that "`catchup`'s keyword fallback finds those folders anyway". That fallback only
runs when the branch has *no* issue key, so it never applied to these branches.

**Chosen.**

- **Roots are fields, folder names aren't.** `plan_root` (default `docs/plans`) and `bug_root`
  (default `docs/bugs`): plain paths, no placeholders. The folder inside is the slug the writers
  mint and `references/plan-directory.md` derives, so a writer and a reader can't disagree.
- **One resolution rule.** `references/plan-directory.md` now owns the roots and is cited by every
  finder: `catchup`, `next`, `implement-plan`, `task-writer`, `shepard`, `review-branch`, `pr`.
  The writers (`plan-feature`, `fix-bug`, `task-writer`'s create path) read the same root field.
  The agents that receive a directory (`surface-reviewer`, `bug-fix-verifier`) or exclude one
  (`docs-accuracy-reviewer`) describe it by root, not by the literal default.
- **`catchup` uses the shared algorithm**, with its own fallback in place of step 6 (it summarises,
  so it never asks). This reverses the "Catchup variant (intentional) … don't unify" note that
  `plugin-skills-rework` D16 and D30 relied on. Their reason was that `catchup` needed a *more
  tolerant* lookup. The trial showed the key-only lookup was the less tolerant one.
- **Step 5 refuses to pick between several key-prefix matches** (kendo has `KD-1444-base-button`
  and `KD-1444-shared-chrome`). Previously the rule implied it but didn't say so.
- **`install`:** the `plan_dir` detection row becomes `plan_root` / `bug_root` rows, which detect
  where the `PLAN.md` / `BUG.md` files actually live. A note says folder naming isn't a field. A
  `doc_paths` candidate that contains a root (e.g. `docs/`) gets `:(exclude)` entries for it.
  In update mode, an existing `plan_dir` is kept and reported as replaced.

**Why not drop the field entirely (option b).** The plan and bug folders are the plugin's own
output, so standardising their location isn't an assumption about the project. But a project can
still have a real clash: an existing `docs/` with another meaning, a docs site that publishes
everything under `docs/`, a monorepo, or a large set of existing plans kept elsewhere. That's the
same kind of reason `worktree_dir` exists. Once the resolution rule was shared anyway, adding a
root override that every skill honours cost little.

**Rejected.**

- **Making `plan_dir` a full template (`{issue_key}`, `{slug}`, globs).** This makes the folder name
  configurable, which is exactly what let writers and readers disagree.
- **A single `artifacts_root` for both.** A project that moves plans won't necessarily move bug
  investigations too, and two fields cost one extra comment line.
- **Fixing it in `install` only.** The kendo glob shows why: `install` can only write values, and no
  value fixed a reader that looked in the wrong place.

**Consequences.**

- The template gained `plan_root` / `bug_root` and lost `plan_dir`. The shipped mirror was
  re-copied by hand, because this clone has no `core.hooksPath` set. Both copies are byte-identical.
- core-skills is bumped to 0.23.0.
- The catalog `skills/catchup` (the placeholder version consumed by checked-in projects) still has
  the key-only lookup. That's catalog-side drift for the next catalog sync, not something this
  branch fixes.
- `kendo`'s uncommitted `.claude/project-context.md` has `plan_dir: docs/plans/{issue_key}*/`, which
  no skill reads any more. Delete the line, or let a re-run of `install` report it.

## D2 — Four `install` fixes from the same two trial runs

**Chosen.**

- **Every applicable field gets an outcome.** Step 3 now settles each field as *candidate*,
  *default fits*, *no default, nothing found* or *undetectable*, with evidence, and all of them
  appear in the summary. `kendo` asked about `plan_dir` and `kendo-2` didn't, and nothing in the
  skill made that difference visible. "Default fits" has to say what was checked, which is exactly
  the claim `kendo-2` got wrong.
- **Gates are confirmed as exact text.** After the user accepts the draft, a second question
  carries the text to be written as a `preview`. `kendo-2` did this on its own initiative; `kendo`
  wrote wording the user had only seen summarised. The rule that a drafted line goes in only after
  confirmation now means the user confirmed *that line*.
- **`worktree_dir` checks `.dockerignore`, not `COPY`.** `kendo-2` cleared the nested default
  because the Dockerfile copies only named directories. But the whole build context is sent to the
  daemon before any `COPY` runs, and kendo's root-anchored `backend/vendor` pattern doesn't match a
  nested worktree's copy. The template comment also stopped presenting a `.gitignore` entry as a
  reason to override; that's a House-rules note.
- **The summary lists checked-in copies a plugin now replaces** (`Replaced by plugin`). In `kendo`,
  `.claude/skills/newbranch`, `catchup`, `commit` and others sit next to their `core-skills:`
  counterparts, and the summary said nothing about it. `install` only lists them, never deletes.

**Rejected.** Deleting replaced copies from `install`. `install` writes one file, and removing a
project's skills is the user's call, made once the plugin version has earned trust.
