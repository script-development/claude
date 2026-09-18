# Plan — rework catalog skills into project-agnostic plugin skills

## Goal

Convert catalog skills (currently consumed by copy-into-project, with project-specific facts
hand-substituted into `{{PLACEHOLDER}}` tokens at adoption time — see `DECISIONS.md` in this
directory, D2) into plugin skills installed via this repo's marketplace, whose body is byte-
identical for every consumer. Project-specific facts move out of the skill's prose and into a
per-project reference file the skill reads at runtime: `.claude/project-context.md`.

Team lead's one fixed requirement: **one reference file per project**, holding everything every
plugin skill running in that project needs — not one file per skill.

## Scope of this pass

Convert exactly one skill, `catchup`, as the worked example that establishes the pattern the
rest will follow. Chosen because its project-specific surface turned out to be small (it
already pattern-matches issue keys generically rather than baking in a fixed prefix) — good for
proving the mechanism before spending it on a more entangled skill.

### In

- `templates/project-context-template.md` — canonical template for `.claude/project-context.md`.
  Starts with only the fields `catchup` needs (`issue_tracker_skill`, `plan_dir`); grows one
  field at a time as later skills are converted, each field added under a section named for the
  *concern* it serves, not the skill, so unrelated skills can share a section.
- `plugins/core-skills/` — new bundle plugin: `.claude-plugin/plugin.json`,
  `skills/catchup/SKILL.md`. `context-economy` is untouched; `core-skills` is a separate,
  new home for project-agnostic conversions of catalog skills, starting with just `catchup`
  and growing as more are converted (see `DECISIONS.md` D7). The skill's content is the same
  as `skills/catchup/SKILL.md` except: reads `.claude/project-context.md` for `plan_dir`
  (Step 1.4) and `issue_tracker_skill` (Step 2's Issue tracker row) instead of hardcoding
  `docs/plans/<issue-key>/` and `/kendo-mcp`; drops the relative link to
  `../plan-feature/references/plan-directory.md` (a plugin consumer won't have that file on
  disk unless they've *also* adopted the catalog's `plan-feature` skill) in favour of a short
  inlined rationale for staying a simpler lookup.

### Out (open questions — not resolved by this pass)

- **Fate of `skills/catchup/`** (the pre-existing catalog copy). Left in place for now — removing
  it would break any consumer still on copy-adoption rather than the plugin. Revisit once it's
  clear whether plugin adoption is meant to fully replace catalog copies or coexist.
  See `DECISIONS.md` D6.
- **Marketplace registration and README** (`.claude-plugin/marketplace.json`,
  README's Plugins table). Not touched yet — pending sign-off on the plugin's content itself.
  See `DECISIONS.md` D6.
- **When (if ever) `core-skills` splits.** D7 picks one bundle plugin for now, on the
  explicit basis that splitting later is easy; it doesn't set a threshold for when a split
  would be warranted (skill count, unrelated themes emerging, install-size complaints, ...).
- **What happens to the `{{PLACEHOLDER}}` mechanism for skills that stay catalog-only.** This
  pass doesn't touch it — `{{ISSUE_KEY_PREFIX}}`, `{{DEFAULT_BRANCH}}`, `{{PROJECT_ID}}`,
  `{{TENANT}}`, `{{DOC_PATHS}}` keep working exactly as before for every skill not yet converted.
