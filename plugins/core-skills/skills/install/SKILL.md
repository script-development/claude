---
name: install
description: |
  Create or top up this project's `.claude/project-context.md` — the one file every installed
  plugin skill (core-skills, kendo-pm, ...) reads for project-specific facts — from the shipped
  template, keeping only the fields the skills actually installed here read. Detects values from
  the repo first and asks (AskUserQuestion) only for what it can't detect or wants confirmed.
  Additive and safe to re-run: never overwrites a value already set. Use whenever the user says
  "install", "set up project context", "configure the plugin", "create project-context.md",
  "init core-skills", just installed a plugin from this marketplace, or added another one (e.g.
  kendo-pm after core-skills) and wants its fields added. Also offer it when another skill
  reports that `.claude/project-context.md` or a field it reads is missing.
---

# Install — set up `.claude/project-context.md`

One file per project serves every plugin from this marketplace (see this plugin's README for why
it's one file and not one per plugin). This skill writes that file for the plugins installed
*here and now*, and tops it up when a plugin is added later. It is the only skill that writes the
file wholesale; every other skill only reads it.

Every field in the file is optional — a reading skill falls back to its own default when a field
or the whole file is absent. So the goal is not to fill in every field: it's to record the facts
where this project **differs** from those defaults. Pinning a value that equals the default is
worse than leaving it unset, because the pinned copy stops following the repo when it changes.

## Step 1: Locate the template and the existing file

The canonical template ships with this plugin at `references/project-context-template.md` (this
plugin's root, two levels above this skill's own directory). If this skill's base directory isn't
known, resolve it:

```bash
tpl=""
for d in "$HOME"/.claude/plugins/cache/*/core-skills/*/references/project-context-template.md; do
  [ -f "$d" ] && tpl=$d   # last match wins: newest cached version
done
echo "tpl=$tpl"
```

No template found — stop: *"install can't find core-skills' project-context template; reinstall
the plugin."*

Then check whether `.claude/project-context.md` exists at the repo root
(`git rev-parse --show-toplevel`). Exists → **update mode** (Step 5). Absent → **create mode**.

## Step 2: Work out which fields apply

Each template section and field carries a `used by:` / `Used by:` list of skill names in its
comment. A field applies when **at least one** skill it names is available in this session — the
session's own skill list (plugin skills appear namespaced, e.g. `core-skills:newbranch`,
`kendo-pm:triage-reports`) is the source of truth, since a disabled plugin's skills don't run
anyway. `~/.claude/plugins/installed_plugins.json` is a cross-check, not the primary signal.

A **checked-in copy** of a reader counts too: a skill at `.claude/skills/<name>/` or
`~/.claude/skills/<name>/`, or an agent at `.claude/agents/<name>.md`, with the same name as a
`used by:` entry. That's the project moving from its own copies to these plugins — `core-skills`
is installed (this skill is running), but a sibling plugin like `kendo-pm` may not be yet, while
the project still runs its own `prepare-issue` or `triage-reports`. The copy itself has its values
baked in and reads nothing, but the plugin version replacing it will. Say in the summary which
fields were kept on a checked-in copy's account, so the user knows they take effect only once
that plugin is installed.

Drop every field, and every `##` body section, none of whose readers is available. Keep the
template's order and its per-field comments for what remains — they are the file's own
documentation for whoever edits it next. Drop the template's header comment block (the "copy to
..." and "Canonical source" lines); it describes the template, not this project's file.

## Step 3: Detect values (in parallel)

For each applicable field, find what the reading skill would get *by default* and whether this
repo has a reason to differ. Only a difference is a candidate value.

| Field | Detect | Candidate when |
|---|---|---|
| `issue_tracker_skill` | Is `kendo-mcp` (or `kendo-pm:kendo-mcp`) available? Any other tracker skill (`*jira*`, `*linear*`, `*github-issues*`)? | `kendo-mcp` absent and another tracker skill present → that skill; no tracker skill at all → ask (`none` vs leave unset) |
| `issue_tracker_project_id` | If Kendo MCP tools are reachable: list projects (`kendo://projects` resource), match on repo name / issue-key prefix from recent branch names (`git branch -a`) | Always a candidate when a match or shortlist exists — there's no default to fall back on |
| `integration_branch` | Run the `worktree` chain: `origin/development`, `origin/develop`, then `git symbolic-ref refs/remotes/origin/HEAD` | Chain result disagrees with where recent PRs actually merge (`gh pr list --state merged -L 20 --json baseRefName`) |
| `plan_dir` | Does `docs/plans/` exist? What do its subfolder names look like? | Planning artifacts live elsewhere, or folders aren't named by issue key |
| `worktree_dir` | Dockerfile/compose build context at repo root, test-runner globs over the whole tree, `.gitignore` already covering a worktree path | Any of those signals |
| `doc_paths` | `docs/`, `README.md`, `*/README.md`, `CHANGELOG.md`, `**/*.md` outside source dirs | Any user-facing text found — this field has **no** default, so unset silently disables docs review |

