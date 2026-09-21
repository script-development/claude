# Plan — convert the Kendo PM Skills into a `kendo-pm` plugin

## Goal

Convert the README's Kendo PM Skills table — currently consumed by copy-into-project,
Kendo-specific by design — into plugin skills installed via this repo's marketplace. Of the
table's six skills, four are in scope: `kendo-cli`, `kendo-mcp`, `prepare-issue`,
`triage-reports`. `board-sync` and `lint-issues` are excluded per the team lead — see D2.

## Relationship to `plugin-skills-rework`

This branch (`research/plugin-skills-rework-kendo-pm`) is cut from `research/plugin-skills-rework`
(still unmerged at the time this plan started), which converted the catalog's vendor-neutral
Generic Skills into the `core-skills` plugin — see that branch's own
`docs/plans/plugin-skills-rework/` for the mechanism this plan reuses
(`.claude/project-context.md`, the per-skill conversion workflow) and its full decision history.
This plan does not restate that mechanism; it only records what's specific to converting a
vendor-specific skill cluster.

**Why a separate plugin, not a `core-skills` addition.** Every skill `core-skills` bundles is
vendor-neutral: it reads `.claude/project-context.md` to *decide* which tracker to call, or needs
no tracker at all. The Kendo PM Skills are the tracker implementation itself — useless to a
consumer without a Kendo tenant. Team lead's call: a new plugin, `kendo-pm`, keeps `core-skills`
vendor-neutral and matches the README's own table split (Generic vs. Kendo PM Skills). See D1.

## Rollout approach

Same per-skill workflow as `plugin-skills-rework` (see the `feedback-plugin-skill-conversion-workflow`
memory): check what the skill actually needs, reuse an existing `project-context.md` field/section
before adding a new one — this plugin's own, or `core-skills`' (see below) — add a new one only on
demand, commit per skill. Default order is the README's Kendo PM Skills table, except a skill with
a hard functional dependency on another not-yet-converted skill jumps the queue ahead of it, so
every commit leaves `kendo-pm` in a working state. `board-sync` and `lint-issues` are skipped
entirely (D2), the same "not converting this one" treatment the parent plan gave `babysit`.

**`.claude/project-context.md` ownership.** `core-skills` already owns this file's canonical
template (`templates/project-context-template.md` in the catalog, mirrored into
`plugins/core-skills/references/`). A `kendo-pm` skill that needs a fact already covered by an
existing field (`issue_tracker_project_id`, most likely, for anything that needs to scope calls to
one project on a shared tenant) reads it from there rather than inventing a duplicate — a project
installing both plugins should still only maintain one file. A `kendo-pm`-only field (something no
`core-skills` skill would ever need) gets added to `core-skills`' template anyway, under a new or
existing section, for the same one-file-per-project reason — not forked into a second template
this plugin ships on its own. Revisit only if a fact turns out to make no sense inside
`core-skills`' template at all.

### Converted so far

- **`kendo-mcp`** — converted first, out of alphabetical order: it's the dependency root every
  other Kendo PM skill calls directly or assumes the tool surface of (`board-sync`, `lint-issues`,
  `prepare-issue`, `triage-reports` all call `mcp__kendo__*` tools; others link to its
  `references/issue-templates.md`). Needed **zero `.claude/project-context.md` integration** — it
  discovers its project id at runtime (`kendo://projects`) rather than hardcoding one, the same
  "already generic" shape `grill-me`/`memory-hygiene`/`review-mcp-descriptions` each hit in the
  parent plan for a different reason. Only change: the three illustrative
  `{{ISSUE_KEY_PREFIX}}-00NN` placeholders in `SKILL.md`'s worked examples swapped for
  `PROJ-00NN` — the file's *own* pre-existing generic-issue-key example (already used a few lines
  above, for the `key` field in Common Operations), not the parent plan's `KD-00NN` convention,
  which names a real project code (Kendo's own internal dev project within its own tenant) and so
  is the wrong placeholder for a skill documenting integration with *any* Kendo tenant. See D1.
  Both reference files (`setup.md`, `issue-templates.md`) shipped byte-identical.

- **`kendo-cli`** — needed **zero `.claude/project-context.md` integration** and had no
  `{{PLACEHOLDER}}` tokens to begin with: it already uses `PROJ-0255`-style generic issue-key
  examples throughout, consistent with `kendo-mcp`'s own convention (no fix needed here, unlike
  `kendo-mcp` itself). The one real change: its prose reference to "the kendo-mcp skill's
  `references/issue-templates.md`" became an actual working relative link
  (`../kendo-mcp/references/issue-templates.md`) instead of `core-skills`' generic-description
  workaround — legitimate here because `kendo-cli` and `kendo-mcp` are siblings in the *same*
  plugin, so the link survives an independent install the way it wouldn't have across plugin
  boundaries (see D1's rejected alternative). `kendo-pm` bumped to 0.2.0.

- **`triage-reports`** — the first `kendo-pm` skill to actually need a
  `.claude/project-context.md` field: reused `issue_tracker_project_id` (D14, from the parent
  plan's template) for its six `{{PROJECT_ID}}` occurrences, resolving the "Out" item below.
  Falls back to `kendo-mcp`'s own `kendo://projects` discovery + asking the user when unset,
  rather than failing — the same "ask, don't guess" shape used elsewhere in this rework.
  Reading the field is **not** a runtime dependency on `core-skills` being installed: it's a
  plain scalar in a project-owned file, not a call into another plugin's skill (contrast the
  still-open `/newbranch` question on `prepare-issue`, which genuinely is one). Swapped the
  three `{{ISSUE_KEY_PREFIX}}-XXXX` occurrences for `PROJ-XXXX`, matching `kendo-mcp`'s
  convention. Its `references/decisions-log-template.md` and the `docs/triage/decisions.md`
  output path shipped unchanged — the path is explicitly a fixed cross-consumer convention in
  the skill's own text, not a project-specific fact to externalize. `kendo-pm`'s own README
  gained a real `.claude/project-context.md` section (previously speculative, now describing an
  actual reader). `kendo-pm` bumped to 0.3.0.

### Paused

- **`prepare-issue`** — picked up, then paused before any edits landed: it unconditionally
  invokes `/newbranch` (`core-skills`) once Step 5's repo-state check finds no existing branch —
  a hard dependency under the workflow's Step 5b (repo-state-gated, not a developer
  confirmation), and the first case in this plugin of a genuine *runtime* cross-plugin
  dependency (unlike `triage-reports`' field reuse above, this really does need `core-skills`
  installed for that path to work). User wants to think about how to handle it before
  proceeding — see `docs/plans/plugin-skills-rework-kendo-pm/DECISIONS.md` for the options
  raised, none chosen yet. Also flagged during the read-through, not yet acted on: Step 7 Option
  C hardcodes the new-worktree path (`../{worktree_name}`) rather than reading `worktree_dir`,
  but that field's `{slug}`-substitution contract doesn't obviously fit this skill's `{N}`-based
  naming — needs the same "does the shape actually fit" check `plan-directory.md` already warns
  about for `plan_dir`, not an automatic reuse.

### Out (open questions — not resolved yet)

- **Fate of `skills/kendo-mcp/` and its siblings** (the pre-existing catalog copies), same open
  question the parent plan already carries for `catchup`/`worktree` — left in place for now.
