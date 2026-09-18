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

# --- Issue tracking (used by: catchup) ---
issue_tracker_skill:   # The skill/command that fetches issue details. Defaults to kendo-mcp
                       # (this org's in-house tracker) when unset. Set to a different skill
                       # name if this project uses a different tracker, or to `none` if it
                       # genuinely has no issue-tracker integration.

# --- Plans (used by: catchup) ---
plan_dir:              # e.g. docs/plans/{issue_key}/ — override for this project's plan
                       # directory convention. {issue_key} is substituted literally.
                       # Omit to use the skill's own generic default.
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

## Plans

- `plan_dir` overrides where a branch's planning artifacts (`PLAN.md`, `TASKS.md`,
  `DECISIONS.md`) live, for projects that don't use the default `docs/plans/{issue_key}/`
  layout. Leave unset to use the default.