**Migrating from checked-in skills.** A project moving from its own `.claude/skills/` and
`.claude/agents/` copies to these plugins already has the answers baked into them — the values
the catalog's `{{PLACEHOLDER}}` tokens were substituted with at adoption (`project_id: 1`, a
reviewer's hardcoded `git diff -- site/ .claude/` trigger). Grep those copies for the field's
concept, and when the reading skill or agent is gone, check git history
(`git log --all -- .claude/agents/<name>.md`, then `git show <sha>:<path>`). A deletion is
evidence too: record in the option's description *that* the project retired the reader and why
(from the commit message), since that may mean "leave unset" is the project's own decision.

A detection that fails (no network, no MCP, no `gh`) isn't an error — the field simply has no
candidate and stays unset unless the user supplies one in Step 4.

## Step 4: Confirm with the user

Ask only about fields that have a candidate, or that have no default and no detectable answer.
Everything else stays unset without a question — say so in the summary instead.

Use AskUserQuestion, up to four fields per call, one question per field:

- **Detected value** → options: `Use <value> (Recommended)`, `Leave unset — <what the default
  is>`. The built-in "Other" covers a custom value.
- **Shortlist** (e.g. several Kendo projects) → one option per candidate (max 3) plus `Leave
  unset`.
- **Nothing detectable, no default** → `Leave unset — <consequence>` plus the most plausible
  guess, if any.

Put the evidence in each option's description (*"PRs #41–#60 all merged into `develop`"*), so the
user is confirming a fact, not guessing. If AskUserQuestion is unavailable (a headless run), take
every `(Recommended)` option and list the choices in the summary for review.

**Prose sections** (`## Worktrees` → Setup, Gates, House rules): these hold only knowledge
verified in this project, with its *why*. Don't invent it. Write each applicable subsection's
heading and guidance text, with its example block replaced by `_Not yet recorded._`. Then offer —
once, as a single question — to draft Gates from the project's own scripts (`package.json`
scripts, `composer.json` scripts, `Makefile` targets). A drafted line goes in only after the user
confirms it; a guess recorded here is followed by every skill as if it were verified.

## Step 5: Write

**Create mode** — write `.claude/project-context.md`: frontmatter with the applicable fields
(confirmed values filled in, the rest left as `field:` with its comment, so the user can see what
exists), then the applicable body sections.

**Update mode** — read the existing file first and change it only additively:

- An applicable field missing from the frontmatter → insert it in template order, under its
  section comment, confirmed through Step 4 like any other.
- A field already present — even empty — is the user's: leave its value alone. Run Step 3 for it
  only if it's empty, and only offer a value, never replace one.
- An applicable `##` section missing from the body → append it in template order. An existing
  section is never rewritten, even if the template's wording has since changed.
- A field or section in the file that the template doesn't know (renamed, removed, or
  project-invented) → keep it and mention it in the summary. Don't delete.

Nothing to add → change nothing and say the file is already up to date for the installed
plugins. Don't commit — the file belongs to the project; leave it for the user or `/commit`.

## Step 6: Summarize

```
## .claude/project-context.md — <created | updated | already up to date>

**For:** <installed plugins whose skills read it>
**Set:**   <field>: <value> — <evidence>
**Unset (using defaults):** <field> — <default in a few words>
**Skipped (no reader installed):** <section or field>
**Kept for a checked-in copy:** <field> — read once <plugin> replaces `.claude/skills/<name>/`
**Left alone:** <existing fields/sections, including unknown ones>

Re-run /core-skills:install after installing another plugin from this marketplace.
```

## What this skill never does

- Never overwrites or deletes a value, field, or section already in the file.
- Never writes a prose rule (Setup, Gates, House rules) the user hasn't confirmed.
- Never pins a field to a value that equals its own default.
- Never commits.
