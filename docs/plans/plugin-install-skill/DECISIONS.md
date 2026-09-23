# Decisions — plugin install skill

## D1 — One `install` skill in `core-skills`, not one per plugin

**Ask.** "Create an install skill as part of the plugin" that builds `.claude/project-context.md`
from the template for whatever repo it runs in, possibly using AskUserQuestion to pick defaults or
ask for field values.

**Chosen.** A single skill, `core-skills:install`, that scopes the file to whatever plugins are
installed. Three facts already on record made one skill enough:

- **One file, one template.** `plugin-skills-rework-kendo-pm` D1 rejected a `kendo-pm` copy of the
  template, and its PLAN.md sends `kendo-pm`-only fields into `core-skills`' template too. A
  per-plugin install skill would have no plugin-specific template to install from.
- **`kendo-pm` depends on `core-skills`** (`plugin-skills-rework-kendo-pm` D4), so the install skill
  is always present wherever `kendo-pm` is.
- **The template already maps fields to readers.** Every field's `used by:` list names the skills
  that read it, and the header already says to leave out sections whose skills aren't installed.
  Checking those names against the session's skill list is enough to scope the file.

**Rejected — one install skill per plugin.** Each copy would need the same logic: parse the shared
file, merge without overwriting, confirm via AskUserQuestion. That's duplicated behavior this
catalog treats as drift, two skills editing one file, and two near-identical `/…:install`
commands for users to choose between. Revisit only if a plugin needs project-context fields
**and** can't depend on `core-skills`. The first fix to try then is adding that dependency.

**Also fixed.** `kendo-pm`'s README still said a `kendo-pm`-only consumer could set the field
"without ever installing `core-skills`", which D4 made impossible. Replaced it with a pointer to
`install`.

## D2 — Detect first, ask second; record only differences from defaults; additive re-runs

**Chosen.**

- **Detect before asking.** Values come from the repo first: git remotes and merged-PR bases, the
  `docs/plans/` layout, doc files, and the Kendo project list when the MCP server is reachable.
- **AskUserQuestion confirms and fills gaps.** It confirms a detected value, with the evidence in
  each option's description, or asks for a field that has no default and nothing detectable.
  "Leave unset" is always offered, because every field degrades to a default.
- **Headless runs skip the questions.** When AskUserQuestion is unavailable, the skill takes the
  recommended options and lists them for review.
- **Never pin a field to its own default.** A pinned copy stops following the repo. For example, a
  pinned `integration_branch` stays put when the default branch moves.
- **Prose sections stay stubs.** Setup, Gates and House rules must hold verified knowledge, so the
  skill writes their headings as `_Not yet recorded._`. It offers to draft Gates from the project's
  own scripts, and each drafted line needs the user's confirmation.
- **Re-runs are additive.** The skill adds missing fields and sections and never overwrites or
  deletes. A field that's present but empty gets an offered value, never a forced one. That makes
  "installed `core-skills`, later added `kendo-pm`" a plain re-run. Today that re-run adds no new
  field, because `issue_tracker_project_id` is also read by `newbranch`. It can still fill that
  field in once the Kendo MCP server is connected.

**Rejected — ask about every field.** Most fields have sensible defaults. A question per field would
invite users to pin defaults, and pinned defaults go stale.

**Deferred — a `SessionStart` hook that nags when the file is missing.** Plugins have no
install-time hook that runs a skill, so `install` stays user-invoked. Skills that read the file
(`catchup`, `worktree`) now point at `/core-skills:install` instead of "copy the template". Other
readers can follow as they're next touched.

**Consequence.** `core-skills` 0.22.0 ships `install`. The template header, both plugin READMEs,
the root README, and the manifest and marketplace descriptions mention it. The template change was
copied to `plugins/core-skills/references/` by hand, because `core.hooksPath` isn't set in this
clone. The two copies are byte-identical.

## D3 — Trial run in `kendo-2`: two detection sources added, catalog decision IDs removed from the template

**Setup.** Ran the skill by hand in the `kendo-2` worktree (branch
`KD-1433-updateteamaction-broadcast-consistency`). Neither `core-skills` nor `kendo-pm` is
installed there; it still runs checked-in copies under `.claude/skills/`, so the run assumed both
plugins were installed. The resulting file had `issue_tracker_project_id: 1` and every other field
unset, and a YAML parser read the frontmatter as intended. It was deleted afterwards: a trial, not
an adoption.

**Chosen — checked-in copies count as readers (Step 2).** Scoping by the session's plugin skills
alone found nothing in `kendo-2`. A skill or agent at `.claude/skills/<name>/`,
`~/.claude/skills/<name>/` or `.claude/agents/<name>.md` whose name matches a `used by:` entry now
keeps its field, and the summary lists those fields separately. They take effect only once the
plugin version replaces the copy.

**Chosen — older skill copies and their git history as a detection source (Step 3).** Both real
answers came from there, not from repo heuristics:

- **`issue_tracker_project_id`:** `project_id: 1` is written into kendo's own `prepare-issue`,
  `triage-reports` and other copies 17 times. No Kendo MCP for that tenant was connected.
- **`doc_paths`:** no transcript ever ran `docs-accuracy-reviewer`. Git history showed kendo's
  original trigger (`site/ .claude/ ':(exclude)site/changelog/entries/'`) in `36c2cd209`. It also
  showed that kendo **deleted** the reviewer a day later in `f4234ec4b` (2026-09-06), folding its
  check into `correctness-reviewer`'s Sins of omission rule, which runs on every branch. The user
  left `doc_paths` unset to match. Repo heuristics had suggested a different, incomplete list
  (`site/docs/` plus READMEs, missing `.claude/` and the site's root pages).

A reader's deletion is now named as evidence the skill should show the user, since "leave unset"
may be the project's own decision.

**Chosen — the template stops citing catalog decisions.** Two `(D8)` references in the `doc_paths`
comment and the Docs section meant nothing once copied into a project's file. Both were replaced
by their reason. A rule in the template's header block now forbids decision IDs and catalog-only
paths below it; the header block itself is removed when the template is copied into a project.
The template change was copied to `plugins/core-skills/references/` by hand; both copies are
byte-identical.

**Other findings, not fixed here:**

- **`plan_dir` can't express `docs/plans/{issue_key}-{slug}/`**, kendo's convention: the field only
  supports `{issue_key}`. `catchup`'s keyword fallback finds those folders anyway, so the field
  stays unset. Revisit when a skill actually misses a plan folder because of this.
- **Gates stays a stub by choice.** `kendo-2`'s `CLAUDE.md` and `/startup` already document its
  gates in more detail, and a second copy would drift.
- **`review-branch` has drifted.** core-skills' version is the older design (score-based, with a
  path-triggered `docs-accuracy-reviewer`). kendo's current version runs `correctness-reviewer`
  and finders with `references/corpus/` hunt lists and no score. Adopting core-skills in kendo
  today would make its review process worse. That needs its own sync pass (kendo → catalog →
  core-skills), outside this branch.
